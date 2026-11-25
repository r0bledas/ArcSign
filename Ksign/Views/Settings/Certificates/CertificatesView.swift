//
//  CertificatesView.swift
//  ArcSign
//

import SwiftUI
import NimbleViews
import NimbleExtensions

struct CertificatesView: View {
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
	
	@State private var _isAddingPresenting = false
	@State private var _isSelectedInfoPresenting: CertificatePair?
	#if os(macOS)
	@State private var _xcodeIdentities: [LocalXcodeSigningIdentity] = []
	@State private var _ocspStatuses: [String: MacOCSPCheckResult] = [:]
	@State private var _isCheckingOCSP = false
	#endif

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var certificates: FetchedResults<CertificatePair>
	
	private var _bindingSelectedCert: Binding<Int>?
	private var _selectedCertBinding: Binding<Int> {
		_bindingSelectedCert ?? $_storedSelectedCert
	}
	
	init(selectedCert: Binding<Int>? = nil) {
		self._bindingSelectedCert = selectedCert
	}
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				#if os(macOS)
				macHardwareAndXcodeBanner
				#endif

				if certificates.isEmpty {
					GroupBox {
						VStack(spacing: 10) {
							Image(systemName: "person.text.rectangle")
								.font(.largeTitle)
								.foregroundStyle(.secondary)
							Text(.localized("No Imported .p12 Certificates"))
								.font(.headline)
							Text("Note: On Apple Silicon Mac, Method 1 (Certless MacCatalyst) works with ZERO certificates! Import a .p12 + .mobileprovision here only if you want WrappedBundle signing or iOS IPA exporting.")
								.font(.caption)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
								.frame(maxWidth: 460)
							Button("Import .p12 & .mobileprovision…") {
								_isAddingPresenting = true
							}
							.buttonStyle(.borderedProminent)
						}
						.frame(maxWidth: .infinity)
						.padding(20)
					}
				} else {
					VStack(alignment: .leading, spacing: 12) {
						Text("Imported Certificates (.p12 + .mobileprovision)")
							.font(.headline)
						ForEach(Array(certificates.enumerated()), id: \.element.uuid) { index, cert in
							_cellButton(for: cert, at: index)
						}
					}
				}
			}
			.padding(20)
		}
		.navigationTitle(.localized("Certificates"))
		.toolbar {
			if _bindingSelectedCert == nil {
				NBToolbarButton(
					systemImage: "plus",
					style: .icon,
					placement: .topBarTrailing
				) {
					_isAddingPresenting = true
				}
			}
			NBToolbarButton(
				systemImage: "arrow.counterclockwise",
				style: .icon,
				placement: .topBarTrailing
			) {
				refreshAllCertificates()
			}
		}
		.sheet(item: $_isSelectedInfoPresenting) { cert in
			CertificatesInfoView(cert: cert)
				.frame(minWidth: 500, minHeight: 520)
		}
		.sheet(isPresented: $_isAddingPresenting) {
			CertificatesAddView()
				.frame(minWidth: 460, minHeight: 380)
		}
		.onAppear {
			#if os(macOS)
			_xcodeIdentities = MacCertificateTrustService.discoverLocalXcodeIdentities()
			runLiveOCSPChecks()
			#endif
		}
	}

	private func refreshAllCertificates() {
		for cert in certificates {
			Storage.shared.revokagedCertificate(for: cert)
		}
		#if os(macOS)
		_xcodeIdentities = MacCertificateTrustService.discoverLocalXcodeIdentities()
		runLiveOCSPChecks()
		#endif
	}

	#if os(macOS)
	private func runLiveOCSPChecks() {
		guard !_isCheckingOCSP else { return }
		_isCheckingOCSP = true
		let pairs = Array(certificates)
		Task {
			for cert in pairs {
				guard let uuid = cert.uuid,
					  let p12URL = Storage.shared.getFile(.certificate, from: cert) else { continue }
				let res = await MacCertificateTrustService.verifyCertificateOCSPLive(
					p12URL: p12URL,
					password: cert.password ?? ""
				)
				await MainActor.run {
					_ocspStatuses[uuid] = res
					if res.status == .revoked && !cert.revoked {
						cert.revoked = true
						Storage.shared.saveContext()
					}
				}
			}
			await MainActor.run {
				_isCheckingOCSP = false
			}
		}
	}

	@ViewBuilder
	private var macHardwareAndXcodeBanner: some View {
		GroupBox("Apple Silicon Mac Signing Environment") {
			VStack(alignment: .leading, spacing: 10) {
				HStack {
					Label("Provisioning UDID:", systemImage: "desktopcomputer")
						.font(.subheadline.weight(.medium))
					Text(MacCertificateTrustService.primaryProvisioningUDID())
						.font(.caption.monospaced())
						.textSelection(.enabled)
					Spacer()
					Button("Copy UDID") {
						UIPasteboard.general.string = MacCertificateTrustService.primaryProvisioningUDID()
					}
					.controlSize(.small)
				}

				Divider()

				HStack {
					Text("Auto-Detected Local Xcode Identities (\(_xcodeIdentities.count))")
						.font(.subheadline.weight(.semibold))
					Spacer()
					Button("Rescan Keychain & Xcode") {
						_xcodeIdentities = MacCertificateTrustService.discoverLocalXcodeIdentities()
					}
					.controlSize(.small)
				}

				if _xcodeIdentities.isEmpty {
					Text("No local Xcode provisioning profiles found. Add an Apple ID in Xcode > Settings > Accounts to enable Method 3 (Local Xcode WrappedBundle Signing), or use Method 1 (Certless) with zero setup.")
						.font(.caption)
						.foregroundStyle(.secondary)
				} else {
					ForEach(_xcodeIdentities) { id in
						HStack {
							Image(systemName: id.provisionsThisMac ? "checkmark.seal.fill" : "iphone")
								.foregroundStyle(id.provisionsThisMac ? .green : .secondary)
							VStack(alignment: .leading, spacing: 1) {
								Text(id.commonName)
									.font(.caption.weight(.semibold))
								Text("\(id.profileName) • Expires \(id.expirationDate.formatted(date: .abbreviated, time: .omitted))")
									.font(.caption2)
									.foregroundStyle(.secondary)
							}
							Spacer()
							Text(id.provisionsThisMac ? "Mac UDID Ready" : "iOS Only")
								.font(.caption2.weight(.semibold))
								.padding(.horizontal, 8)
								.padding(.vertical, 3)
								.background(Capsule().fill((id.provisionsThisMac ? Color.green : Color.orange).opacity(0.18)))
						}
					}
				}
			}
			.padding(6)
		}
	}
	#endif
}

extension CertificatesView {
	@ViewBuilder
	private func _cellButton(for cert: CertificatePair, at index: Int) -> some View {
		Button {
			_selectedCertBinding.wrappedValue = index
		} label: {
			VStack(alignment: .leading, spacing: 8) {
				CertificatesCellView(cert: cert)
				#if os(macOS)
				if let uuid = cert.uuid, let ocsp = _ocspStatuses[uuid] {
					HStack(spacing: 8) {
						Label(ocsp.status.rawValue, systemImage: ocsp.status == .valid ? "checkmark.shield.fill" : (ocsp.status == .revoked ? "xmark.shield.fill" : "questionmark.circle"))
							.font(.caption.weight(.semibold))
							.foregroundStyle(ocsp.status == .valid ? .green : (ocsp.status == .revoked ? .red : .orange))

						let compat = MacCertificateTrustService.evaluateMacCompatibility(
							provision: Storage.shared.getProvisionFileDecoded(for: cert)
						)
						if case .macWrappedBundleReady = compat {
							Text("• Mac WrappedBundle Ready")
								.font(.caption)
								.foregroundStyle(.green)
						} else {
							Text("• iOS Export / OTA (No Mac UDID)")
								.font(.caption)
								.foregroundStyle(.secondary)
						}

						Spacer()

						if !ocsp.isTrustedInKeychain, let p12URL = Storage.shared.getFile(.certificate, from: cert) {
							Button("Import to Mac Keychain") {
								let res = MacCertificateTrustService.importP12IntoLoginKeychain(
									p12URL: p12URL,
									password: cert.password ?? ""
								)
								UIAlertController.showAlertWithOk(title: res.success ? "Keychain Updated" : "Keychain Error", message: res.message)
								runLiveOCSPChecks()
							}
							.controlSize(.mini)
						}
					}
				}
				#endif
			}
			.padding()
			.background(
				RoundedRectangle(cornerRadius: 16)
					.fill(Color(uiColor: .quaternarySystemFill))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 16)
					.strokeBorder(
						_selectedCertBinding.wrappedValue == index ? Color.accentColor : Color.clear,
						lineWidth: 2
					)
			)
			.contextMenu {
				_contextActions(for: cert)
				Divider()
				_actions(for: cert)
			}
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private func _actions(for cert: CertificatePair) -> some View {
		Button(role: .destructive) {
			Storage.shared.deleteCertificate(for: cert)
		} label: {
			Label(.localized("Delete"), systemImage: "trash")
		}
	}

	@ViewBuilder
	private func _contextActions(for cert: CertificatePair) -> some View {
		Button {
			_isSelectedInfoPresenting = cert
		} label: {
			Label(.localized("Get Info"), systemImage: "info.circle")
		}
	}
}
