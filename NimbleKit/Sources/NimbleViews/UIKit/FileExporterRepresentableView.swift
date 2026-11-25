//
//  FileExporterRepresentableView.swift
//  NimbleViews
//

import SwiftUI
#if canImport(UIKit)
import UIKit

public struct FileExporterRepresentableView: UIViewControllerRepresentable {
	public var urlsToExport: [URL]
	public var asCopy: Bool
	public var useLastLocation: Bool
	public var onCompletion: (Bool) -> Void

	public init(
		urlsToExport: [URL],
		asCopy: Bool = false,
		useLastLocation: Bool = false,
		onCompletion: @escaping (Bool) -> Void
	) {
		self.urlsToExport = urlsToExport
		self.asCopy = asCopy
		self.useLastLocation = useLastLocation
		self.onCompletion = onCompletion
	}

	public func makeCoordinator() -> Coordinator {
		Coordinator(onCompletion: onCompletion)
	}

	public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
		let picker = UIDocumentPickerViewController(forExporting: urlsToExport, asCopy: asCopy)
		picker.delegate = context.coordinator
		picker.directoryURL = !useLastLocation ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first : nil
		return picker
	}

	public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

	public class Coordinator: NSObject, UIDocumentPickerDelegate {
		var onCompletion: (Bool) -> Void
		init(onCompletion: @escaping (Bool) -> Void) { self.onCompletion = onCompletion }
		public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
			onCompletion(true)
		}
		public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
			onCompletion(false)
		}
	}
}
#elseif os(macOS)
import AppKit

public struct FileExporterRepresentableView: View {
	@Environment(\.dismiss) private var dismiss
	public var urlsToExport: [URL]
	public var asCopy: Bool
	public var useLastLocation: Bool
	public var onCompletion: (Bool) -> Void
	@State private var didPresent = false

	public init(
		urlsToExport: [URL],
		asCopy: Bool = false,
		useLastLocation: Bool = false,
		onCompletion: @escaping (Bool) -> Void
	) {
		self.urlsToExport = urlsToExport
		self.asCopy = asCopy
		self.useLastLocation = useLastLocation
		self.onCompletion = onCompletion
	}

	public var body: some View {
		Color.clear
			.frame(width: 1, height: 1)
			.onAppear {
				guard !didPresent else { return }
				didPresent = true
				DispatchQueue.main.async {
					var success = false
					if urlsToExport.count == 1, let src = urlsToExport.first {
						let panel = NSSavePanel()
						panel.canCreateDirectories = true
						panel.nameFieldStringValue = src.lastPathComponent
						if panel.runModal() == .OK, let dest = panel.url {
							try? FileManager.default.removeItem(at: dest)
							do {
								if asCopy {
									try FileManager.default.copyItem(at: src, to: dest)
								} else {
									try FileManager.default.copyItem(at: src, to: dest)
								}
								success = true
								NSWorkspace.shared.activateFileViewerSelecting([dest])
							} catch {
								success = false
							}
						}
					} else if !urlsToExport.isEmpty {
						let panel = NSOpenPanel()
						panel.canChooseDirectories = true
						panel.canChooseFiles = false
						panel.canCreateDirectories = true
						panel.prompt = "Export Here"
						if panel.runModal() == .OK, let folder = panel.url {
							success = true
							for src in urlsToExport {
								let dest = folder.appendingPathComponent(src.lastPathComponent)
								try? FileManager.default.removeItem(at: dest)
								try? FileManager.default.copyItem(at: src, to: dest)
							}
							NSWorkspace.shared.activateFileViewerSelecting([folder])
						}
					}
					dismiss()
					onCompletion(success)
				}
			}
	}
}
#endif
