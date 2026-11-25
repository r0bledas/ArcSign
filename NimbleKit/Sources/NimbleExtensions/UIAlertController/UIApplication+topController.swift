//
//  UIApplication+topController.swift
//  Loader
//

import Foundation
#if canImport(UIKit)
import UIKit.UIApplication

extension UIApplication {
	public class func topViewController(controller: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
		if let navigationController = controller as? UINavigationController {
			return topViewController(controller: navigationController.visibleViewController)
		}
		if let tabController = controller as? UITabBarController {
			if let selected = tabController.selectedViewController {
				return topViewController(controller: selected)
			}
		}
		if let presented = controller?.presentedViewController {
			return topViewController(controller: presented)
		}
		return controller
	}
}
#elseif os(macOS)
import AppKit

extension UIApplication {
	@MainActor
	public static func topViewController(controller: NSViewController? = nil) -> NSViewController? {
		controller ?? NSApplication.shared.keyWindow?.contentViewController ?? NSViewController()
	}
}
#endif
