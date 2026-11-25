//
//  MacBundleInstaller.swift
//  ArcSign
//
//  Unified 5-Method macOS & iOS Sideloading Engine:
//  1. Certless Mac (MacCatalyst Mach-O conversion + MacKeychainShim.dylib + Ad-Hoc codesign)
//  2. WrappedBundle Mac Install (.p12 + .mobileprovision via ZsignSwift)
//  3. Local Xcode / Keychain Identity (codesign + local provisioning profile + WrappedBundle)
//  4. Official macOS iOS App Installer.app handoff (for FairPlay-owned / MDM IPAs)
//  5. Export Signed .ipa / USB-WiFi IDeviceKit / LAN OTA ServerInstaller
//

#if os(macOS)
import Foundation
import AppKit
import CoreServices
import ZsignSwift

enum MacInstallMethodKind: Int, CaseIterable, Identifiable {
	case certlessCatalyst = 0
	case p12WrappedBundle = 1
	case xcodeLocalIdentity = 2
	case officialMacInstaller = 3
	case iosExportOrOTA = 4

	var id: Int { rawValue }

	var title: String {
		switch self {
		case .certlessCatalyst:
			return "1. Certless Mac Install (MacCatalyst + Ad-Hoc)"
		case .p12WrappedBundle:
			return "2. WrappedBundle Mac Install (.p12 + Profile)"
		case .xcodeLocalIdentity:
			return "3. Local Xcode / Apple ID Sign (WrappedBundle)"
		case .officialMacInstaller:
			return "4. Official macOS iOS App Installer.app"
		case .iosExportOrOTA:
			return "5. Export .ipa / Install to iPhone & iPad"
		}
	}

	var subtitle: String {
		switch self {
		case .certlessCatalyst:
			return "No certificate or Apple ID required. Never expires or revokes. Includes Keychain Shim for login support."
		case .p12WrappedBundle:
			return "Runs unmodified iOS binary via ZsignSwift. Requires Mac's UDID in .mobileprovision when SIP is enabled."
		case .xcodeLocalIdentity:
			return "Uses your Mac Keychain Apple Development certificate + Xcode profile for real Apple Keychain entitlements."
		case .officialMacInstaller:
			return "Hands off .ipa to macOS built-in installer. Required for FairPlay-encrypted App Store IPAs you own."
		case .iosExportOrOTA:
			return "Signs with ZsignSwift (.p12 / Ad-Hoc) to export .ipa, install via USB/Wi-Fi (IDeviceKit), or host LAN OTA."
		}
	}

	var icon: String {
		switch self {
		case .certlessCatalyst: return "bolt.shield.fill"
		case .p12WrappedBundle: return "signature"
		case .xcodeLocalIdentity: return "hammer.fill"
		case .officialMacInstaller: return "apple.logo"
		case .iosExportOrOTA: return "iphone.and.arrow.forward"
		}
	}
}

struct IPAPreflightReport {
	let isFairPlayEncrypted: Bool
	let hasArm64Slice: Bool
	let binaryName: String
	let recommendedMethod: MacInstallMethodKind
	let recommendationNote: String
}

enum MacInstallDestination: Hashable, Identifiable {
	case systemApplications
	case userApplications
	case custom(URL)

	static var allCases: [MacInstallDestination] {
		[.systemApplications, .userApplications]
	}

	var id: String { rawValue }

	var rawValue: String {
		switch self {
		case .systemApplications: return "/Applications"
		case .userApplications: return "~/Applications"
		case .custom(let url): return url.path
		}
	}

	var directoryURL: URL {
		switch self {
		case .systemApplications:
			return URL(fileURLWithPath: "/Applications", isDirectory: true)
		case .userApplications:
			let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
			try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			return url
		case .custom(let url):
			try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			return url
		}
	}
}

enum MacBundleInstaller {
	static let officialInstallerURL = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/iOS App Installer.app")

	/// Analyzes an unpacked `.app` directory stored in Ksign's Library and recommends the best sideloading method.
	static func analyzeAppBundle(at appBundleURL: URL, availableCerts: [CertificatePair], xcodeIdentities: [LocalXcodeSigningIdentity]) -> IPAPreflightReport {
		let infoPlistURL = appBundleURL.appendingPathComponent("Info.plist")
		let execName = (NSDictionary(contentsOf: infoPlistURL)?["CFBundleExecutable"] as? String) ?? appBundleURL.deletingPathExtension().lastPathComponent
		let execURL = appBundleURL.appendingPathComponent(execName)

		if let info = try? MacMachOConverter.inspectMachO(at: execURL) {
			if info.isFairPlayEncrypted {
				return IPAPreflightReport(
					isFairPlayEncrypted: true,
					hasArm64Slice: info.hasArm64Slice,
					binaryName: execName,
					recommendedMethod: .officialMacInstaller,
					recommendationNote: "FairPlay DRM detected (cryptid != 0). Only macOS's Official iOS App Installer can run encrypted IPAs tied to your Apple ID."
				)
			}
			if !info.hasArm64Slice {
				return IPAPreflightReport(
					isFairPlayEncrypted: false,
					hasArm64Slice: false,
					binaryName: execName,
					recommendedMethod: .iosExportOrOTA,
					recommendationNote: "No arm64 binary slice detected in \(execName)."
				)
			}
		}

		// Prefer Certless Catalyst by default (zero certs, permanent, never revokes), while noting if Mac-UDID Xcode/p12 is also ready
		if xcodeIdentities.contains(where: \.provisionsThisMac) {
			return IPAPreflightReport(
				isFairPlayEncrypted: false,
				hasArm64Slice: true,
				binaryName: execName,
				recommendedMethod: .certlessCatalyst,
				recommendationNote: "Decrypted arm64 IPA. Method 1 (Certless) runs permanently with zero expiration; Method 3 (Xcode Identity) is also available if native Keychain is needed."
			)
		}

		return IPAPreflightReport(
			isFairPlayEncrypted: false,
			hasArm64Slice: true,
			binaryName: execName,
			recommendedMethod: .certlessCatalyst,
			recommendationNote: "Decrypted arm64 IPA ready for Certless Mac Install (no Enterprise cert needed, never revokes)."
		)
	}

	/// Locates or compiles `MacKeychainShim.dylib` on-the-fly for MacCatalyst (`arm64-apple-ios14.0-macabi`) if not already bundled.
	static func resolveKeychainShimDylib() throws -> URL {
		if let bundled = Bundle.main.url(forResource: "MacKeychainShim", withExtension: "dylib"),
		   FileManager.default.fileExists(atPath: bundled.path) {
			return bundled
		}

		let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			.appendingPathComponent("ArcSign/RuntimeShims", isDirectory: true)
		try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
		let dylibOut = cacheDir.appendingPathComponent("MacKeychainShim.dylib")
		if FileManager.default.fileExists(atPath: dylibOut.path) {
			return dylibOut
		}

		// Compile from bundled/workspace source if running from debug/test environment
		let candidateSources = [
			Bundle.main.url(forResource: "MacKeychainShim", withExtension: "m"),
			URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("KeychainShim/MacKeychainShim.m")
		].compactMap { $0 }

		guard let srcURL = candidateSources.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
			throw MacSideloadError.installerFailed("MacKeychainShim.dylib not found in app bundle resources.")
		}

		let compile = MacMachOConverter.runProcess(
			"/usr/bin/xcrun",
			arguments: [
				"clang",
				"-dynamiclib",
				"-fobjc-arc",
				"-target", "arm64-apple-ios14.0-macabi",
				"-isysroot", sdkPath(),
				"-F/System/iOSSupport/System/Library/Frameworks",
				"-framework", "Foundation",
				"-framework", "Security",
				"-install_name", "@executable_path/Frameworks/MacKeychainShim.dylib",
				srcURL.path,
				"-o", dylibOut.path
			]
		)
		guard compile.exitCode == 0 else {
			throw MacSideloadError.installerFailed("Failed compiling MacKeychainShim.dylib: \(compile.stderr)")
		}
		return dylibOut
	}

	private static func sdkPath() -> String {
		let out = MacMachOConverter.runProcess("/usr/bin/xcrun", arguments: ["--sdk", "macosx", "--show-sdk-path"]).stdout
		return out.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Method 1: Certless MacCatalyst + Keychain Shim + Ad-Hoc Sign

	static func installCertlessCatalystApp(
		sourceAppBundleURL: URL,
		customDisplayName: String? = nil,
		injectKeychainShim: Bool = true,
		destination: MacInstallDestination = .systemApplications
	) async throws -> URL {
		let fm = FileManager.default
		let workDir = fm.temporaryDirectory.appendingPathComponent("ArcSign_Certless_\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
		defer { try? fm.removeItem(at: workDir) }

		let stagingAppURL = workDir.appendingPathComponent(sourceAppBundleURL.lastPathComponent, isDirectory: true)
		try fm.copyItem(at: sourceAppBundleURL, to: stagingAppURL)

		// 1. Convert all Mach-O binaries inside stagingAppURL to MacCatalyst (PLATFORM_MACCATALYST = 6)
		try MacMachOConverter.convertAppBundleToMacCatalyst(appBundleURL: stagingAppURL)

		// 2. Optionally inject MacKeychainShim.dylib so SecItem* calls (-34018) persist locally
		let infoPlistURL = stagingAppURL.appendingPathComponent("Info.plist")
		let infoDict = NSDictionary(contentsOf: infoPlistURL)
		let execName = (infoDict?["CFBundleExecutable"] as? String) ?? stagingAppURL.deletingPathExtension().lastPathComponent
		let mainExecURL = stagingAppURL.appendingPathComponent(execName)

		if injectKeychainShim, fm.fileExists(atPath: mainExecURL.path) {
			let shimSource = try resolveKeychainShimDylib()
			let frameworksDir = stagingAppURL.appendingPathComponent("Frameworks", isDirectory: true)
			try fm.createDirectory(at: frameworksDir, withIntermediateDirectories: true)
			let shimDest = frameworksDir.appendingPathComponent("MacKeychainShim.dylib")
			if fm.fileExists(atPath: shimDest.path) {
				try fm.removeItem(at: shimDest)
			}
			try fm.copyItem(at: shimSource, to: shimDest)
			_ = Zsign.injectDyLib(
				appExecutable: mainExecURL.path,
				with: "@executable_path/Frameworks/MacKeychainShim.dylib",
				weak: true
			)
		}

		// 3. Ensure @executable_path/Frameworks rpath is present on main executable
		let rpathCheck = MacMachOConverter.runProcess("/usr/bin/otool", arguments: ["-l", mainExecURL.path]).stdout
		if !rpathCheck.contains("@executable_path/Frameworks") {
			_ = MacMachOConverter.runProcess(
				"/usr/bin/xcrun",
				arguments: ["install_name_tool", "-add_rpath", "@executable_path/Frameworks", mainExecURL.path]
			)
		}

		// 4. Write SIP-safe macOS/MacCatalyst entitlements
		let entitlementsURL = workDir.appendingPathComponent("CertlessEntitlements.plist")
		let safeEntitlements: [String: Any] = [
			"com.apple.security.network.client": true,
			"com.apple.security.network.server": true,
			"com.apple.security.device.audio-input": true,
			"com.apple.security.device.camera": true,
			"com.apple.security.device.microphone": true,
			"com.apple.security.device.bluetooth": true,
			"com.apple.security.files.user-selected.read-write": true,
			"com.apple.security.files.downloads.read-write": true,
			"com.apple.security.personal-information.location": true
		]
		let entData = try PropertyListSerialization.data(fromPropertyList: safeEntitlements, format: .xml, options: 0)
		try entData.write(to: entitlementsURL)

		// 5. Ad-hoc sign nested frameworks, dylibs, plugins, then root .app bundle
		try adhocSignBundleBottomUp(appBundleURL: stagingAppURL, entitlementsURL: entitlementsURL)

		// 6. Place into /Applications (or ~/Applications fallback)
		let displayName = sanitizeAppName(
			customDisplayName
			?? (infoDict?["CFBundleDisplayName"] as? String)
			?? (infoDict?["CFBundleName"] as? String)
			?? stagingAppURL.deletingPathExtension().lastPathComponent
		)
		let finalAppURL = try moveBundleToApplications(sourceAppURL: stagingAppURL, appName: displayName, preferred: destination)
		stripQuarantineAndRegister(at: finalAppURL)
		return finalAppURL
	}

	private static func adhocSignBundleBottomUp(appBundleURL: URL, entitlementsURL: URL) throws {
		let fm = FileManager.default
		// Sign Frameworks/*.dylib and Frameworks/*.framework first
		let frameworksURL = appBundleURL.appendingPathComponent("Frameworks", isDirectory: true)
		if let items = try? fm.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil) {
			for item in items {
				let res = MacMachOConverter.runProcess("/usr/bin/codesign", arguments: ["--force", "--sign", "-", "--timestamp=none", item.path])
				if res.exitCode != 0 {
					throw MacSideloadError.codesignFailed("Failed signing \(item.lastPathComponent): \(res.stderr)")
				}
			}
		}

		// Sign PlugIns/*.appex if kept, or remove incompatible iOS-only extensions if signing fails
		let pluginsURL = appBundleURL.appendingPathComponent("PlugIns", isDirectory: true)
		if let plugins = try? fm.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil) {
			for plugin in plugins {
				let res = MacMachOConverter.runProcess(
					"/usr/bin/codesign",
					arguments: ["--force", "--sign", "-", "--timestamp=none", "--entitlements", entitlementsURL.path, plugin.path]
				)
				if res.exitCode != 0 {
					try? fm.removeItem(at: plugin)
				}
			}
		}

		// Sign root .app bundle
		let rootSign = MacMachOConverter.runProcess(
			"/usr/bin/codesign",
			arguments: ["--force", "--sign", "-", "--timestamp=none", "--entitlements", entitlementsURL.path, appBundleURL.path]
		)
		guard rootSign.exitCode == 0 else {
			throw MacSideloadError.codesignFailed(rootSign.stderr)
		}
	}

	// MARK: - Method 2: WrappedBundle Mac Install (Signed Payload via ZsignSwift)

	static func installWrappedBundle(
		signedPayloadAppURL: URL,
		customDisplayName: String? = nil,
		destination: MacInstallDestination = .systemApplications
	) async throws -> URL {
		let fm = FileManager.default
		let infoDict = NSDictionary(contentsOf: signedPayloadAppURL.appendingPathComponent("Info.plist"))
		let displayName = sanitizeAppName(
			customDisplayName
			?? (infoDict?["CFBundleDisplayName"] as? String)
			?? (infoDict?["CFBundleName"] as? String)
			?? signedPayloadAppURL.deletingPathExtension().lastPathComponent
		)

		let workDir = fm.temporaryDirectory.appendingPathComponent("ArcSign_Wrapped_\(UUID().uuidString)", isDirectory: true)
		let outerAppURL = workDir.appendingPathComponent("\(displayName).app", isDirectory: true)
		let wrapperDirURL = outerAppURL.appendingPathComponent("Wrapper", isDirectory: true)
		try fm.createDirectory(at: wrapperDirURL, withIntermediateDirectories: true)
		defer { try? fm.removeItem(at: workDir) }

		let innerPayloadName = signedPayloadAppURL.lastPathComponent
		let innerDestURL = wrapperDirURL.appendingPathComponent(innerPayloadName, isDirectory: true)
		try fm.copyItem(at: signedPayloadAppURL, to: innerDestURL)

		// Create relative symlink: WrappedBundle -> Wrapper/<PayloadApp>.app
		let symlinkURL = outerAppURL.appendingPathComponent("WrappedBundle")
		try fm.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: "Wrapper/\(innerPayloadName)")

		let finalAppURL = try moveBundleToApplications(sourceAppURL: outerAppURL, appName: displayName, preferred: destination)
		stripQuarantineAndRegister(at: finalAppURL)
		return finalAppURL
	}

	// MARK: - Method 3: Local Xcode / Keychain Identity + Profile -> WrappedBundle

	static func installWithLocalXcodeIdentity(
		sourceAppBundleURL: URL,
		identity: LocalXcodeSigningIdentity,
		customBundleID: String? = nil,
		customDisplayName: String? = nil,
		destination: MacInstallDestination = .systemApplications
	) async throws -> URL {
		let fm = FileManager.default
		let workDir = fm.temporaryDirectory.appendingPathComponent("ArcSign_XcodeSign_\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
		defer { try? fm.removeItem(at: workDir) }

		let stagingAppURL = workDir.appendingPathComponent(sourceAppBundleURL.lastPathComponent, isDirectory: true)
		try fm.copyItem(at: sourceAppBundleURL, to: stagingAppURL)

		// Remove PlugIns that don't match single-app provisioning profile
		let pluginsURL = stagingAppURL.appendingPathComponent("PlugIns", isDirectory: true)
		if fm.fileExists(atPath: pluginsURL.path) {
			try? fm.removeItem(at: pluginsURL)
		}

		// Align CFBundleIdentifier if profile requires a specific non-wildcard App ID
		let infoPlistURL = stagingAppURL.appendingPathComponent("Info.plist")
		if let plist = NSMutableDictionary(contentsOf: infoPlistURL) {
			let prefix = identity.teamID + "."
			let rawPattern = identity.appIDWildcardOrPrefix.hasPrefix(prefix)
				? String(identity.appIDWildcardOrPrefix.dropFirst(prefix.count))
				: identity.appIDWildcardOrPrefix
			if let customBundleID, !customBundleID.isEmpty {
				plist["CFBundleIdentifier"] = customBundleID
			} else if !rawPattern.contains("*") {
				plist["CFBundleIdentifier"] = rawPattern
			} else if rawPattern.hasSuffix(".*") {
				let base = String(rawPattern.dropLast(2))
				let current = (plist["CFBundleIdentifier"] as? String) ?? "app"
				if !current.hasPrefix(base) {
					plist["CFBundleIdentifier"] = "\(base).\(current.components(separatedBy: ".").last ?? "app")"
				}
			}
			if let customDisplayName, !customDisplayName.isEmpty {
				plist["CFBundleDisplayName"] = customDisplayName
			}
			plist.removeObject(forKey: "UIRequiredDeviceCapabilities")
			plist.removeObject(forKey: "UISupportedDevices")
			plist.write(to: infoPlistURL, atomically: true)
		}

		// Embed .mobileprovision and extract its entitlements
		let embeddedProv = stagingAppURL.appendingPathComponent("embedded.mobileprovision")
		if fm.fileExists(atPath: embeddedProv.path) {
			try fm.removeItem(at: embeddedProv)
		}
		try fm.copyItem(at: identity.profileURL, to: embeddedProv)

		let cmsOut = MacMachOConverter.runProcess("/usr/bin/security", arguments: ["cms", "-D", "-i", identity.profileURL.path]).stdout
		let entitlementsURL = workDir.appendingPathComponent("ProfileEntitlements.plist")
		if let plistData = cmsOut.data(using: .utf8),
		   let profileDict = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
		   let entDict = profileDict["Entitlements"] as? [String: Any] {
			let entData = try PropertyListSerialization.data(fromPropertyList: entDict, format: .xml, options: 0)
			try entData.write(to: entitlementsURL)
		}

		let certSHA1 = identity.id.components(separatedBy: "_").first ?? identity.commonName
		let frameworksURL = stagingAppURL.appendingPathComponent("Frameworks", isDirectory: true)
		if let items = try? fm.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil) {
			for item in items {
				let res = MacMachOConverter.runProcess("/usr/bin/codesign", arguments: ["--force", "--sign", certSHA1, item.path])
				if res.exitCode != 0 {
					throw MacSideloadError.codesignFailed("Failed signing \(item.lastPathComponent): \(res.stderr)")
				}
			}
		}

		var rootArgs = ["--force", "--sign", certSHA1]
		if fm.fileExists(atPath: entitlementsURL.path) {
			rootArgs += ["--entitlements", entitlementsURL.path]
		}
		rootArgs.append(stagingAppURL.path)
		let signRes = MacMachOConverter.runProcess("/usr/bin/codesign", arguments: rootArgs)
		guard signRes.exitCode == 0 else {
			throw MacSideloadError.codesignFailed(signRes.stderr)
		}

		return try await installWrappedBundle(
			signedPayloadAppURL: stagingAppURL,
			customDisplayName: customDisplayName,
			destination: destination
		)
	}

	// MARK: - Method 4: Official macOS `iOS App Installer.app` Handoff

	@MainActor
	static func openWithOfficialMacInstaller(ipaURL: URL) throws {
		guard FileManager.default.fileExists(atPath: officialInstallerURL.path) else {
			throw MacSideloadError.installerFailed("macOS iOS App Installer.app was not found at \(officialInstallerURL.path).")
		}
		_ = MacMachOConverter.runProcess("/usr/bin/xattr", arguments: ["-cr", ipaURL.path])
		let config = NSWorkspace.OpenConfiguration()
		NSWorkspace.shared.open([ipaURL], withApplicationAt: officialInstallerURL, configuration: config, completionHandler: nil)
	}

	// MARK: - Helpers

	private static func sanitizeAppName(_ raw: String) -> String {
		let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
		let cleaned = raw.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
		return cleaned.isEmpty ? "SideloadedApp" : cleaned
	}

	private static func moveBundleToApplications(sourceAppURL: URL, appName: String, preferred: MacInstallDestination) throws -> URL {
		let fm = FileManager.default
		let primaryDir = preferred.directoryURL
		let primaryDest = primaryDir.appendingPathComponent("\(appName).app", isDirectory: true)

		do {
			if fm.fileExists(atPath: primaryDest.path) {
				try fm.removeItem(at: primaryDest)
			}
			try fm.copyItem(at: sourceAppURL, to: primaryDest)
			return primaryDest
		} catch {
			// Fallback to ~/Applications if /Applications requires root elevation
			if preferred == .systemApplications {
				let fallbackDir = MacInstallDestination.userApplications.directoryURL
				let fallbackDest = fallbackDir.appendingPathComponent("\(appName).app", isDirectory: true)
				if fm.fileExists(atPath: fallbackDest.path) {
					try? fm.removeItem(at: fallbackDest)
				}
				try fm.copyItem(at: sourceAppURL, to: fallbackDest)
				return fallbackDest
			}
			throw MacSideloadError.installerFailed(error.localizedDescription)
		}
	}

	static func stripQuarantineAndRegister(at appURL: URL) {
		_ = MacMachOConverter.runProcess("/usr/bin/xattr", arguments: ["-cr", appURL.path])
		LSRegisterURL(appURL as CFURL, true)
	}

	@MainActor
	static func launchApp(at appURL: URL) {
		let config = NSWorkspace.OpenConfiguration()
		NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
	}

	@MainActor
	static func revealInFinder(at url: URL) {
		NSWorkspace.shared.activateFileViewerSelecting([url])
	}
}
#endif
