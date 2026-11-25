//
//  UIApplication+open.swift
//  NimbleKit
//

import Foundation
#if canImport(UIKit)
import UIKit.UIApplication
#elseif os(macOS)
import AppKit
#endif

extension UIApplication {
	static public func open(_ url: URL) {
		Self.shared.open(url, options: [:])
	}
	
	static public func open(_ urlString: String) {
		guard let url = URL(string: urlString) else { return }
		Self.shared.open(url, options: [:])
	}
}
