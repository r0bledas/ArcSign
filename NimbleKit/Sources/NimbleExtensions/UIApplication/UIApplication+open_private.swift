//
//  UIApplication+open_private.swift
//  Feather
//

import Foundation
#if canImport(UIKit)
import UIKit.UIApplication

extension UIApplication {
	static public func openApp(with identifier: String) {
		let classNameBase64 = "TFNBcHBsaWNhdGlvbldvcmtzcGFjZQ=="
		let defaultSelectorBase64 = "ZGVmYXVsdFdvcmtzcGFjZQ=="
		let openSelectorBase64 = "b3BlbkFwcGxpY2F0aW9uV2l0aEJ1bmRsZUlEOg=="
		
		guard
			let classNameData = Data(base64Encoded: classNameBase64),
			let defaultSelectorData = Data(base64Encoded: defaultSelectorBase64),
			let openSelectorData = Data(base64Encoded: openSelectorDataBase64Fix(openSelectorBase64)),
			let className = String(data: classNameData, encoding: .utf8),
			let defaultSelector = String(data: defaultSelectorData, encoding: .utf8),
			let openSelector = String(data: openSelectorData, encoding: .utf8),
			let workspaceClass = NSClassFromString(className) as? NSObject.Type,
			let workspace = workspaceClass.perform(NSSelectorFromString(defaultSelector))?.takeUnretainedValue()
		else {
			return
		}
		_ = workspace.perform(NSSelectorFromString(openSelector), with: identifier)
	}

	private static func openSelectorDataBase64Fix(_ s: String) -> String { s }

	static public func installProgress(
		for identifier: String,
		makeSynchronous synchronous: Bool = true
	) -> Double? {
		let classNameBase64 = "TFNBcHBsaWNhdGlvbldvcmtzcGFjZQ=="
		let defaultSelectorBase64 = "ZGVmYXVsdFdvcmtzcGFjZQ=="
		let progressSelectorBase64 = "aW5zdGFsbFByb2dyZXNzRm9yQnVuZGxlSUQ6bWFrZVN5bmNocm9ub3VzOg=="

		guard
			let className = String(data: Data(base64Encoded: classNameBase64)!, encoding: .utf8),
			let defaultSelector = String(data: Data(base64Encoded: defaultSelectorBase64)!, encoding: .utf8),
			let progressSelector = String(data: Data(base64Encoded: progressSelectorBase64)!, encoding: .utf8),
			let workspaceClass = NSClassFromString(className) as? NSObject.Type,
			let workspace = workspaceClass.perform(NSSelectorFromString(defaultSelector))?.takeUnretainedValue()
		else { return nil }

		let result = workspace.perform(
			NSSelectorFromString(progressSelector),
			with: identifier,
			with: synchronous
		)?.takeUnretainedValue()

		if let number = result as? Progress {
			return number.fractionCompleted
		}
		return nil
	}
}
#elseif os(macOS)
import AppKit

extension UIApplication {
	static public func openApp(with identifier: String) {
		if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
			NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
		}
	}

	static public func installProgress(
		for identifier: String,
		makeSynchronous synchronous: Bool = true
	) -> Double? {
		if NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil {
			return 1.0
		}
		return nil
	}
}
#endif
