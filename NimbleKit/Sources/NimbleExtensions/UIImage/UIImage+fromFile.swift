//
//  UIImage+url.swift
//  Feather
//

import Foundation
#if canImport(UIKit)
import UIKit.UIImage

extension UIImage {
	static public func fromFile(_ url: URL?) -> UIImage? {
		guard let url = url else {
			return nil
		}
		return UIImage(contentsOfFile: url.path)
	}
}
#elseif os(macOS)
import AppKit

extension NSImage {
	static public func fromFile(_ url: URL?) -> NSImage? {
		guard let url = url else {
			return nil
		}
		return NSImage(contentsOfFile: url.path)
	}
}
#endif
