//
//  UIApplication+exitAndSuspend.swift
//  Loader
//

import Foundation
#if canImport(UIKit)
import UIKit.UIApplication

extension UIApplication {
	public func suspend() {
		CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
		self.perform(#selector(NSXPCConnection.suspend))
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			exit(0)
		}
	}
	public func suspendAndReopen() {
		suspend()
		UIApplication.openApp(with: Bundle.main.bundleIdentifier!)
	}
}
#elseif os(macOS)
import AppKit

public final class UIApplication: @unchecked Sendable {
	public static let shared = UIApplication()
	public let supportsAlternateIcons: Bool = false
	public var alternateIconName: String? { nil }

	public func setAlternateIconName(_ iconName: String?, completionHandler: ((Error?) -> Void)? = nil) {
		if let iconName, let img = NSImage(named: iconName) {
			Task { @MainActor in
				NSApplication.shared.applicationIconImage = img
			}
		}
		completionHandler?(nil)
	}

	public func open(_ url: URL, options: [String: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
		let ok = NSWorkspace.shared.open(url)
		completionHandler?(ok)
	}

	public func canOpenURL(_ url: URL) -> Bool {
		NSWorkspace.shared.urlForApplication(toOpen: url) != nil
	}

	public func suspend() {
		CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
		DispatchQueue.main.async {
			NSApplication.shared.terminate(nil)
		}
	}

	public func suspendAndReopen() {
		let bundleURL = Bundle.main.bundleURL
		let config = NSWorkspace.OpenConfiguration()
		config.createsNewApplicationInstance = true
		NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
			DispatchQueue.main.async {
				NSApplication.shared.terminate(nil)
			}
		}
	}
}
#endif
