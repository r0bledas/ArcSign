//
//  LibraryView.swift
//  ArcSign
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import NimbleViews
import NimbleExtensions

struct LibraryView: View {
	@StateObject var downloadManager = DownloadManager.shared
	
	@State private var _selectedInfoAppPresenting: AnyApp?
	@State private var _selectedSigningAppPresenting: AnyApp?
	@State private var _selectedInstallAppPresenting: AnyApp?
	@State private var _selectedAppDylibsPresenting: AnyApp?
	@State private var _isBulkSigningPresenting = false
	@State private var _isBulkInstallingPresenting = false
	@State private var _isImportingPresenting = false
	@State private var _isDownloadingPresenting = false

	@State private var _searchText = ""
	@State private var _selectedTab: Int = 0 // 0 = Downloaded/Imported, 1 = Signed
	@State private var _isEditMode: EditMode = .inactive
	@State private var _selectedApps: Set<String> = []
	
	@Namespace private var _namespace
	
	private func filteredAndSortedApps<T>(from apps: FetchedResults<T>) -> [T] where T: NSManagedObject {
		apps.filter {
			_searchText.isEmpty ||
			(($0.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(_searchText) ?? false)
		}
	}
	
	private var _filteredSignedApps: [Signed] {
		filteredAndSortedApps(from: _signedApps)
	}
	
	private var _filteredImportedApps: [Imported] {
		filteredAndSortedApps(from: _importedApps)
	}
	
	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>
	
	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>
	
	var body: some View {
		NBNavigationView(.localized("Library")) {
			VStack(spacing: 0) {
				Picker("", selection: $_selectedTab) {
					Text(.localized("Downloaded / Imported IPAs")).tag(0)
					Text(.localized("Signed Apps")).tag(1)
				}
				.pickerStyle(SegmentedPickerStyle())
				.padding(.horizontal)
				.padding(.vertical, 8)
				
				NBListAdaptable {
					if _selectedTab == 0 {
						NBSection(
							.localized("Downloaded Apps"),
							secondary: _filteredImportedApps.count.description
						) {
							ForEach(_filteredImportedApps, id: \.uuid) { app in
								LibraryCellView(
									app: app,
									selectedInfoAppPresenting: $_selectedInfoAppPresenting,
									selectedSigningAppPresenting: $_selectedSigningAppPresenting,
									selectedInstallAppPresenting: $_selectedInstallAppPresenting,
									selectedAppDylibsPresenting: $_selectedAppDylibsPresenting,
									selectedApps: $_selectedApps
								)
								.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
							}
						}
					} else {
						NBSection(
							.localized("Signed Apps"),
							secondary: _filteredSignedApps.count.description
						) {
							ForEach(_filteredSignedApps, id: \.uuid) { app in
								LibraryCellView(
									app: app,
									selectedInfoAppPresenting: $_selectedInfoAppPresenting,
									selectedSigningAppPresenting: $_selectedSigningAppPresenting,
									selectedInstallAppPresenting: $_selectedInstallAppPresenting,
									selectedAppDylibsPresenting: $_selectedAppDylibsPresenting,
									selectedApps: $_selectedApps
								)
								.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
							}
						}
					}
				}
			}
			.searchable(text: $_searchText, placement: .platform())
			.overlay {
				if (_selectedTab == 0 && _filteredImportedApps.isEmpty) || (_selectedTab == 1 && _filteredSignedApps.isEmpty) {
					ContentUnavailableView {
						Label(
							_selectedTab == 0 ? .localized("No Imported IPAs") : .localized("No Signed Apps"),
							systemImage: "square.stack.3d.up.fill"
						)
					} description: {
						Text(_selectedTab == 0
							? "Drag & drop any .ipa file anywhere onto this window, import from disk, or browse ESign/AltStore repos in the sidebar."
							: "Sign an imported .ipa to see it here, or use Method 1 (Certless Mac Install) directly from Imported IPAs.")
					} actions: {
						if _selectedTab == 0 {
							Button("Import .ipa File…") {
								_isImportingPresenting = true
							}
							.buttonStyle(.borderedProminent)
						}
					}
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					EditButton()
				}
				if _isEditMode.isEditing {
					ToolbarItemGroup(placement: .topBarTrailing) {
						Button {
							if _selectedTab == 0 {
								_isBulkSigningPresenting = true
							} else {
								_isBulkInstallingPresenting = true
							}
						} label: {
							NBButton(_selectedTab == 0 ? .localized("Bulk Sign") : .localized("Bulk Install"), systemImage: "signature", style: .icon)
						}
						.disabled(_selectedApps.isEmpty)

						#if os(macOS)
						Button("Bulk Certless Mac Install") {
							_bulkInstallCertlessOnMac()
						}
						.disabled(_selectedApps.isEmpty)
						#endif

						Button {
							_bulkDeleteSelectedApps()
						} label: {
							NBButton(.localized("Delete"), systemImage: "trash", style: .icon)
						}
						.disabled(_selectedApps.isEmpty)
					}
				} else {
					NBToolbarMenu(
						systemImage: "plus",
						style: .icon,
						placement: .topBarTrailing
					) {
						_importActions()
					}
				}
			}
			.environment(\.editMode, $_isEditMode)
			.sheet(item: $_selectedInfoAppPresenting) { app in
				LibraryInfoView(app: app.base)
					.frame(minWidth: 480, minHeight: 480)
			}
			.sheet(item: $_selectedInstallAppPresenting) { app in
				#if os(macOS)
				if app.archive {
					InstallPreviewView(app: app.base, isSharing: true)
						.frame(minWidth: 420, minHeight: 240)
				} else {
					MacInstallSheetView(app: app.base)
				}
				#else
				InstallPreviewView(app: app.base, isSharing: app.archive)
					.presentationDetents([.height(200)])
				#endif
			}
			.fullScreenCover(item: $_selectedSigningAppPresenting) { app in
				#if os(macOS)
				if app.signAndInstall {
					MacInstallSheetView(app: app.base)
				} else {
					SigningView(app: app.base, signAndInstall: false)
						.frame(minWidth: 560, minHeight: 560)
				}
				#else
				SigningView(app: app.base, signAndInstall: app.signAndInstall)
				#endif
			}
			.fullScreenCover(item: $_selectedAppDylibsPresenting) { app in
				DylibsView(app: app.base)
					.frame(minWidth: 500, minHeight: 450)
			}
			.fullScreenCover(isPresented: $_isBulkSigningPresenting) {
				BulkSigningView(apps: _selectedApps.compactMap { id in
					(_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
					?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
				})
				.frame(minWidth: 580, minHeight: 540)
				.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ksign.bulkSigningFinished"))) { _ in
					_selectedTab = 1
				}
			}
			.sheet(isPresented: $_isBulkInstallingPresenting) {
				BulkInstallPreviewView(apps: _selectedApps.compactMap { id in
					(_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
					?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
				})
				.frame(minWidth: 480, minHeight: 320)
			}
			.sheet(isPresented: $_isImportingPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.ipa, .tipa],
					allowsMultipleSelection: true,
					onDocumentsPicked: { urls in
						guard !urls.isEmpty else { return }
						for ipas in urls {
							let id = "FeatherManualDownload_\(UUID().uuidString)"
							let dl = downloadManager.startArchive(from: ipas, id: id)
							downloadManager.handlePachageFile(url: ipas, dl: dl) { err in
								if err != nil {
									UIAlertController.showAlertWithOk(
										title: "Error",
										message: .localized("Whoops!, something went wrong when extracting the file.\nMaybe try switching the extraction library in Settings?")
									)
								}
							}
						}
					}
				)
			}
			.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("feather.installApp"))) { _ in
				if let latest = _signedApps.first {
					_selectedInstallAppPresenting = AnyApp(base: latest)
				}
			}
		}
	}

	@ViewBuilder
	private func _importActions() -> some View {
		Button(.localized("Import from Files…"), systemImage: "folder") {
			_isImportingPresenting = true
		}
		Button(.localized("Import from URL…"), systemImage: "link") {
			UIAlertController.showAlertWithTextBox(
				title: .localized("Import IPA URL"),
				message: .localized("Enter a direct https:// link to an .ipa file"),
				textFieldPlaceholder: "https://example.com/app.ipa",
				submit: .localized("Download"),
				cancel: .localized("Cancel")
			) { text in
				if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
					_ = downloadManager.startDownload(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
				}
			}
		}
	}

	private func _bulkDeleteSelectedApps() {
		let targets: [AppInfoPresentable] = _selectedApps.compactMap { id in
			(_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
			?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
		}
		for app in targets {
			Storage.shared.deleteApp(for: app)
		}
		_selectedApps.removeAll()
		_isEditMode = .inactive
	}

	#if os(macOS)
	private func _bulkInstallCertlessOnMac() {
		let targets: [AppInfoPresentable] = _selectedApps.compactMap { id in
			(_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
			?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
		}
		guard !targets.isEmpty else { return }
		Task {
			var installedCount = 0
			var lastURL: URL?
			for item in targets {
				if let dir = Storage.shared.getAppDirectory(for: item),
				   let out = try? await MacBundleInstaller.installCertlessCatalystApp(sourceAppBundleURL: dir) {
					installedCount += 1
					lastURL = out
				}
			}
			await MainActor.run {
				_selectedApps.removeAll()
				_isEditMode = .inactive
				UIAlertController.showAlertWithOk(
					title: "Bulk Mac Install Complete",
					message: "Installed \(installedCount) of \(targets.count) app(s) using Certless MacCatalyst Mode."
				) {
					if let lastURL {
						MacBundleInstaller.revealInFinder(at: lastURL)
					}
				}
			}
		}
	}
	#endif
}
