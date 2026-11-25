//
//  SafariWebView.swift
//  NimbleKit
//

import SwiftUI
#if os(iOS)
import SafariServices

public struct SafariRepresentableView: UIViewControllerRepresentable {
	public let url: URL
	
	public init(url: URL) {
		self.url = url
	}
	
	public func makeUIViewController(context: Context) -> SFSafariViewController { return SFSafariViewController(url: url) }
	public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#elseif os(macOS)
import WebKit

public struct SafariRepresentableView: NSViewRepresentable {
	public let url: URL

	public init(url: URL) {
		self.url = url
	}

	public func makeNSView(context: Context) -> WKWebView {
		let webView = WKWebView()
		webView.load(URLRequest(url: url))
		return webView
	}

	public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
