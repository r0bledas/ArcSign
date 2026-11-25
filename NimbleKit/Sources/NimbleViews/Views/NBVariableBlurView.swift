//
//  NBVariableBlurView.swift
//  NimbleViews
//

import SwiftUI
#if canImport(UIKit)
import UIKit

public struct NBVariableBlurView: UIViewRepresentable {
	public init() {}
	public func makeUIView(context: Context) -> UIVisualEffectView {
		UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
	}
	public func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
#elseif os(macOS)
import AppKit

public struct NBVariableBlurView: NSViewRepresentable {
	public init() {}
	public func makeNSView(context: Context) -> NSVisualEffectView {
		let view = NSVisualEffectView()
		view.material = .headerView
		view.blendingMode = .withinWindow
		view.state = .active
		return view
	}
	public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif
