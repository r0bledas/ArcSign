//
//  MacCertificateTrustService.swift
//  ArcSign
//
//  Live macOS Security.framework OCSP revocation verifier, Mac Provisioning UDID reader,
//  Keychain trust helper, and automatic Local Xcode / Apple ID signing identity scanner.
//

#if os(macOS)
import Foundation
import Security
import CryptoKit
import IOKit

struct MacOCSPCheckResult: Sendable {
	enum Status: String, Sendable {
		case valid = "Valid (OCSP Verified)"
		case revoked = "Revoked by Apple"
		case expired = "Expired"
		case unknown = "Unverified / Offline"
		case invalidPassword = "Invalid .p12 Password"
	}

	let status: Status
	let commonName: String
	let issuerName: String
	let expirationDate: Date?
	let isTrustedInKeychain: Bool
	let detailMessage: String
}

struct LocalXcodeSigningIdentity: Identifiable, Hashable, Sendable {
	let id: String // SHA-1 hex fingerprint
	let commonName: String
	let teamID: String
	let teamName: String
	let profileURL: URL
	let profileName: String
	let appIDWildcardOrPrefix: String
	let expirationDate: Date
	let provisionsThisMac: Bool
}

enum MacCertificateCompatibility: Equatable, Sendable {
	case macWrappedBundleReady(reason: String)
	case iosExportOnlyEnterprise(reason: String)
	case iosExportOnlyMissingMacUDID(reason: String)
}

enum MacCertificateTrustService {
	/// Returns both the Apple Silicon Provisioning UDID (`0000XXXX-...`) and Hardware UUID (`IOPlatformUUID`) for matching `.mobileprovision` `ProvisionedDevices`.
	static func currentMacDeviceIdentifiers() -> Set<String> {
		var ids = Set<String>()

		// 1. Query system_profiler SPHardwareDataType for Provisioning UDID & Hardware UUID
		let sp = MacMachOConverter.runProcess("/usr/sbin/system_profiler", arguments: ["SPHardwareDataType"])
		if sp.exitCode == 0 {
			for line in sp.stdout.components(separatedBy: .newlines) {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				if trimmed.hasPrefix("Provisioning UDID:") || trimmed.hasPrefix("Hardware UUID:") {
					if let val = trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces), !val.isEmpty {
						ids.insert(val)
						ids.insert(val.uppercased())
						ids.insert(val.lowercased())
					}
				}
			}
		}

		// 2. Fallback IOKit IOPlatformUUID
		let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
		if service != 0 {
			defer { IOObjectRelease(service) }
			if let uuidCF = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
				ids.insert(uuidCF)
			}
		}

		return ids
	}

	/// Primary display Provisioning UDID for UI display (so users can register their Mac if desired).
	static func primaryProvisioningUDID() -> String {
		let sp = MacMachOConverter.runProcess("/usr/sbin/system_profiler", arguments: ["SPHardwareDataType"])
		for line in sp.stdout.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("Provisioning UDID:"),
			   let val = trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) {
				return val
			}
		}
		return currentMacDeviceIdentifiers().first ?? "Unknown"
	}

	/// Evaluates how a decoded `.mobileprovision` (`Certificate`) behaves on this Apple Silicon Mac.
	static func evaluateMacCompatibility(provision: Certificate?) -> MacCertificateCompatibility {
		guard let provision else {
			return .iosExportOnlyMissingMacUDID(reason: "Could not decode .mobileprovision")
		}

		let macIDs = currentMacDeviceIdentifiers()
		if let devices = provision.ProvisionedDevices {
			let matchesMac = devices.contains { macIDs.contains($0) || macIDs.contains($0.uppercased()) }
			if matchesMac {
				return .macWrappedBundleReady(reason: "Includes this Mac's Provisioning UDID (\(provision.TeamName))")
			}
		}

		if provision.ProvisionsAllDevices == true {
			return .iosExportOnlyEnterprise(
				reason: "Enterprise In-House profile (ProvisionsAllDevices). Great for iOS export/OTA; on macOS with SIP enabled, amfid blocks raw WrappedBundle Enterprise apps—use Method 1 (Certless) for local Mac execution."
			)
		}

		return .iosExportOnlyMissingMacUDID(
			reason: "Profile does not list this Mac's Provisioning UDID (\(primaryProvisioningUDID())). Suitable for iOS export/OTA; use Method 1 (Certless) or Method 3 (Xcode Identity) to run on this Mac."
		)
	}

	/// Performs a live OCSP revocation check against Apple's OCSP servers via macOS `Security.framework` (supports all WWDR G2-G6 & Enterprise CAs).
	static func verifyCertificateOCSPLive(p12URL: URL, password: String) async -> MacOCSPCheckResult {
		await Task.detached(priority: .userInitiated) {
			guard let p12Data = try? Data(contentsOf: p12URL) else {
				return MacOCSPCheckResult(
					status: .unknown,
					commonName: "Unknown",
					issuerName: "Unknown",
					expirationDate: nil,
					isTrustedInKeychain: false,
					detailMessage: "Unable to read .p12 file at \(p12URL.lastPathComponent)"
				)
			}

			let options: [String: Any] = [kSecImportExportPassphrase as String: password]
			var rawItems: CFArray?
			let importStatus = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &rawItems)
			guard importStatus == errSecSuccess,
				  let items = rawItems as? [[String: Any]],
				  let first = items.first,
				  let identityObj = first[kSecImportItemIdentity as String] else {
				return MacOCSPCheckResult(
					status: .invalidPassword,
					commonName: "Unknown",
					issuerName: "Unknown",
					expirationDate: nil,
					isTrustedInKeychain: false,
					detailMessage: "SecPKCS12Import failed (OSStatus \(importStatus)). Check password."
				)
			}

			let identity = identityObj as! SecIdentity
			var certRef: SecCertificate?
			SecIdentityCopyCertificate(identity, &certRef)
			guard let leafCert = certRef else {
				return MacOCSPCheckResult(
					status: .unknown,
					commonName: "Unknown",
					issuerName: "Unknown",
					expirationDate: nil,
					isTrustedInKeychain: false,
					detailMessage: "No X.509 certificate inside PKCS#12 container."
				)
			}

			let commonName = (SecCertificateCopySubjectSummary(leafCert) as String?) ?? "Apple Certificate"
			let chain = (first[kSecImportItemCertChain as String] as? [SecCertificate]) ?? [leafCert]
			let issuerName = chain.count > 1 ? ((SecCertificateCopySubjectSummary(chain[1]) as String?) ?? "Apple CA") : "Apple CA"
			let expirationDate = extractCertificateExpiration(leafCert)

			if let exp = expirationDate, exp < Date() {
				return MacOCSPCheckResult(
					status: .expired,
					commonName: commonName,
					issuerName: issuerName,
					expirationDate: exp,
					isTrustedInKeychain: isCertInKeychain(leafCert),
					detailMessage: "Certificate expired on \(exp.formatted(date: .abbreviated, time: .shortened))."
				)
			}

			let basicPolicy = SecPolicyCreateBasicX509()
			guard let revPolicy = SecPolicyCreateRevocation(kSecRevocationOCSPMethod) else {
				return MacOCSPCheckResult(
					status: .unknown,
					commonName: commonName,
					issuerName: issuerName,
					expirationDate: expirationDate,
					isTrustedInKeychain: isCertInKeychain(leafCert),
					detailMessage: "Failed to construct OCSP revocation policy."
				)
			}

			var trustRef: SecTrust?
			let trustCreate = SecTrustCreateWithCertificates(chain as CFArray, [basicPolicy, revPolicy] as CFArray, &trustRef)
			guard trustCreate == errSecSuccess, let trust = trustRef else {
				return MacOCSPCheckResult(
					status: .unknown,
					commonName: commonName,
					issuerName: issuerName,
					expirationDate: expirationDate,
					isTrustedInKeychain: isCertInKeychain(leafCert),
					detailMessage: "Failed to create SecTrust evaluation context."
				)
			}

			SecTrustSetNetworkFetchAllowed(trust, true)
			var cfError: CFError?
			let isValid = SecTrustEvaluateWithError(trust, &cfError)
			let inKeychain = isCertInKeychain(leafCert)

			if isValid {
				return MacOCSPCheckResult(
					status: .valid,
					commonName: commonName,
					issuerName: issuerName,
					expirationDate: expirationDate,
					isTrustedInKeychain: inKeychain,
					detailMessage: "Certificate chain & live Apple OCSP check passed."
				)
			} else {
				let nsErr = cfError as Error? as NSError?
				let code = nsErr?.code ?? 0
				let desc = nsErr?.localizedDescription ?? "Unknown trust error"
				// errSecCertificateRevoked = -67635 (CSSMERR_TP_CERT_REVOKED = -2147409652)
				if desc.localizedCaseInsensitiveContains("revoked") || code == -67635 || code == -2147409652 {
					return MacOCSPCheckResult(
						status: .revoked,
						commonName: commonName,
						issuerName: issuerName,
						expirationDate: expirationDate,
						isTrustedInKeychain: inKeychain,
						detailMessage: "Apple OCSP reported this certificate as REVOKED (\(desc))."
					)
				}
				return MacOCSPCheckResult(
					status: .unknown,
					commonName: commonName,
					issuerName: issuerName,
					expirationDate: expirationDate,
					isTrustedInKeychain: inKeychain,
					detailMessage: desc
				)
			}
		}.value
	}

	private static func extractCertificateExpiration(_ cert: SecCertificate) -> Date? {
		let keys = [kSecOIDInvalidityDate, kSecOIDX509V1ValidityNotAfter] as CFArray
		guard let vals = SecCertificateCopyValues(cert, keys, nil) as? [CFString: [CFString: Any]],
			  let entry = vals[kSecOIDX509V1ValidityNotAfter],
			  let refTime = entry[kSecPropertyKeyValue] as? TimeInterval else {
			return nil
		}
		return Date(timeIntervalSinceReferenceDate: refTime)
	}

	private static func isCertInKeychain(_ cert: SecCertificate) -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassCertificate,
			kSecValueRef as String: cert,
			kSecMatchLimit as String: kSecMatchLimitOne
		]
		return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
	}

	/// Imports a `.p12` into the user's macOS Login Keychain so `codesign` and Gatekeeper recognize the identity.
	static func importP12IntoLoginKeychain(p12URL: URL, password: String) -> (success: Bool, message: String) {
		let loginKeychain = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Keychains/login.keychain-db").path
		var args = ["import", p12URL.path, "-k", loginKeychain, "-T", "/usr/bin/codesign"]
		if !password.isEmpty {
			args += ["-P", password]
		} else {
			args += ["-P", ""]
		}
		let res = MacMachOConverter.runProcess("/usr/bin/security", arguments: args)
		if res.exitCode == 0 {
			return (true, "Imported certificate into macOS Login Keychain.")
		} else {
			return (false, res.stderr.isEmpty ? res.stdout : res.stderr)
		}
	}

	/// Auto-discovers local Xcode / Apple ID signing identities in macOS Keychain paired with local `.mobileprovision` files!
	static func discoverLocalXcodeIdentities() -> [LocalXcodeSigningIdentity] {
		let macIDs = currentMacDeviceIdentifiers()
		let home = FileManager.default.homeDirectoryForCurrentUser
		let profileDirs = [
			home.appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles"),
			home.appendingPathComponent("Library/MobileDevice/Provisioning Profiles")
		]

		// 1. Gather all valid identities in macOS Keychain via `/usr/bin/security find-identity -v -p codesigning`
		let secOut = MacMachOConverter.runProcess("/usr/bin/security", arguments: ["find-identity", "-v", "-p", "codesigning"]).stdout
		var keychainFingerprints: [String: String] = [:] // SHA1_UPPER -> CommonName
		for line in secOut.components(separatedBy: .newlines) {
			// Format:  1) ABCDEF1234567890... "Apple Development: user@example.com (TEAMID)"
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard let closeParen = trimmed.firstIndex(of: ")"),
				  let firstQuote = trimmed.firstIndex(of: "\""),
				  let lastQuote = trimmed.lastIndex(of: "\""),
				  firstQuote < lastQuote else { continue }
			let shaPart = trimmed[trimmed.index(after: closeParen)..<firstQuote].trimmingCharacters(in: .whitespaces).uppercased()
			let namePart = String(trimmed[trimmed.index(after: firstQuote)..<lastQuote])
			if shaPart.count == 40 {
				keychainFingerprints[shaPart] = namePart
			}
		}

		guard !keychainFingerprints.isEmpty else { return [] }

		var discovered: [LocalXcodeSigningIdentity] = []
		let fm = FileManager.default

		for dir in profileDirs {
			guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
			for file in files where ["mobileprovision", "provisionprofile"].contains(file.pathExtension.lowercased()) {
				guard let decoded = CertificateReader(file).decoded,
					  decoded.ExpirationDate > Date(),
					  let devCerts = decoded.DeveloperCertificates else {
					continue
				}
				let provisionsMac = (decoded.ProvisionedDevices ?? []).contains {
					macIDs.contains($0) || macIDs.contains($0.uppercased())
				} || (decoded.ProvisionsAllDevices == true)

				for certData in devCerts {
					let sha1 = Insecure.SHA1.hash(data: certData).map { String(format: "%02X", $0) }.joined()
					if let commonName = keychainFingerprints[sha1] {
						let appID = (decoded.Entitlements?["application-identifier"]?.value as? String) ?? "*"
						let item = LocalXcodeSigningIdentity(
							id: "\(sha1)_\(decoded.UUID)",
							commonName: commonName,
							teamID: decoded.TeamIdentifier.first ?? "",
							teamName: decoded.TeamName,
							profileURL: file,
							profileName: decoded.Name,
							appIDWildcardOrPrefix: appID,
							expirationDate: decoded.ExpirationDate,
							provisionsThisMac: provisionsMac
						)
						discovered.append(item)
					}
				}
			}
		}

		return discovered.sorted { lhs, rhs in
			if lhs.provisionsThisMac != rhs.provisionsThisMac {
				return lhs.provisionsThisMac && !rhs.provisionsThisMac
			}
			return lhs.expirationDate > rhs.expirationDate
		}
	}
}
#endif
