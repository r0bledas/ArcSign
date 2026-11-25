//
//  UIAlertController+Alerts.swift
//  NimbleKit
//

import Foundation
#if canImport(UIKit)
import UIKit.UIAlertController

extension UIAlertController {
	static public func showAlertWithCancel(
		_ presenter: UIViewController = UIApplication.topViewController()!,
		_ popoverFromView: UIView? = nil,
		title: String?,
		message: String?,
		style: UIAlertController.Style = .alert,
		actions: [UIAlertAction]
	) {
		var actions = actions
		actions.append(UIAlertAction(title: .localized("Cancel"), style: .cancel, handler: nil))
		showAlert(presenter, popoverFromView, title: title, message: message, style: style, actions: actions)
	}

	static public func showAlertWithOk(
		_ presenter: UIViewController = UIApplication.topViewController()!,
		_ popoverFromView: UIView? = nil,
		title: String?,
		message: String?,
		style: UIAlertController.Style = .alert,
		isCancel: Bool = false,
		thankYou: Bool = false,
		action: (() -> Void)? = nil
	) {
		let alertAction = UIAlertAction(
			title: thankYou ? "Thank You!" : "OK",
			style: isCancel ? .cancel : .default,
			handler: { _ in if !isCancel { action?() } }
		)
		showAlert(presenter, popoverFromView, title: title, message: message, style: style, actions: [alertAction])
	}

	static public func showAlertWithRestart(
		_ presenter: UIViewController = UIApplication.topViewController()!,
		_ popoverFromView: UIView? = nil,
		title: String?,
		message: String?,
		style: UIAlertController.Style = .alert
	) {
		let actions = [
			UIAlertAction(title: "Suspend", style: .default) { _ in UIApplication.shared.suspend() },
			UIAlertAction(title: "Later", style: .cancel, handler: nil)
		]
		showAlert(presenter, popoverFromView, title: title, message: message, style: style, actions: actions)
	}

	static public func showAlert(
		_ presenter: UIViewController = UIApplication.topViewController()!,
		_ popoverFromView: UIView? = nil,
		title: String?,
		message: String?,
		style: UIAlertController.Style = .alert,
		actions: [UIAlertAction]
	) {
		let alert = Self(title: title, message: message, preferredStyle: style)
		actions.forEach { alert.addAction($0) }
		if style == .actionSheet, let popover = alert.popoverPresentationController, let view = popoverFromView {
			popover.sourceView = view
			popover.sourceRect = view.bounds
			popover.permittedArrowDirections = .any
		}
		presenter.present(alert, animated: true)
	}

	static public func showAlertWithTextBox(
		_ presenter: UIViewController = UIApplication.topViewController()!,
		_ popoverFromView: UIView? = nil,
		title: String?,
		message: String?,
		textFieldPlaceholder: String?,
		textFieldText: String = "",
		submit: String?,
		cancel: String?,
		style: UIAlertController.Style = .alert,
		onSubmit: @escaping (String) -> Void
	) {
		let alert = Self(title: title, message: message, preferredStyle: style)
		alert.addTextField { textField in
			textField.placeholder = textFieldPlaceholder
			textField.text = textFieldText
		}
		alert.addAction(UIAlertAction(title: cancel, style: .cancel, handler: nil))
		alert.addAction(UIAlertAction(title: submit, style: .default) { _ in
			onSubmit(alert.textFields?.first?.text ?? "")
		})
		if style == .actionSheet, let popover = alert.popoverPresentationController, let view = popoverFromView {
			popover.sourceView = view
			popover.sourceRect = view.bounds
			popover.permittedArrowDirections = .any
		}
		presenter.present(alert, animated: true)
	}
}
#elseif os(macOS)
import AppKit

public final class UIAlertController {
	public enum Style {
		case alert
		case actionSheet
	}

	static public func showAlertWithCancel(
		_ presenter: NSViewController? = nil,
		_ popoverFromView: NSView? = nil,
		title: String?,
		message: String?,
		style: Style = .alert,
		actions: [UIAlertAction]
	) {
		var allActions = actions
		allActions.append(UIAlertAction(title: .localized("Cancel"), style: .cancel, handler: nil))
		showAlert(presenter, popoverFromView, title: title, message: message, style: style, actions: allActions)
	}

	static public func showAlertWithOk(
		_ presenter: NSViewController? = nil,
		_ popoverFromView: NSView? = nil,
		title: String?,
		message: String?,
		style: Style = .alert,
		isCancel: Bool = false,
		thankYou: Bool = false,
		action: (() -> Void)? = nil
	) {
		let ok = UIAlertAction(
			title: thankYou ? "Thank You!" : "OK",
			style: isCancel ? .cancel : .default,
			handler: { _ in if !isCancel { action?() } }
		)
		showAlert(presenter, popoverFromView, title: title, message: message, style: style, actions: [ok])
	}

	static public func showAlertWithRestart(
		_ presenter: NSViewController? = nil,
		_ popoverFromView: NSView? = nil,
		title: String?,
		message: String?,
		style: Style = .alert
	) {
		let actions = [
			UIAlertAction(title: "Restart", style: .default) { _ in UIApplication.shared.suspendAndReopen() },
			UIAlertAction(title: "Later", style: .cancel, handler: nil)
		]
		showAlert(presenter, popoverFromView, title: title, message: message, style: style, actions: actions)
	}

	static public func showAlert(
		_ presenter: NSViewController? = nil,
		_ popoverFromView: NSView? = nil,
		title: String?,
		message: String?,
		style: Style = .alert,
		actions: [UIAlertAction]
	) {
		let runBlock = {
			let alert = NSAlert()
			alert.messageText = title ?? ""
			alert.informativeText = message ?? ""
			alert.alertStyle = .informational
			// Put non-cancel actions first so default button is primary
			let ordered = actions.sorted { ($0.style == .cancel ? 1 : 0) < ($1.style == .cancel ? 1 : 0) }
			for act in ordered {
				let btn = alert.addButton(withTitle: act.title ?? "OK")
				if act.style == .destructive {
					btn.hasDestructiveAction = true
				}
			}
			let response = alert.runModal()
			let idx = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
			if idx >= 0 && idx < ordered.count {
				let chosen = ordered[idx]
				chosen.handler?(chosen)
			}
		}
		if Thread.isMainThread {
			runBlock()
		} else {
			DispatchQueue.main.async(execute: runBlock)
		}
	}

	static public func showAlertWithTextBox(
		_ presenter: NSViewController? = nil,
		_ popoverFromView: NSView? = nil,
		title: String?,
		message: String?,
		textFieldPlaceholder: String?,
		textFieldText: String = "",
		submit: String?,
		cancel: String?,
		style: Style = .alert,
		onSubmit: @escaping (String) -> Void
	) {
		let runBlock = {
			let alert = NSAlert()
			alert.messageText = title ?? ""
			alert.informativeText = message ?? ""
			let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
			input.placeholderString = textFieldPlaceholder
			input.stringValue = textFieldText
			alert.accessoryView = input
			alert.addButton(withTitle: submit ?? "OK")
			alert.addButton(withTitle: cancel ?? "Cancel")
			alert.window.initialFirstResponder = input
			let response = alert.runModal()
			if response == .alertFirstButtonReturn {
				onSubmit(input.stringValue)
			}
		}
		if Thread.isMainThread {
			runBlock()
		} else {
			DispatchQueue.main.async(execute: runBlock)
		}
	}
}
#endif
