//
//  SourceAppsTableRepresentableView.swift
//  ArcSign
//

import SwiftUI
import AltSourceKit
import NimbleExtensions

#if os(macOS)
struct SourceAppsTableRepresentableView: View {
	var sources: [ASRepository]
	@Binding var searchText: String
	@Binding var sortOption: SourceAppsView.SortOption
	@Binding var sortAscending: Bool
	var onSelect: (SourceAppsView.SourceAppRoute) -> Void

	private var filteredAndSorted: [(source: ASRepository, app: ASRepository.App)] {
		let all = sources.flatMap { src in src.apps.map { (source: src, app: $0) } }
		let filtered = searchText.isEmpty ? all : all.filter { entry in
			(entry.app.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
			(entry.app.description?.localizedCaseInsensitiveContains(searchText) ?? false) ||
			(entry.app.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false) ||
			(entry.app.localizedDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
		}

		switch sortOption {
		case .default:
			return sortAscending ? filtered : filtered.reversed()
		case .name:
			return filtered.sorted { lhs, rhs in
				let a = lhs.app.name ?? ""
				let b = rhs.app.name ?? ""
				return sortAscending
					? (a.localizedCaseInsensitiveCompare(b) == .orderedAscending)
					: (a.localizedCaseInsensitiveCompare(b) == .orderedDescending)
			}
		case .date:
			return filtered.sorted { lhs, rhs in
				let d1 = lhs.app.currentDate?.date ?? .distantPast
				let d2 = rhs.app.currentDate?.date ?? .distantPast
				return sortAscending ? (d1 > d2) : (d1 < d2)
			}
		}
	}

	var body: some View {
		List {
			if sources.count == 1, let news = sources.first?.news, !news.isEmpty {
				SourceNewsView(news: news)
					.frame(height: 165)
					.listRowInsets(EdgeInsets())
					.listRowSeparator(.hidden)
			}

			ForEach(Array(filteredAndSorted.enumerated()), id: \.offset) { _, entry in
				SourceAppsCellView(source: entry.source, app: entry.app)
					.contentShape(Rectangle())
					.onTapGesture {
						onSelect(SourceAppsView.SourceAppRoute(source: entry.source, app: entry.app))
					}
					.contextMenu {
						Button("View Versions & Details") {
							onSelect(SourceAppsView.SourceAppRoute(source: entry.source, app: entry.app))
						}
						if let id = entry.app.id {
							Button("Copy Bundle Identifier") {
								UIPasteboard.general.string = id
							}
						}
						if let dlURL = entry.app.currentDownloadUrl {
							Button("Download IPA to Library") {
								_ = DownloadManager.shared.startDownload(from: dlURL, id: entry.app.currentUniqueId)
							}
						}
					}
			}
		}
		.listStyle(.inset)
	}
}
#else
import UIKit

struct SourceAppsTableRepresentableView: UIViewRepresentable {
	var sources: [ASRepository]
	@Binding var searchText: String
	@Binding var sortOption: SourceAppsView.SortOption
	@Binding var sortAscending: Bool
	var onSelect: (SourceAppsView.SourceAppRoute) -> Void

	func makeUIView(context: Context) -> UITableView {
		let tableView = UITableView(frame: .zero, style: .plain)
		tableView.allowsSelection = true
		return tableView
	}

	func updateUIView(_ tableView: UITableView, context: Context) {}
}
#endif
