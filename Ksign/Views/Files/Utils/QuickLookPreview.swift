//
//  QuickLookPreview.swift
//  Ksign
//

import SwiftUI
#if os(iOS)
import QuickLook
import UIKit

struct QuickLookPreview: UIViewControllerRepresentable {
	let fileURL: URL

	final class Coordinator: NSObject, QLPreviewControllerDataSource {
		private let _fileURL: URL
		init(fileURL: URL) { self._fileURL = fileURL }
		func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
		func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
			_fileURL as QLPreviewItem
		}
	}

	func makeCoordinator() -> Coordinator { Coordinator(fileURL: fileURL) }

	func makeUIViewController(context: Context) -> UINavigationController {
		let ql = QLPreviewController()
		ql.dataSource = context.coordinator
		return UINavigationController(rootViewController: ql)
	}

	func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
		if let ql = uiViewController.viewControllers.first as? QLPreviewController {
			ql.reloadData()
		}
	}
}
#elseif os(macOS)
import QuickLookUI

struct QuickLookPreview: NSViewRepresentable {
	let fileURL: URL

	func makeNSView(context: Context) -> QLPreviewView {
		let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
		view.previewItem = fileURL as NSURL
		return view
	}

	func updateNSView(_ nsView: QLPreviewView, context: Context) {
		nsView.previewItem = fileURL as NSURL
	}
}
#endif
