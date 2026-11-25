//
//  UlActivityViewController+Present.swift
//  NimbleKit
//

import Foundation
#if canImport(UIKit)
import UIKit.UIActivityViewController

extension UIActivityViewController {
	static public func show(
		_ presenter: UIViewController = UIApplication.topViewController()!,
		activityItems: [Any],
		applicationActivities: [UIActivity]? = nil
	) {
		let controller = Self(
			activityItems: activityItems,
			applicationActivities: applicationActivities
		)
		if let popover = controller.popoverPresentationController {
			popover.sourceView = presenter.view
			popover.sourceRect = CGRect(
				x: presenter.view.bounds.midX,
				y: presenter.view.bounds.midY,
				width: 0,
				height: 0
			)
			popover.permittedArrowDirections = []
		}
		presenter.present(controller, animated: true)
	}
}
#elseif os(macOS)
import AppKit

public class UIActivity {}

public final class UIActivityViewController {
	static public func show(
		_ presenter: NSViewController? = nil,
		activityItems: [Any],
		applicationActivities: [UIActivity]? = nil
	) {
		let urls = activityItems.compactMap { $0 as? URL }
		if !urls.isEmpty {
			DispatchQueue.main.async {
				let savePanel = NSSavePanel()
				if urls.count == 1, let src = urls.first {
					savePanel.nameFieldStringValue = src.lastPathComponent
					savePanel.canCreateDirectories = true
					if savePanel.runModal() == .OK, let dest = savePanel.url {
						try? FileManager.default.removeItem(at: dest)
						try? FileManager.default.copyItem(at: src, to: dest)
						NSWorkspace.shared.activateFileViewerSelecting([dest])
					}
				} else {
					NSWorkspace.shared.activateFileViewerSelecting(urls)
				}
			}
		} else if let str = activityItems.compactMap({ $0 as? String }).first {
			UIPasteboard.general.string = str
		}
	}
}
#endif
