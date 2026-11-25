//
//  FeatherApp.swift
//  ArcSign (Ksign macOS Port)
//

import SwiftUI
import Nuke
import OSLog
import IDeviceSwift

@main
struct FeatherApp: App {
	#if os(iOS)
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	#elseif os(macOS)
	@NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
	#endif

	let heartbeat = HeartbeatManager.shared
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var accentColorManager = AccentColorManager.shared
	@StateObject var extractManager = ExtractManager.shared
	@StateObject var logsManager = LogsManager.shared
	let storage = Storage.shared

	var body: some Scene {
		WindowGroup {
			if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
				EmptyView()
			} else {
				VStack(spacing: 0) {
					ExtractHeaderView(extractManager: extractManager)
						.transition(.move(edge: .top).combined(with: .opacity))
					DownloadHeaderView(downloadManager: downloadManager)
						.transition(.move(edge: .top).combined(with: .opacity))
					VariedTabbarView()
						.environment(\.managedObjectContext, storage.context)
						.onOpenURL(perform: _handleURL)
						.transition(.move(edge: .top).combined(with: .opacity))
				}
				.tint(accentColorManager.currentAccentColor)
				.animation(.smooth, value: downloadManager.manualDownloads.description)
				.animation(.smooth, value: extractManager.extractItems.description)
				.onReceive(accentColorManager.objectWillChange) { _ in
					accentColorManager.updateGlobalTintColor()
				}
				.onAppear {
					accentColorManager.updateGlobalTintColor()
					if logsManager.isCapturing { logsManager.startCapture() }
				}
			}
		}
		#if os(macOS)
		.defaultSize(width: 1120, height: 740)
		#endif
	}

	private func _handleURL(_ url: URL) {
		if url.scheme == "ksign" || url.scheme == "arcsign" {
			if let fullPath = url.validatedScheme(after: "/source/") {
				FR.handleSource(fullPath) { }
			}
			if let fullPath = url.validatedScheme(after: "/install/"),
			   let downloadURL = URL(string: fullPath) {
				_ = DownloadManager.shared.startDownload(from: downloadURL, id: "FeatherManualDownload_\(UUID().uuidString)")
			}
		} else {
			if url.pathExtension.lowercased() == "ipa" || url.pathExtension.lowercased() == "tipa" {
				if FileManager.default.isFileFromFileProvider(at: url) {
					guard url.startAccessingSecurityScopedResource() else { return }
					FR.handlePackageFile(url) { _ in }
				} else {
					FR.handlePackageFile(url) { _ in }
				}
				return
			}
			if url.pathExtension.lowercased() == "ksign" {
				UIAlertController.showAlertWithOk(
					title: .localized("Error"),
					message: .localized("Ksign certificate file (.ksign) is unsupported, please use .p12 and .mobileprovision instead.")
				)
			}
		}
	}
}

enum AppBootstrapHelper {
	static func bootstrap() {
		createPipeline()
		createDirectories()
		if !UserDefaults.standard.bool(forKey: "hasInitializedBuiltInSources") {
			Storage.shared.addBuiltInSources()
			UserDefaults.standard.set(true, forKey: "hasInitializedBuiltInSources")
		}
		cleanTmp()
	}

	private static func createPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0
		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache")
			let imageCache = Nuke.ImageCache()
			dataCache?.sizeLimit = 500 * 1024 * 1024
			imageCache.costLimit = 100 * 1024 * 1024
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .storeOriginalData
			$0.isStoringPreviewsInMemoryCache = false
		}
		ImagePipeline.shared = pipeline
	}

	private static func createDirectories() {
		let fileManager = FileManager.default
		let directories: [URL] = [
			fileManager.archives,
			fileManager.certificates,
			fileManager.signed,
			fileManager.unsigned,
			fileManager.appWorkspaceDirectory.appendingPathComponent("App").appendingPathComponent("Server")
		]
		for url in directories {
			try? fileManager.createDirectoryIfNeeded(at: url)
		}
	}

	private static func cleanTmp() {
		let fileManager = FileManager.default
		let tmp = fileManager.appWorkspaceDirectory.appendingPathComponent("Tmp")
		if let items = try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
			for item in items {
				try? fileManager.removeFileIfNeeded(at: item)
			}
		}
	}
}

#if os(iOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		AppBootstrapHelper.bootstrap()
		return true
	}
}
#elseif os(macOS)
import AppKit

class MacAppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		AppBootstrapHelper.bootstrap()
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		for url in urls {
			let ext = url.pathExtension.lowercased()
			if ext == "ipa" || ext == "tipa" {
				FR.handlePackageFile(url) { _ in }
			}
		}
	}
}
#endif
