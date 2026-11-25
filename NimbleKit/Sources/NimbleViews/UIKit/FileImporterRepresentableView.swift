//
//  UIKitFileImporter.swift
//  Feather
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit

public struct FileImporterRepresentableView: UIViewControllerRepresentable {
	public var allowedContentTypes: [UTType]
	public var allowsMultipleSelection: Bool = false
	public var onDocumentsPicked: ([URL]) -> Void
	
	public init(
		allowedContentTypes: [UTType],
		allowsMultipleSelection: Bool = false,
		onDocumentsPicked: @escaping ([URL]) -> Void
	) {
		self.allowedContentTypes = allowedContentTypes
		self.allowsMultipleSelection = allowsMultipleSelection
		self.onDocumentsPicked = onDocumentsPicked
	}
	
	public func makeCoordinator() -> Coordinator {
		Coordinator(onDocumentsPicked: onDocumentsPicked)
	}
	
	public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
		let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
		picker.delegate = context.coordinator
		picker.allowsMultipleSelection = allowsMultipleSelection
		return picker
	}
	
	public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
	
	public class Coordinator: NSObject, UIDocumentPickerDelegate {
		var onDocumentsPicked: ([URL]) -> Void
		init(onDocumentsPicked: @escaping ([URL]) -> Void) {
			self.onDocumentsPicked = onDocumentsPicked
		}
		public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
			onDocumentsPicked(urls)
		}
		public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
			onDocumentsPicked([])
		}
	}
}
#elseif os(macOS)
import AppKit

public struct FileImporterRepresentableView: View {
	@Environment(\.dismiss) private var dismiss
	public var allowedContentTypes: [UTType]
	public var allowsMultipleSelection: Bool = false
	public var onDocumentsPicked: ([URL]) -> Void
	@State private var didPresent = false

	public init(
		allowedContentTypes: [UTType],
		allowsMultipleSelection: Bool = false,
		onDocumentsPicked: @escaping ([URL]) -> Void
	) {
		self.allowedContentTypes = allowedContentTypes
		self.allowsMultipleSelection = allowsMultipleSelection
		self.onDocumentsPicked = onDocumentsPicked
	}

	public var body: some View {
		Color.clear
			.frame(width: 1, height: 1)
			.onAppear {
				guard !didPresent else { return }
				didPresent = true
				DispatchQueue.main.async {
					let panel = NSOpenPanel()
					panel.canChooseFiles = true
					panel.canChooseDirectories = false
					panel.allowsMultipleSelection = allowsMultipleSelection
					if !allowedContentTypes.isEmpty && !allowedContentTypes.contains(.item) {
						panel.allowedContentTypes = allowedContentTypes
					}
					let resp = panel.runModal()
					let picked = (resp == .OK) ? panel.urls : []
					dismiss()
					onDocumentsPicked(picked)
				}
			}
	}
}
#endif
