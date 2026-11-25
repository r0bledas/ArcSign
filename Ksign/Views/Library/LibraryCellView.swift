//
//  LibraryCellView.swift
//  ArcSign
//

import SwiftUI
import NimbleExtensions
import NimbleViews

struct LibraryCellView: View {
	@AppStorage("Feather.libraryCellAppearance") private var _libraryCellAppearance: Int = 0
	@Environment(\.editMode) private var editMode

	var certInfo: Date.ExpirationInfo? {
		Storage.shared.getCertificate(from: app)?.expiration?.expirationInfo()
	}
	
	var app: AppInfoPresentable
	@Binding var selectedInfoAppPresenting: AnyApp?
	@Binding var selectedSigningAppPresenting: AnyApp?
	@Binding var selectedInstallAppPresenting: AnyApp?
	@Binding var selectedAppDylibsPresenting: AnyApp?
	@Binding var selectedApps: Set<String>
	@State private var _showActionSheet = false
	
	private var _isSelected: Bool {
		selectedApps.contains(app.uuid ?? "")
	}

	var body: some View {
		let isEditing = editMode?.wrappedValue == .active
		HStack(spacing: 12) {
			if isEditing {
				Button {
					_toggleSelection()
				} label: {
					Image(systemName: _isSelected ? "checkmark.circle.fill" : "circle")
						.foregroundColor(_isSelected ? .accentColor : .secondary)
						.font(.title2)
				}
				.buttonStyle(.borderless)
			}
			
			FRAppIconView(app: app, size: 54)
			
			NBTitleWithSubtitleView(
				title: app.name ?? .localized("Unknown"),
				subtitle: _desc,
				linelimit: 0
			)
			
			Spacer()
			
			if !isEditing {
				if app.isSigned, let certInfo = certInfo {
					HStack(spacing: 4) {
						Image(systemName: "clock")
							.font(.system(size: 11))
						Text(certInfo.formatted)
							.font(.system(size: 12))
							.fontWeight(.semibold)
					}
					.foregroundColor(.white)
					.padding(.horizontal, 10)
					.padding(.vertical, 5)
					.background(certInfo.color)
					.clipShape(Capsule())
				}

				#if os(macOS)
				Button {
					selectedInstallAppPresenting = AnyApp(base: app)
				} label: {
					Label("Install / Sign…", systemImage: "arrow.down.app.fill")
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
				#else
				Image(systemName: "chevron.right")
					.foregroundColor(.secondary)
					.font(.footnote)
				#endif
			}
		}
		.scaleEffect(_isSelected ? 0.98 : 1.0)
		.contentShape(Rectangle())
		.onTapGesture {
			if isEditing {
				_toggleSelection()
			} else {
				#if os(macOS)
				selectedInstallAppPresenting = AnyApp(base: app)
				#else
				_showActionSheet = true
				#endif
			}
		}
		.confirmationDialog(
			app.name ?? .localized("Unknown"),
			isPresented: $_showActionSheet,
			titleVisibility: .visible
		) {
			if !isEditing {
				_actionSheetButtons(for: app)
			}
		}
		.contextMenu {
			if !isEditing {
				Button("Install / Sign (All 5 Methods)…", systemImage: "arrow.down.app.fill") {
					selectedInstallAppPresenting = AnyApp(base: app)
				}
				Button("Customize Payload / Tweaks / Sign…", systemImage: "slider.horizontal.3") {
					selectedSigningAppPresenting = AnyApp(base: app, signAndInstall: false)
				}
				Button("Inspect Dylibs & Load Commands", systemImage: "cpu") {
					selectedAppDylibsPresenting = AnyApp(base: app)
				}
				Button(.localized("Get Info"), systemImage: "info.circle") {
					selectedInfoAppPresenting = AnyApp(base: app)
				}
				Button(.localized("Export .ipa"), systemImage: "square.and.arrow.up") {
					selectedInstallAppPresenting = AnyApp(base: app, archive: true)
				}
				if let id = app.identifier {
					Button(.localized("Open Installed App"), systemImage: "app.badge.checkmark") {
						UIApplication.openApp(with: id)
					}
				}
				Divider()
				Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
					Storage.shared.deleteApp(for: app)
				}
			}
		}
	}
	
	private var _desc: String {
		if let version = app.version, let id = app.identifier {
			return "\(version) • \(id)"
		} else {
			return .localized("Unknown")
		}
	}
	
	private func _toggleSelection() {
		guard let uuid = app.uuid else { return }
		withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)) {
			if _isSelected {
				selectedApps.remove(uuid)
			} else {
				selectedApps.insert(uuid)
			}
		}
	}

	@ViewBuilder
	private func _actionSheetButtons(for app: AppInfoPresentable) -> some View {
		Button(.localized("Install / Sign")) {
			selectedInstallAppPresenting = AnyApp(base: app)
		}
		Button(.localized("Customize & Sign")) {
			selectedSigningAppPresenting = AnyApp(base: app)
		}
		Button(.localized("Show Dylibs")) {
			selectedAppDylibsPresenting = AnyApp(base: app)
		}
		Button(.localized("Get Info")) {
			selectedInfoAppPresenting = AnyApp(base: app)
		}
		Button(.localized("Export")) {
			selectedInstallAppPresenting = AnyApp(base: app, archive: true)
		}
		Button(.localized("Delete"), role: .destructive) {
			Storage.shared.deleteApp(for: app)
		}
	}
}
