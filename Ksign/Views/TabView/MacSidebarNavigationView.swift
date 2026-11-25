//
//  MacSidebarNavigationView.swift
//  ArcSign
//
//  Native macOS NavigationSplitView sidebar for ArcSign, supporting drag-and-drop .ipa/.p12/.mobileprovision import.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import NimbleViews
import NimbleExtensions

struct MacSidebarNavigationView: View {
	@State private var selectedTab: TabEnum = .library
	@State private var isDropTargeted = false

	private let sidebarItems: [TabEnum] = [
		.library,
		.appstore,
		.sources,
		.files,
		.certificates,
		.downloader,
		.settings
	]

	var body: some View {
		NavigationSplitView {
			List(sidebarItems, id: \.self, selection: $selectedTab) { item in
				Label(sidebarTitle(for: item), systemImage: item.icon)
					.tag(item)
			}
			.navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 280)
			.safeAreaInset(edge: .bottom) {
				VStack(alignment: .leading, spacing: 4) {
					Divider()
					HStack(spacing: 6) {
						Image(systemName: "cpu")
							.foregroundStyle(.secondary)
						Text("Apple Silicon • 5 Engines Ready")
							.font(.caption2)
							.foregroundStyle(.secondary)
					}
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
				}
			}
		} detail: {
			TabEnum.view(for: selectedTab)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.overlay {
			if isDropTargeted {
				RoundedRectangle(cornerRadius: 14)
					.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
					.background(Color.accentColor.opacity(0.08))
					.overlay {
						Label("Drop .ipa, .tipa, .dylib, or .deb to Import", systemImage: "tray.and.arrow.down.fill")
							.font(.title2.bold())
							.padding(20)
							.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
					}
					.padding(10)
			}
		}
		.onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
			handleDroppedFiles(providers)
		}
	}

	private func sidebarTitle(for item: TabEnum) -> String {
		switch item {
		case .library: return "Library & Install"
		case .appstore: return "Browse Repo Apps"
		case .sources: return "Repo Sources"
		case .files: return "Payload & Plist Editor"
		case .certificates: return "Certificates & Xcode"
		case .downloader: return "IPA Downloader"
		case .settings: return "Settings & Logs"
		}
	}

	private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
		var handled = false
		for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
			handled = true
			provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
				guard let data = item as? Data,
					  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
				let ext = url.pathExtension.lowercased()
				if ext == "ipa" || ext == "tipa" {
					DispatchQueue.main.async {
						selectedTab = .library
						let id = "FeatherManualDownload_\(UUID().uuidString)"
						let dl = DownloadManager.shared.startArchive(from: url, id: id)
						DownloadManager.shared.handlePachageFile(url: url, dl: dl) { _ in }
					}
				}
			}
		}
		return handled
	}
}
#endif
