//
//  NativeMacDeviceBridge.swift
//  IDeviceSwift (Lightweight macOS devicectl replacement — 0 MB external binary dependencies)
//

import Foundation
import Combine
import UniformTypeIdentifiers
import OSLog

extension UTType {
	public static let plist = UTType(filenameExtension: "plist", conformingTo: .data) ?? .propertyList
	public static let mobiledevicepairing = UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data) ?? .data
}

extension Notification.Name {
	public static let heartbeat = Notification.Name("FR.heartBeat")
	public static let heartbeatInvalidHost = Notification.Name("FR.heartBeatInvalidHost")
	public static let isStreamingDidChange = Notification.Name("SY.isStreamingDidChange")
}

public class InstallerStatusViewModel: ObservableObject {
	public enum InstallerStatus {
		case none
		case ready
		case sendingManifest
		case sendingPayload
		case installing
		case completed(Result<Void, Error>)
		case broken(Error)
	}

	@Published public var status: InstallerStatus
	@Published public var uploadProgress: Double = 0.0
	@Published public var packageProgress: Double = 0.0
	@Published public var installProgress: Double = 0.0

	public var isIDevice: Bool

	public var overallProgress: Double {
		if isIDevice {
			(installProgress + uploadProgress + packageProgress) / 3.0
		} else {
			(installProgress + packageProgress) / 2.0
		}
	}

	public var isCompleted: Bool {
		if case .completed = status {
			return true
		}
		return false
	}

	public init(status: InstallerStatus = .none, isIdevice: Bool = true) {
		self.status = status
		self.isIDevice = isIdevice
	}
}

public final class HeartbeatManager: @unchecked Sendable {
	public static let shared = HeartbeatManager()
	public init() {}

	public func start(_ forceRestart: Bool = false) {
		DispatchQueue.main.async {
			NotificationCenter.default.post(name: .heartbeat, object: nil)
		}
	}

	public func checkSocketConnection(timeoutInSeconds: Double = 2.0) -> (isConnected: Bool, error: String?) {
		let devices = Self.connectedIOSDevices()
		return (!devices.isEmpty, devices.isEmpty ? "No paired USB/Wi-Fi iOS devices detected by xcrun devicectl." : nil)
	}

	public static func pairingFile() -> String {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			.appendingPathComponent("ArcSign/pairingFile.plist").relativePath
	}

	public static func connectedIOSDevices() -> [(identifier: String, name: String)] {
		#if os(macOS)
		let tmpJSON = FileManager.default.temporaryDirectory.appendingPathComponent("devicectl_\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: tmpJSON) }
		let proc = Process()
		proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		proc.arguments = ["devicectl", "list", "devices", "--json-output", tmpJSON.path]
		proc.standardOutput = Pipe()
		proc.standardError = Pipe()
		try? proc.run()
		proc.waitUntilExit()

		guard let data = try? Data(contentsOf: tmpJSON),
			  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let result = root["result"] as? [String: Any],
			  let devices = result["devices"] as? [[String: Any]] else {
			return []
		}
		return devices.compactMap { dev in
			guard let id = dev["identifier"] as? String else { return nil }
			let props = dev["deviceProperties"] as? [String: Any]
			let name = (props?["name"] as? String) ?? id
			return (id, name)
		}
		#else
		return []
		#endif
	}
}

public class InstallationProxy: Identifiable, ObservableObject {
	public let id = UUID()
	public var viewModel: InstallerStatusViewModel

	public init(viewModel: InstallerStatusViewModel) {
		self.viewModel = viewModel
	}

	/// Installs a signed `.ipa` onto the first connected USB/Wi-Fi iOS/iPadOS device using Apple's native `xcrun devicectl`.
	public func install(at url: URL, suspend: Bool = false) async throws {
		#if os(macOS)
		let devices = HeartbeatManager.connectedIOSDevices()
		guard let target = devices.first else {
			let err = NSError(
				domain: "ArcSign.devicectl",
				code: -1,
				userInfo: [NSLocalizedDescriptionKey: "No connected USB or Wi-Fi iPhone/iPad detected via xcrun devicectl. Connect and trust your iOS device in Finder first, or use Export .ipa / Certless Mac Install."]
			)
			await MainActor.run { self.viewModel.status = .broken(err) }
			throw err
		}

		await MainActor.run {
			self.viewModel.status = .sendingPayload
			self.viewModel.uploadProgress = 0.5
		}

		try await Task.detached(priority: .userInitiated) {
			let proc = Process()
			proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
			proc.arguments = ["devicectl", "device", "install", "app", "--device", target.identifier, url.path]
			let errPipe = Pipe()
			proc.standardOutput = Pipe()
			proc.standardError = errPipe
			try proc.run()
			proc.waitUntilExit()
			if proc.terminationStatus != 0 {
				let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "devicectl install failed"
				throw NSError(domain: "ArcSign.devicectl", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg])
			}
		}.value

		await MainActor.run {
			self.viewModel.uploadProgress = 1.0
			self.viewModel.installProgress = 1.0
			self.viewModel.status = .completed(.success(()))
		}
		#endif
	}
}
