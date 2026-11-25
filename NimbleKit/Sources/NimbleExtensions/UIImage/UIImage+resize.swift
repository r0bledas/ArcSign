//
//  UIImage+resize.swift
//  feather
//

import AVFoundation
#if canImport(UIKit)
import UIKit.UIImage

extension UIImage {
	public func resizeToSquare() -> UIImage? {
		let size = min(self.size.width, self.size.height)
		let rect = CGRect(
			x: (self.size.width - size) / 2,
			y: (self.size.height - size) / 2,
			width: size,
			height: size
		)
		
		UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, self.scale)
		self.draw(at: CGPoint(x: -rect.origin.x, y: -rect.origin.y))
		let squareImage = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		
		return squareImage
	}
	
	public func resize(_ width: Int, _ height: Int) -> UIImage {
		let maxSize = CGSize(width: width, height: height)
		
		let availableRect = AVFoundation.AVMakeRect(
			aspectRatio: self.size,
			insideRect: .init(origin: .zero, size: maxSize)
		)
		let targetSize = availableRect.size
		
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
		
		let resized = renderer.image { _ in
			self.draw(in: CGRect(origin: .zero, size: targetSize))
		}
		
		return resized
	}
}
#elseif os(macOS)
import AppKit

extension NSImage {
	public func resizeToSquare() -> NSImage? {
		let side = min(self.size.width, self.size.height)
		guard side > 0 else { return nil }
		let targetSize = NSSize(width: side, height: side)
		let result = NSImage(size: targetSize)
		result.lockFocus()
		let srcRect = NSRect(
			x: (self.size.width - side) / 2,
			y: (self.size.height - side) / 2,
			width: side,
			height: side
		)
		self.draw(in: NSRect(origin: .zero, size: targetSize), from: srcRect, operation: .copy, fraction: 1.0)
		result.unlockFocus()
		return result
	}

	public func resize(_ width: Int, _ height: Int) -> NSImage {
		let maxSize = CGSize(width: width, height: height)
		let availableRect = AVFoundation.AVMakeRect(
			aspectRatio: self.size,
			insideRect: .init(origin: .zero, size: maxSize)
		)
		let targetSize = NSSize(width: max(1, availableRect.size.width), height: max(1, availableRect.size.height))
		let result = NSImage(size: targetSize)
		result.lockFocus()
		NSGraphicsContext.current?.imageInterpolation = .high
		self.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
		result.unlockFocus()
		return result
	}
}
#endif
