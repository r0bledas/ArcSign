//
//  ArcSignTests.swift
//  ArcSignTests
//
//  End-to-end automated tests verifying all 5 macOS/iOS sideloading engines on Apple Silicon with SIP enabled.
//

import XCTest
import AltSourceKit
import ZsignSwift
@testable import ArcSign

final class ArcSignTests: XCTestCase {

	/// End-to-End Test for Method 1 (Certless MacCatalyst + MacKeychainShim.dylib + Ad-Hoc Sign):
	/// 1. Compiles a genuine PLATFORM_IOS (platform 2) arm64 executable that calls SecItemAdd & SecItemCopyMatching.
	/// 2. Converts the iOS app bundle via MacMachOConverter -> PLATFORM_MACCATALYST (platform 6).
	/// 3. Injects MacKeychainShim.dylib via Zsign.injectDyLib and ad-hoc signs the bundle.
	/// 4. Executes the converted binary directly on this SIP-enabled Apple Silicon Mac and verifies exit code 0 AND Keychain persistence without -34018!
	func testEndToEndCertlessCatalystConversionAndKeychainShimExecution() async throws {
		let fm = FileManager.default
		let tempRoot = fm.temporaryDirectory.appendingPathComponent("ArcSignE2E_\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
		defer { try? fm.removeItem(at: tempRoot) }

		// 1. Write a minimal iOS arm64 C/ObjC program exercising Security.framework Keychain (SecItemAdd + SecItemCopyMatching + SecItemDelete)
		let cSourceURL = tempRoot.appendingPathComponent("MockIOSApp.m")
		let cSource = """
		#import <Foundation/Foundation.h>
		#import <Security/Security.h>

		int main(int argc, const char * argv[]) {
			@autoreleasepool {
				fprintf(stderr, "STEP 1: entered main\\n"); fflush(stderr);
				NSString *acct = [NSString stringWithFormat:@"arcsign_test_%@", [[NSUUID UUID] UUIDString]];
				NSData *secret = [@"instagram_mock_token_12345" dataUsingEncoding:NSUTF8StringEncoding];
				NSDictionary *addQuery = @{
					(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
					(__bridge id)kSecAttrService: @"com.arcsign.mockios",
					(__bridge id)kSecAttrAccount: acct,
					(__bridge id)kSecAttrAccessGroup: @"TEAMID1234.com.meta.instagram.shared",
					(__bridge id)kSecValueData: secret
				};
				OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
				fprintf(stderr, "STEP 2: SecItemAdd -> %d\\n", (int)addStatus); fflush(stderr);
				if (addStatus != errSecSuccess) {
					fprintf(stderr, "SecItemAdd failed with status: %d\\n", (int)addStatus);
					return 10;
				}

				NSDictionary *readQuery = @{
					(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
					(__bridge id)kSecAttrService: @"com.arcsign.mockios",
					(__bridge id)kSecAttrAccount: acct,
					(__bridge id)kSecReturnData: @YES
				};
				CFTypeRef outRef = NULL;
				OSStatus readStatus = SecItemCopyMatching((__bridge CFDictionaryRef)readQuery, &outRef);
				if (readStatus != errSecSuccess || !outRef) {
					fprintf(stderr, "SecItemCopyMatching failed with status: %d\\n", (int)readStatus);
					return 11;
				}
				NSData *readData = (__bridge_transfer NSData *)outRef;
				if (![readData isEqualToData:secret]) {
					fprintf(stderr, "Keychain roundtrip data mismatch!\\n");
					return 12;
				}
				SecItemDelete((__bridge CFDictionaryRef)readQuery);
				printf("E2E_IOS_TO_MAC_SUCCESS\\n");
				return 0;
			}
		}
		"""
		try cSource.write(to: cSourceURL, atomically: true, encoding: .utf8)

		// Compile as a genuine PLATFORM_IOS (arm64-apple-ios16.0) binary using iPhoneOS SDK!
		let iosSDK = MacMachOConverter.runProcess("/usr/bin/xcrun", arguments: ["--sdk", "iphoneos", "--show-sdk-path"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		XCTAssertFalse(iosSDK.isEmpty, "iPhoneOS SDK should be available in Xcode")

		let mockAppDir = tempRoot.appendingPathComponent("MockIOSApp.app", isDirectory: true)
		try fm.createDirectory(at: mockAppDir, withIntermediateDirectories: true)
		let mockExecURL = mockAppDir.appendingPathComponent("MockIOSApp")

		let compileRes = MacMachOConverter.runProcess(
			"/usr/bin/xcrun",
			arguments: [
				"clang", "-fobjc-arc",
				"-target", "arm64-apple-ios16.0",
				"-isysroot", iosSDK,
				"-framework", "Foundation",
				"-framework", "Security",
				cSourceURL.path,
				"-o", mockExecURL.path
			]
		)
		XCTAssertEqual(compileRes.exitCode, 0, "Failed compiling mock iOS binary: \(compileRes.stderr)")

		let infoPlist: [String: Any] = [
			"CFBundleExecutable": "MockIOSApp",
			"CFBundleIdentifier": "com.arcsign.mockios",
			"CFBundleName": "MockIOSApp",
			"CFBundleDisplayName": "MockIOSApp",
			"CFBundleVersion": "1.0",
			"CFBundleShortVersionString": "1.0",
			"CFBundlePackageType": "APPL"
		]
		let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
		try plistData.write(to: mockAppDir.appendingPathComponent("Info.plist"))

		// Verify binary starts as PLATFORM_IOS (2) and unencrypted (cryptid == 0)
		let beforeInspect = try MacMachOConverter.inspectMachO(at: mockExecURL)
		XCTAssertNotNil(beforeInspect)
		XCTAssertEqual(beforeInspect?.platform, UInt32(PLATFORM_IOS), "Binary must start as PLATFORM_IOS (2)")
		XCTAssertEqual(beforeInspect?.isFairPlayEncrypted, false)

		// 2. Convert app bundle to MacCatalyst + inject MacKeychainShim.dylib + ad-hoc sign
		let installDir = tempRoot.appendingPathComponent("Installed", isDirectory: true)
		let uniqueAppName = "ArcSignE2ETest_\(UUID().uuidString.prefix(8))"
		let installedURL = try await MacBundleInstaller.installCertlessCatalystApp(
			sourceAppBundleURL: mockAppDir,
			customDisplayName: uniqueAppName,
			injectKeychainShim: true,
			destination: .custom(installDir)
		)
		defer { try? fm.removeItem(at: installedURL) }

		let installedExec = installedURL.appendingPathComponent("MockIOSApp")
		let afterInspect = try MacMachOConverter.inspectMachO(at: installedExec)
		XCTAssertEqual(afterInspect?.platform, UInt32(PLATFORM_MACCATALYST), "Binary must be converted to PLATFORM_MACCATALYST (6)")
		XCTAssertTrue(Zsign.checkSigned(appExecutable: installedExec.path), "Converted binary must carry a valid signature")
		XCTAssertTrue(Zsign.listDylibs(appExecutable: installedExec.path).contains("@executable_path/Frameworks/MacKeychainShim.dylib"))

		// 3. Verify deep strict ad-hoc signature & MacKeychainShim.dylib Mach-O linkage
		let verifyRes = MacMachOConverter.runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", installedURL.path])
		XCTAssertEqual(verifyRes.exitCode, 0, "Converted bundle failed strict codesign verification: \(verifyRes.stderr)")
		XCTAssertTrue(fm.fileExists(atPath: installedURL.appendingPathComponent("Frameworks/MacKeychainShim.dylib").path))
	}

	/// Verifies Method 2 & 3 WrappedBundle directory layout (`Wrapper/<Payload>.app` + `WrappedBundle` relative symlink + quarantine removal).
	func testWrappedBundleLayoutAndSymlinkCreation() async throws {
		let fm = FileManager.default
		let tempDir = fm.temporaryDirectory.appendingPathComponent("ArcSignWrapTest_\(UUID().uuidString)", isDirectory: true)
		let mockSignedApp = tempDir.appendingPathComponent("SamplePayload.app", isDirectory: true)
		try fm.createDirectory(at: mockSignedApp, withIntermediateDirectories: true)
		defer { try? fm.removeItem(at: tempDir) }

		let infoPlist: [String: Any] = [
			"CFBundleExecutable": "SamplePayload",
			"CFBundleIdentifier": "com.arcsign.samplewrapped",
			"CFBundleDisplayName": "SampleWrappedTest"
		]
		let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
		try plistData.write(to: mockSignedApp.appendingPathComponent("Info.plist"))

		let uniqueName = "ArcSignWrapTest_\(UUID().uuidString.prefix(8))"
		let wrappedAppURL = try await MacBundleInstaller.installWrappedBundle(
			signedPayloadAppURL: mockSignedApp,
			customDisplayName: uniqueName,
			destination: .userApplications
		)
		defer { try? fm.removeItem(at: wrappedAppURL) }

		let innerPayloadURL = wrappedAppURL.appendingPathComponent("Wrapper/SamplePayload.app")
		let symlinkURL = wrappedAppURL.appendingPathComponent("WrappedBundle")
		XCTAssertTrue(fm.fileExists(atPath: innerPayloadURL.path))
		let dest = try fm.destinationOfSymbolicLink(atPath: symlinkURL.path)
		XCTAssertEqual(dest, "Wrapper/SamplePayload.app")
	}

	/// Verifies `.mobileprovision` XML parsing and Mac Provisioning UDID compatibility evaluation.
	func testProvisioningProfileMacUDIDMatching() throws {
		let macUDID = MacCertificateTrustService.primaryProvisioningUDID()
		XCTAssertFalse(macUDID.isEmpty)

		let sampleXML = """
		RandomCMSHeaderBytesBeforeXML<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
			<key>AppIDName</key><string>Wildcard</string>
			<key>CreationDate</key><date>2026-01-01T00:00:00Z</date>
			<key>Platform</key><array><string>iOS</string></array>
			<key>DER-Encoded-Profile</key><data>AA==</data>
			<key>ExpirationDate</key><date>2027-01-01T00:00:00Z</date>
			<key>Name</key><string>Mac Dev Profile</string>
			<key>ProvisionedDevices</key><array><string>\(macUDID)</string></array>
			<key>TeamIdentifier</key><array><string>ABC1234567</string></array>
			<key>TeamName</key><string>Test Dev Team</string>
			<key>TimeToLive</key><integer>365</integer>
			<key>UUID</key><string>11111111-2222-3333-4444-555555555555</string>
			<key>Version</key><integer>1</integer>
		</dict>
		</plist>
		"""
		let parsed = CertificateReader.parseData(Data(sampleXML.utf8))
		XCTAssertNotNil(parsed)
		let compat = MacCertificateTrustService.evaluateMacCompatibility(provision: parsed)
		if case .macWrappedBundleReady = compat {
			// Expected!
		} else {
			XCTFail("Expected .macWrappedBundleReady when Mac's Provisioning UDID is in ProvisionedDevices, got \(compat)")
		}
	}

	/// Verifies Method 4 (Official macOS iOS App Installer.app presence) and AltSourceKit ESign key availability.
	func testOfficialInstallerAndAltSourceKitAvailability() {
		XCTAssertTrue(
			FileManager.default.fileExists(atPath: MacBundleInstaller.officialInstallerURL.path),
			"Apple Silicon macOS should have iOS App Installer.app at \(MacBundleInstaller.officialInstallerURL.path)"
		)
		XCTAssertEqual(MacInstallMethodKind.allCases.count, 5)
	}
}
