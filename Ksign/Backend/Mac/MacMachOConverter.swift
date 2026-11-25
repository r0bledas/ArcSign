//
//  MacMachOConverter.swift
//  ArcSign
//
//  Inspects and patches iOS ARM64 Mach-O binaries inside .app bundles
//  to run natively as MacCatalyst executables on Apple Silicon macOS with SIP enabled.
//

#if os(macOS)
import Foundation
import MachO

enum MacSideloadError: LocalizedError {
	case fairPlayEncrypted(binaryName: String)
	case missingArm64Slice(binaryName: String)
	case invalidAppBundle(String)
	case machOPatchFailed(String)
	case codesignFailed(String)
	case installerFailed(String)
	case missingCredentials(String)

	var errorDescription: String? {
		switch self {
		case .fairPlayEncrypted(let name):
			return "‘\(name)’ is FairPlay DRM-encrypted (cryptid != 0). Use a decrypted .ipa, or choose Method 4 (Official macOS iOS App Installer) if purchased with your Apple ID."
		case .missingArm64Slice(let name):
			return "‘\(name)’ does not contain an arm64 slice compatible with Apple Silicon."
		case .invalidAppBundle(let msg):
			return "Invalid app bundle: \(msg)"
		case .machOPatchFailed(let msg):
			return "Mach-O conversion failed: \(msg)"
		case .codesignFailed(let msg):
			return "macOS code signing failed: \(msg)"
		case .installerFailed(let msg):
			return "Installation failed: \(msg)"
		case .missingCredentials(let msg):
			return msg
		}
	}
}

struct MachOBinaryInspection {
	let url: URL
	let hasArm64Slice: Bool
	let isFairPlayEncrypted: Bool
	let platform: UInt32 // 1 = macOS, 2 = iOS, 6 = MacCatalyst
}

enum MacMachOConverter {
	/// Inspects a single Mach-O file for arm64 slice, FairPlay encryption (cryptid), and LC_BUILD_VERSION platform.
	static func inspectMachO(at url: URL) throws -> MachOBinaryInspection? {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
		defer { try? handle.close() }
		guard let magicData = try? handle.read(upToCount: 4), magicData.count == 4 else { return nil }
		let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }

		let isMachO = (magic == MH_MAGIC_64 || magic == MH_CIGAM_64 || magic == FAT_MAGIC || magic == FAT_CIGAM)
		guard isMachO else { return nil }

		var data = try Data(contentsOf: url)
		if magic == FAT_MAGIC || magic == FAT_CIGAM {
			guard let thin = extractArm64Slice(from: data) else {
				return MachOBinaryInspection(url: url, hasArm64Slice: false, isFairPlayEncrypted: false, platform: 0)
			}
			data = thin
		}

		guard data.count >= MemoryLayout<mach_header_64>.size else { return nil }
		let header = data.withUnsafeBytes { $0.load(as: mach_header_64.self) }
		guard header.magic == MH_MAGIC_64, header.cputype == CPU_TYPE_ARM64 else {
			return MachOBinaryInspection(url: url, hasArm64Slice: false, isFairPlayEncrypted: false, platform: 0)
		}

		var isEncrypted = false
		var platform: UInt32 = 0
		var offset = MemoryLayout<mach_header_64>.size
		let endOffset = min(data.count, offset + Int(header.sizeofcmds))

		for _ in 0..<header.ncmds {
			guard offset + MemoryLayout<load_command>.size <= endOffset else { break }
			let lc = data.withUnsafeBytes { raw in
				raw.loadUnaligned(fromByteOffset: offset, as: load_command.self)
			}
			guard lc.cmdsize >= MemoryLayout<load_command>.size, offset + Int(lc.cmdsize) <= endOffset else { break }

			if lc.cmd == UInt32(LC_ENCRYPTION_INFO_64),
			   Int(lc.cmdsize) >= MemoryLayout<encryption_info_command_64>.size {
				let enc = data.withUnsafeBytes { raw in
					raw.loadUnaligned(fromByteOffset: offset, as: encryption_info_command_64.self)
				}
				if enc.cryptid != 0 {
					isEncrypted = true
				}
			} else if lc.cmd == UInt32(LC_BUILD_VERSION),
					  Int(lc.cmdsize) >= MemoryLayout<build_version_command>.size {
				let bvc = data.withUnsafeBytes { raw in
					raw.loadUnaligned(fromByteOffset: offset, as: build_version_command.self)
				}
				platform = bvc.platform
			} else if lc.cmd == UInt32(LC_VERSION_MIN_IPHONEOS) && platform == 0 {
				platform = UInt32(PLATFORM_IOS)
			}

			offset += Int(lc.cmdsize)
		}

		return MachOBinaryInspection(
			url: url,
			hasArm64Slice: true,
			isFairPlayEncrypted: isEncrypted,
			platform: platform
		)
	}

	/// Recursively finds all Mach-O binaries inside an `.app` bundle.
	static func resolveMachOBinaries(in appBundleURL: URL) -> [URL] {
		var results: [URL] = []
		let fm = FileManager.default
		guard let enumerator = fm.enumerator(
			at: appBundleURL,
			includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
			options: []
		) else {
			return results
		}

		for case let fileURL as URL in enumerator {
			guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
				  vals.isRegularFile == true,
				  vals.isSymbolicLink != true,
				  (vals.fileSize ?? 0) >= 32 else {
				continue
			}
			let ext = fileURL.pathExtension.lowercased()
			if !ext.isEmpty && ext != "dylib" && ext != "so" {
				continue
			}
			if inspectMachOMagicOnly(at: fileURL) {
				results.append(fileURL)
			}
		}
		return results
	}

	private static func inspectMachOMagicOnly(at url: URL) -> Bool {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
		defer { try? handle.close() }
		guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
		let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
		return magic == MH_MAGIC_64 || magic == MH_CIGAM_64 || magic == FAT_MAGIC || magic == FAT_CIGAM
	}

	/// Converts an entire unpacked iOS `.app` bundle in-place to MacCatalyst (PLATFORM_MACCATALYST = 6).
	static func convertAppBundleToMacCatalyst(appBundleURL: URL) throws {
		let machos = resolveMachOBinaries(in: appBundleURL)
		guard !machos.isEmpty else {
			throw MacSideloadError.invalidAppBundle("No Mach-O executables found in \(appBundleURL.lastPathComponent)")
		}

		for machoURL in machos {
			guard FileManager.default.fileExists(atPath: machoURL.path) else { continue }
			if let info = try inspectMachO(at: machoURL) {
				if info.isFairPlayEncrypted || !info.hasArm64Slice {
					// Tweaked IPAs often leave iOS .appex extensions (in PlugIns/ or Extensions/) encrypted; strip incompatible extensions instead of aborting.
					if let appexURL = enclosingAppexURL(for: machoURL) {
						try? FileManager.default.removeItem(at: appexURL)
						continue
					}
					if info.isFairPlayEncrypted {
						throw MacSideloadError.fairPlayEncrypted(binaryName: machoURL.lastPathComponent)
					}
					throw MacSideloadError.missingArm64Slice(binaryName: machoURL.lastPathComponent)
				}
			}
			try convertSingleMachO(at: machoURL)
		}

		// Ensure main executable has +x permissions and patch Info.plist for desktop compatibility
		let infoPlistURL = appBundleURL.appendingPathComponent("Info.plist")
		if let plistDict = NSMutableDictionary(contentsOf: infoPlistURL) {
			if let execName = plistDict["CFBundleExecutable"] as? String {
				let execURL = appBundleURL.appendingPathComponent(execName)
				try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)
			}
			plistDict.removeObject(forKey: "UIRequiredDeviceCapabilities")
			plistDict.removeObject(forKey: "UISupportedDevices")
			plistDict.removeObject(forKey: "LSRequiresIPhoneOS")
			plistDict["CFBundleSupportedPlatforms"] = ["MacOSX"]
			if plistDict["LSMinimumSystemVersion"] == nil {
				plistDict["LSMinimumSystemVersion"] = "14.0"
			}
			plistDict.write(to: infoPlistURL, atomically: true)
		}

		// Remove embedded.mobileprovision for ad-hoc MacCatalyst execution
		let provisionURL = appBundleURL.appendingPathComponent("embedded.mobileprovision")
		if FileManager.default.fileExists(atPath: provisionURL.path) {
			try? FileManager.default.removeItem(at: provisionURL)
		}
	}

	/// Converts a single Mach-O file to thin arm64 MacCatalyst and remaps `@rpath/libswiftUIKit.dylib`.
	static func convertSingleMachO(at url: URL) throws {
		// Use vtool first when available (Xcode's official Mach-O load-command editor handles code-sig stripping & padding cleanly!)
		var data = try Data(contentsOf: url)
		let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
		if magic == FAT_MAGIC || magic == FAT_CIGAM {
			guard let thin = extractArm64Slice(from: data) else {
				throw MacSideloadError.missingArm64Slice(binaryName: url.lastPathComponent)
			}
			try thin.write(to: url, options: .atomic)
		}

		// Strip existing invalid signature before modifying load commands
		_ = runProcess("/usr/bin/codesign", arguments: ["--remove-signature", url.path])

		// Rewrite build version to MacCatalyst 14.0 via xcrun vtool (or direct binary patch fallback)
		let vtoolResult = runProcess(
			"/usr/bin/xcrun",
			arguments: [
				"vtool",
				"-set-build-version", "maccatalyst", "14.0", "14.0",
				"-replace",
				"-output", url.path,
				url.path
			]
		)
		if vtoolResult.exitCode != 0 {
			var fallbackData = try Data(contentsOf: url)
			try patchBuildVersionInPlace(&fallbackData)
			try fallbackData.write(to: url, options: .atomic)
		}

		// Remap @rpath/libswiftUIKit.dylib -> /System/iOSSupport/usr/lib/swift/libswiftUIKit.dylib if present
		let otoolOut = runProcess("/usr/bin/otool", arguments: ["-L", url.path]).stdout
		if otoolOut.contains("@rpath/libswiftUIKit.dylib") {
			_ = runProcess(
				"/usr/bin/xcrun",
				arguments: [
					"install_name_tool",
					"-change",
					"@rpath/libswiftUIKit.dylib",
					"/System/iOSSupport/usr/lib/swift/libswiftUIKit.dylib",
					url.path
				]
			)
		}
	}

	private static func extractArm64Slice(from data: Data) -> Data? {
		guard data.count >= MemoryLayout<fat_header>.size else { return nil }
		var fatHeader = data.withUnsafeBytes { $0.loadUnaligned(as: fat_header.self) }
		let shouldSwap = (fatHeader.magic == FAT_CIGAM)
		if shouldSwap {
			fatHeader.nfat_arch = fatHeader.nfat_arch.byteSwapped
		}
		var offset = MemoryLayout<fat_header>.size
		for _ in 0..<fatHeader.nfat_arch {
			guard offset + MemoryLayout<fat_arch>.size <= data.count else { break }
			var arch = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: fat_arch.self) }
			if shouldSwap {
				arch.cputype = cpu_type_t(bitPattern: UInt32(bitPattern: arch.cputype).byteSwapped)
				arch.offset = arch.offset.byteSwapped
				arch.size = arch.size.byteSwapped
			}
			if arch.cputype == CPU_TYPE_ARM64 {
				let start = Int(arch.offset)
				let end = start + Int(arch.size)
				guard end <= data.count else { return nil }
				return data.subdata(in: start..<end)
			}
			offset += MemoryLayout<fat_arch>.size
		}
		return nil
	}

	private static func patchBuildVersionInPlace(_ data: inout Data) throws {
		guard data.count >= MemoryLayout<mach_header_64>.size else {
			throw MacSideloadError.machOPatchFailed("Binary too small")
		}
		let header = data.withUnsafeBytes { $0.loadUnaligned(as: mach_header_64.self) }
		var offset = MemoryLayout<mach_header_64>.size
		let endOffset = min(data.count, offset + Int(header.sizeofcmds))

		for _ in 0..<header.ncmds {
			guard offset + MemoryLayout<load_command>.size <= endOffset else { break }
			let lc = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: load_command.self) }
			if lc.cmd == UInt32(LC_BUILD_VERSION), Int(lc.cmdsize) >= MemoryLayout<build_version_command>.size {
				var bvc = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: build_version_command.self) }
				bvc.platform = UInt32(PLATFORM_MACCATALYST)
				bvc.minos = 0x000e0000
				bvc.sdk = 0x000e0000
				withUnsafeBytes(of: &bvc) { raw in
					data.replaceSubrange(offset..<(offset + MemoryLayout<build_version_command>.size), with: raw)
				}
				return
			}
			offset += Int(lc.cmdsize)
		}
	}

	@discardableResult
	private static func enclosingAppexURL(for url: URL) -> URL? {
		var current = url
		while current.path != "/" {
			if current.pathExtension.lowercased() == "appex" {
				return current
			}
			current = current.deletingLastPathComponent()
		}
		return nil
	}

	static func runProcess(_ executable: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: executable)
		proc.arguments = arguments

		// Strip Xcode test/debugger DYLD_* injections so child tools and converted apps run cleanly.
		var env = ProcessInfo.processInfo.environment
		env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
		env.removeValue(forKey: "DYLD_FRAMEWORK_PATH")
		env.removeValue(forKey: "DYLD_LIBRARY_PATH")
		proc.environment = env

		let outPipe = Pipe()
		let errPipe = Pipe()
		proc.standardOutput = outPipe
		proc.standardError = errPipe

		var outData = Data()
		var errData = Data()
		let group = DispatchGroup()

		do {
			try proc.run()
		} catch {
			return (-1, "", error.localizedDescription)
		}

		group.enter()
		DispatchQueue.global(qos: .userInitiated).async {
			outData = outPipe.fileHandleForReading.readDataToEndOfFile()
			group.leave()
		}

		group.enter()
		DispatchQueue.global(qos: .userInitiated).async {
			errData = errPipe.fileHandleForReading.readDataToEndOfFile()
			group.leave()
		}

		proc.waitUntilExit()
		group.wait()

		let outStr = String(data: outData, encoding: .utf8) ?? ""
		let errStr = String(data: errData, encoding: .utf8) ?? ""
		return (proc.terminationStatus, outStr, errStr)
	}
}
#endif
