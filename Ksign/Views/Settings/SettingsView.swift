//
//  SettingsView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SettingsView: View {
    @AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
    @AppStorage("arcsign.autoCleanAfterInstall") private var _autoCleanAfterInstall: Bool = true
    @State private var _cacheSizeText: String = "Calculating…"
    @FetchRequest(
        entity: CertificatePair.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
        animation: .snappy
    ) private var _certificates: FetchedResults<CertificatePair>
    
    private var selectedCertificate: CertificatePair? {
        guard
            _storedSelectedCert >= 0,
            _storedSelectedCert < _certificates.count
        else {
            return nil
        }
        return _certificates[_storedSelectedCert]
    }
    
    
	private let _donationsUrl = "https://github.com/sponsors/nyasami"
	private let _githubUrl = "https://github.com/r0bledas/ArcSign"
    private let _discordUrl = "https://discord.gg/sfbZfQzVdQ"
	// MARK: Body
    var body: some View {
		NBNavigationView(.localized("Settings")) {
			Form {
//				#if !NIGHTLY && !DEBUG
				SettingsDonationCellView(site: _donationsUrl)
//				#endif
				
				_feedback()
				
				Section {
                    #if os(iOS)
                    NavigationLink(destination: AppIconView()) {
                        Label(.localized("App Icon"), systemImage: "app.badge")
                    }
                    #endif
					NavigationLink(destination: AppearanceView()) {
                        Label(.localized("Appearance"), systemImage: "paintbrush")
                    }
				}
                
                NBSection(.localized("Certificates")) {
                    
                    if let cert = selectedCertificate {
                        CertificatesCellView(cert: cert)
                    } else {
                        Text(.localized("No Certificate"))
                            .font(.footnote)
                            .foregroundColor(.disabled())
                    }
                    NavigationLink(destination: CertificatesView()) {
                        Label(.localized("Certificates"), systemImage: "signature")
                    }
                 
                } footer: {
                    Text(.localized("Add and manage certificates used for signing applications."))
                }
				
				NBSection(.localized("Features")) {
                    NavigationLink(destination: LogsView(manager: LogsManager.shared)) {
                        Label(.localized("Logs"), systemImage: "apple.terminal")
                    }
					NavigationLink(destination: AppFeaturesView()) {
                        Label(.localized("App Features"), systemImage: "sparkles")
                    }
					NavigationLink(destination: ConfigurationView()) {
                        Label(.localized("Signing Options"), systemImage: "gear")
                    }
					NavigationLink(destination: ArchiveView()) {
                        Label(.localized("Archive & Extraction"), systemImage: "archivebox")
                    }
					NavigationLink(destination: InstallationView()) {
                        Label(.localized("Installation"), systemImage: "server.rack")
                    }
				}
				
				_directories()
                
                Section {
                    NavigationLink(destination: ResetView()) {
                        Label(.localized("Reset"), systemImage: "trash")
                    }
                } footer: {
                    Text("Reset the applications sources, certificates, apps, and general contents.")
                }

            }
            #if os(macOS)
            .formStyle(.grouped)
            .onAppear {
                _cacheSizeText = MacStorageManager.formattedCacheSize()
            }
            #endif
        }
    }
}

// MARK: - View extension
extension SettingsView {
	@ViewBuilder
	private func _feedback() -> some View {
		Section {
			NavigationLink(destination: AboutNyaView()) {
                Label(.localized("About"), systemImage: "info.circle")
            }
			Button(.localized("Telegram Channel"), systemImage: "paperplane.circle") {
				UIApplication.open("https://t.me/KhoinDNS")
			}
			Button(.localized("GitHub Repository"), systemImage: "safari") {
				UIApplication.open(_githubUrl)
			}
            Button(.localized("Discord Server"), systemImage: "safari") {
                UIApplication.open(_discordUrl)
            }
		}
	}
	
	@ViewBuilder
	private func _directories() -> some View {
		#if os(macOS)
		NBSection("Storage & Workspace Cache") {
			HStack {
				Label("Cached IPAs & Staging Files", systemImage: "internaldrive")
				Spacer()
				Text(_cacheSizeText)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			Toggle("Auto-Clean Cache After Mac Install", isOn: $_autoCleanAfterInstall)
			Button("Clean Cache Now", systemImage: "trash.slash") {
				MacStorageManager.cleanImportAndBuildCaches()
				_cacheSizeText = MacStorageManager.formattedCacheSize()
			}
			Button(.localized("Open Workspace Folder"), systemImage: "folder") {
				UIApplication.open(FileManager.default.appWorkspaceDirectory.toSharedDocumentsURL()!)
			}
		} footer: {
			Text("Certificates and Repo Sources are kept safe when cleaning the IPA cache (~/Library/Application Support/ArcSign).")
		}
		#else
		NBSection(.localized("Misc")) {
			Button(.localized("Open Workspace Folder"), systemImage: "folder") {
				UIApplication.open(FileManager.default.appWorkspaceDirectory.toSharedDocumentsURL()!)
			}
			Button(.localized("Open Archives"), systemImage: "folder") {
				UIApplication.open(FileManager.default.archives.toSharedDocumentsURL()!)
			}
		} footer: {
			Text(.localized("All of ArcSign files except certificates are contained in the documents directory, here are some quick links to these."))
		}
		#endif
	}
}
