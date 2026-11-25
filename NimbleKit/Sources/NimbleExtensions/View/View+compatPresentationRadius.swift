//
//  View+compatPresentationRadius.swift
//  Feather
//

import SwiftUI

extension View {
	@ViewBuilder
	public func compatPresentationRadius(_ cornerRadius: CGFloat?) -> some View {
		if #available(iOS 16.4, macOS 13.3, *) {
			self.presentationCornerRadius(cornerRadius)
		} else {
			self
		}
	}
}
