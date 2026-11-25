//
//  MacInstallSheetView.swift
//  ArcSign
//
//  Unified 5-Method Install & Sign Sheet for Apple Silicon macOS.
//

#if os(macOS)
import SwiftUI
import CoreData
import IDeviceSwift
import NimbleViews
import NimbleExtensions

struct MacInstallSheetView: View {
	@Environment(\.dismiss) private var dismiss

	let app: AppInfoPresentable

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var certificates: FetchedResults<CertificatePair>

	@State private var selectedMethod: MacInstallMethodKind = .certlessCatalyst
	@State private var injectKeychainShim: Bool = true
	@State private var windowMode: MacWindowMode = .iphone
	@State private var windowScale: MacWindowScale = .x1_0
	@State private var wipeExistingAppData: Bool = false
	@AppStorage("arcsign.autoCleanAfterInstall") private var autoCleanAfterInstall: Bool = true
	@State private var destination: MacInstallDestination = .systemApplications
	@State private var selectedCertIndex: Int = UserDefaults.standard.integer(forKey: "feather.selectedCert")
	@State private var xcodeIdentities: [LocalXcodeSigningIdentity] = []
	@State private var selectedXcodeIdentityID: String = ""
	@State private var iosSubMode: Int = 0 // 0 = Export .ipa, 1 = USB/Wi-Fi IDevice, 2 = LAN OTA

	@State private var customAppName: String = ""
	@State private var customBundleID: String = ""
	@State private var preflight: IPAPreflightReport?

	@State private var isRunning = false
	@State private var statusMessage: String = ""
	@State private var installedAppURL: URL?
	@State private var exportedIPAURL: URL?
	@State private var errorMessage: String?
	@State private var showCustomizeSigningSheet = false
	@State private var showLegacyOTAInstaller = false

	private var selectedCert: CertificatePair? {
		guard certificates.indices.contains(selectedCertIndex) else { return certificates.first }
		return certificates[selectedCertIndex]
	}

	private var selectedXcodeIdentity: LocalXcodeSigningIdentity? {
		xcodeIdentities.first(where: { $0.id == selectedXcodeIdentityID }) ?? xcodeIdentities.first
	}

	var body: some View {
		VStack(spacing: 0) {
			headerBar
			Divider()

			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					if let preflight {
						preflightBanner(preflight)
					}

					methodPickerSection
					methodConfigurationSection
					customizationSection

					if let errorMessage {
						GroupBox {
							Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
								.foregroundStyle(.red)
								.font(.callout)
								.textSelection(.enabled)
								.frame(maxWidth: .infinity, alignment: .leading)
						}
					}

					if let installedAppURL {
						installedSuccessCard(installedAppURL)
					}

					if let exportedIPAURL {
						exportedSuccessCard(exportedIPAURL)
					}
				}
				.padding(20)
			}

			Divider()
			footerBar
		}
		.frame(minWidth: 680, idealWidth: 720, minHeight: 620, idealHeight: 720)
		.onAppear(perform: loadInitialState)
		.sheet(isPresented: $showCustomizeSigningSheet) {
			SigningView(app: app, signAndInstall: false)
				.frame(minWidth: 620, idealWidth: 660, minHeight: 580, idealHeight: 660)
		}
		.sheet(isPresented: $showLegacyOTAInstaller) {
			InstallPreviewView(app: app, isSharing: false)
				.frame(minWidth: 460, minHeight: 300)
		}
	}

	@ViewBuilder
	private var headerBar: some View {
		HStack(spacing: 14) {
			FRAppIconView(app: app, size: 52)
			VStack(alignment: .leading, spacing: 3) {
				Text(app.name ?? "Unknown App")
					.font(.title3.bold())
				Text("\(app.version ?? "1.0") • \(app.identifier ?? "unknown.bundle.id")")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Button("Advanced Payload / Tweaks…") {
				showCustomizeSigningSheet = true
			}
			.buttonStyle(.bordered)
		}
		.padding(16)
	}

	@ViewBuilder
	private func preflightBanner(_ report: IPAPreflightReport) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: report.isFairPlayEncrypted ? "lock.trianglebadge.exclamationmark.fill" : "checkmark.seal.fill")
				.foregroundStyle(report.isFairPlayEncrypted ? .orange : .green)
				.font(.title3)
			VStack(alignment: .leading, spacing: 2) {
				Text("Pre-Flight Analysis • Recommended: \(report.recommendedMethod.title)")
					.font(.subheadline.weight(.semibold))
				Text(report.recommendationNote)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
		}
		.padding(12)
		.background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.09)))
	}

	@ViewBuilder
	private var methodPickerSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Sideloading / Installation Engine (All 5 Ways Supported)")
				.font(.headline)

			ForEach(MacInstallMethodKind.allCases) { method in
				Button {
					selectedMethod = method
					errorMessage = nil
				} label: {
					HStack(alignment: .top, spacing: 12) {
						Image(systemName: selectedMethod == method ? "largecircle.fill.circle" : "circle")
							.foregroundStyle(selectedMethod == method ? Color.accentColor : .secondary)
							.font(.title3)
							.padding(.top, 2)

						Image(systemName: method.icon)
							.frame(width: 20)
							.foregroundStyle(Color.accentColor)
							.padding(.top, 2)

						VStack(alignment: .leading, spacing: 2) {
							HStack {
								Text(method.title)
									.font(.subheadline.weight(.semibold))
									.foregroundStyle(.primary)
								if preflight?.recommendedMethod == method {
									Text("RECOMMENDED")
										.font(.system(size: 9, weight: .bold))
										.padding(.horizontal, 6)
										.padding(.vertical, 2)
										.background(Capsule().fill(Color.green.opacity(0.2)))
										.foregroundStyle(.green)
								}
							}
							Text(method.subtitle)
								.font(.caption)
								.foregroundStyle(.secondary)
								.fixedSize(horizontal: false, vertical: true)
						}
						Spacer()
					}
					.padding(10)
					.background(
						RoundedRectangle(cornerRadius: 10)
							.fill(selectedMethod == method ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
					)
					.overlay(
						RoundedRectangle(cornerRadius: 10)
							.stroke(selectedMethod == method ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
					)
				}
				.buttonStyle(.plain)
			}
		}
	}

	@ViewBuilder
	private var methodConfigurationSection: some View {
		GroupBox("Engine Options") {
			VStack(alignment: .leading, spacing: 10) {
				switch selectedMethod {
				case .certlessCatalyst:
					Toggle("Inject Keychain Fix (MacKeychainShim.dylib — fixes -34018 login crashes)", isOn: $injectKeychainShim)
					Picker("Window Mode", selection: $windowMode) {
						ForEach(MacWindowMode.allCases) { mode in
							Text(mode.title).tag(mode)
						}
					}
					.pickerStyle(.segmented)
					Picker("Window Scale", selection: $windowScale) {
						ForEach(MacWindowScale.allCases) { scale in
							Text(scale.title).tag(scale)
						}
					}
					.pickerStyle(.segmented)
					Toggle("Auto-clean imported IPA cache after install (saves disk space)", isOn: $autoCleanAfterInstall)
					Toggle("Wipe existing app data & saved logins before installing", isOn: $wipeExistingAppData)
					destinationPicker

				case .p12WrappedBundle:
					if certificates.isEmpty {
						Text("No .p12 + .mobileprovision certificates imported yet. Import one in the Certificates sidebar tab, or switch to Method 1 (Certless).")
							.font(.caption)
							.foregroundStyle(.orange)
					} else {
						Picker("Signing Certificate", selection: $selectedCertIndex) {
							ForEach(Array(certificates.enumerated()), id: \.offset) { idx, cert in
								Text(cert.nickname ?? Storage.shared.getProvisionFileDecoded(for: cert)?.Name ?? "Certificate #\(idx + 1)")
									.tag(idx)
							}
						}
						if let cert = selectedCert {
							let compat = MacCertificateTrustService.evaluateMacCompatibility(
								provision: Storage.shared.getProvisionFileDecoded(for: cert)
							)
							switch compat {
							case .macWrappedBundleReady(let reason):
								Label(reason, systemImage: "checkmark.circle.fill")
									.font(.caption)
									.foregroundStyle(.green)
							case .iosExportOnlyEnterprise(let reason), .iosExportOnlyMissingMacUDID(let reason):
								Label(reason, systemImage: "exclamationmark.triangle.fill")
									.font(.caption)
									.foregroundStyle(.orange)
							}
						}
					}
					destinationPicker

				case .xcodeLocalIdentity:
					HStack {
						Text("This Mac's Provisioning UDID: \(MacCertificateTrustService.primaryProvisioningUDID())")
							.font(.caption.monospaced())
							.textSelection(.enabled)
						Spacer()
						Button("Copy UDID") {
							UIPasteboard.general.string = MacCertificateTrustService.primaryProvisioningUDID()
						}
						.controlSize(.small)
						Button("Rescan Xcode") {
							xcodeIdentities = MacCertificateTrustService.discoverLocalXcodeIdentities()
							if let first = xcodeIdentities.first {
								selectedXcodeIdentityID = first.id
							}
						}
						.controlSize(.small)
					}

					if xcodeIdentities.isEmpty {
						Text("No local Xcode signing profiles found in ~/Library/Developer/Xcode/UserData/Provisioning Profiles. Sign into Xcode > Settings > Accounts and build any dummy iOS target for 'My Mac (Designed for iPad)' once, or use Method 1 (Certless).")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else {
						Picker("Xcode Identity & Profile", selection: $selectedXcodeIdentityID) {
							ForEach(xcodeIdentities) { id in
								Text("\(id.commonName) — \(id.profileName)\(id.provisionsThisMac ? " [Mac Ready]" : "")")
									.tag(id.id)
							}
						}
					}
					destinationPicker

				case .officialMacInstaller:
					Text("Packages the app back into an .ipa, strips quarantine attributes, and opens it with macOS's built-in /System/Library/CoreServices/Applications/iOS App Installer.app.")
						.font(.caption)
						.foregroundStyle(.secondary)

				case .iosExportOrOTA:
					Picker("Delivery Target", selection: $iosSubMode) {
						Text("Export Signed .ipa to Disk").tag(0)
						Text("USB / Wi-Fi iDevice / LAN OTA").tag(1)
					}
					.pickerStyle(.segmented)

					if !certificates.isEmpty {
						Picker("Certificate (.p12)", selection: $selectedCertIndex) {
							ForEach(Array(certificates.enumerated()), id: \.offset) { idx, cert in
								Text(cert.nickname ?? Storage.shared.getProvisionFileDecoded(for: cert)?.Name ?? "Certificate #\(idx + 1)")
									.tag(idx)
							}
						}
					} else {
						Text("No .p12 imported — will export with Ad-Hoc signature unless you import a .p12 in Certificates.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(6)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	@ViewBuilder
	private var destinationPicker: some View {
		Picker("Install Location", selection: $destination) {
			ForEach(MacInstallDestination.allCases) { dest in
				Text(dest.rawValue).tag(dest)
			}
		}
		.pickerStyle(.segmented)
	}

	@ViewBuilder
	private var customizationSection: some View {
		DisclosureGroup("Optional Display Name / Bundle ID Override") {
			VStack(spacing: 8) {
				TextField("Custom Display Name (leave blank to keep \(app.name ?? "original"))", text: $customAppName)
					.textFieldStyle(.roundedBorder)
				TextField("Custom Bundle Identifier (leave blank to keep \(app.identifier ?? "original"))", text: $customBundleID)
					.textFieldStyle(.roundedBorder)
			}
			.padding(.top, 6)
		}
		.font(.subheadline)
	}

	@ViewBuilder
	private func installedSuccessCard(_ url: URL) -> some View {
		GroupBox {
			HStack {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.green)
					.font(.title2)
				VStack(alignment: .leading, spacing: 2) {
					Text("Installed to \(url.path)")
						.font(.subheadline.weight(.semibold))
					Text("Quarantine attributes cleared and registered with LaunchServices.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Button("Reveal in Finder") {
					MacBundleInstaller.revealInFinder(at: url)
				}
				Button("Launch App") {
					MacBundleInstaller.launchApp(at: url)
				}
				.buttonStyle(.borderedProminent)
			}
		}
	}

	@ViewBuilder
	private func exportedSuccessCard(_ url: URL) -> some View {
		GroupBox {
			HStack {
				Image(systemName: "doc.zipper")
					.foregroundStyle(.blue)
					.font(.title2)
				Text("Exported IPA: \(url.path)")
					.font(.subheadline.weight(.semibold))
				Spacer()
				Button("Reveal in Finder") {
					MacBundleInstaller.revealInFinder(at: url)
				}
				.buttonStyle(.borderedProminent)
			}
		}
	}

	@ViewBuilder
	private var footerBar: some View {
		HStack {
			if isRunning {
				ProgressView()
					.controlSize(.small)
				Text(statusMessage)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Button("Close") {
				dismiss()
			}
			.keyboardShortcut("w", modifiers: .command)

			Button(primaryButtonTitle) {
				runSelectedMethod()
			}
			.buttonStyle(.borderedProminent)
			.disabled(isRunning)
			.keyboardShortcut(.defaultAction)
		}
		.padding(16)
	}

	private var primaryButtonTitle: String {
		switch selectedMethod {
		case .certlessCatalyst: return "Install to Mac (Certless)"
		case .p12WrappedBundle: return "Sign & Install WrappedBundle"
		case .xcodeLocalIdentity: return "Sign with Xcode & Install"
		case .officialMacInstaller: return "Open in iOS App Installer"
		case .iosExportOrOTA: return iosSubMode == 0 ? "Sign & Export .ipa…" : "Sign & Launch Device/OTA Installer"
		}
	}

	private func loadInitialState() {
		xcodeIdentities = MacCertificateTrustService.discoverLocalXcodeIdentities()
		if let first = xcodeIdentities.first {
			selectedXcodeIdentityID = first.id
		}
		if let appDir = Storage.shared.getAppDirectory(for: app) {
			let report = MacBundleInstaller.analyzeAppBundle(
				at: appDir,
				availableCerts: Array(certificates),
				xcodeIdentities: xcodeIdentities
			)
			preflight = report
			selectedMethod = report.recommendedMethod
		}
	}

	private func runSelectedMethod() {
		guard let sourceAppDir = Storage.shared.getAppDirectory(for: app) else {
			errorMessage = "Could not locate extracted .app directory in Library."
			return
		}

		errorMessage = nil
		installedAppURL = nil
		exportedIPAURL = nil
		isRunning = true

		let trimmedName = customAppName.trimmingCharacters(in: .whitespacesAndNewlines)
		let trimmedBundleID = customBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
		let overrideName = trimmedName.isEmpty ? nil : trimmedName
		let overrideID = trimmedBundleID.isEmpty ? nil : trimmedBundleID

		Task {
			do {
				switch selectedMethod {
				case .certlessCatalyst:
					await MainActor.run { statusMessage = "Converting Mach-O to MacCatalyst & signing ad-hoc…" }
					var workingAppDir = sourceAppDir
					var tempCleanup: URL?
					if overrideName != nil || overrideID != nil {
						let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ArcSign_Custom_\(UUID().uuidString)", isDirectory: true)
						try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
						let copyURL = tmp.appendingPathComponent(sourceAppDir.lastPathComponent, isDirectory: true)
						try FileManager.default.copyItem(at: sourceAppDir, to: copyURL)
						if let plist = NSMutableDictionary(contentsOf: copyURL.appendingPathComponent("Info.plist")) {
							if let overrideName { plist["CFBundleDisplayName"] = overrideName }
							if let overrideID { plist["CFBundleIdentifier"] = overrideID }
							plist.write(to: copyURL.appendingPathComponent("Info.plist"), atomically: true)
						}
						workingAppDir = copyURL
						tempCleanup = tmp
					}
					defer { if let tempCleanup { try? FileManager.default.removeItem(at: tempCleanup) } }

					if wipeExistingAppData, let targetID = overrideID ?? app.identifier {
						MacStorageManager.wipeAppData(forBundleID: targetID)
					}
					let outURL = try await MacBundleInstaller.installCertlessCatalystApp(
						sourceAppBundleURL: workingAppDir,
						customDisplayName: overrideName,
						injectKeychainShim: injectKeychainShim,
						windowMode: windowMode,
						windowScale: windowScale,
						destination: destination
					)
					if autoCleanAfterInstall {
						MacStorageManager.cleanImportAndBuildCaches()
					}
					await MainActor.run {
						installedAppURL = outURL
						isRunning = false
						statusMessage = ""
					}

				case .p12WrappedBundle:
					guard let cert = selectedCert else {
						throw MacSideloadError.missingCredentials("Please import a .p12 + .mobileprovision certificate first, or select Method 1 (Certless).")
					}
					await MainActor.run { statusMessage = "Signing with ZsignSwift & constructing WrappedBundle…" }
					let signedAppURL = try await signAppToSignedStorage(cert: cert, adhoc: false, overrideName: overrideName, overrideID: overrideID)
					let outURL = try await MacBundleInstaller.installWrappedBundle(
						signedPayloadAppURL: signedAppURL,
						customDisplayName: overrideName,
						destination: destination
					)
					await MainActor.run {
						installedAppURL = outURL
						isRunning = false
						statusMessage = ""
					}

				case .xcodeLocalIdentity:
					guard let identity = selectedXcodeIdentity else {
						throw MacSideloadError.missingCredentials("No local Xcode signing identity selected.")
					}
					await MainActor.run { statusMessage = "Signing with Local Xcode Identity & constructing WrappedBundle…" }
					let outURL = try await MacBundleInstaller.installWithLocalXcodeIdentity(
						sourceAppBundleURL: sourceAppDir,
						identity: identity,
						customBundleID: overrideID,
						customDisplayName: overrideName,
						destination: destination
					)
					await MainActor.run {
						installedAppURL = outURL
						isRunning = false
						statusMessage = ""
					}

				case .officialMacInstaller:
					await MainActor.run { statusMessage = "Packaging .ipa for macOS iOS App Installer…" }
					let vm = await MainActor.run { InstallerStatusViewModel() }
					let archiveHandler = await ArchiveHandler(app: app, viewModel: vm)
					try await archiveHandler.move()
					let ipaURL = try await archiveHandler.archive()
					try await MainActor.run {
						try MacBundleInstaller.openWithOfficialMacInstaller(ipaURL: ipaURL)
						isRunning = false
						statusMessage = ""
					}

				case .iosExportOrOTA:
					await MainActor.run { statusMessage = "Signing .ipa package with ZsignSwift…" }
					let targetApp: AppInfoPresentable
					if app.isSigned && overrideName == nil && overrideID == nil {
						targetApp = app
					} else {
						_ = try await signAppToSignedStorage(
							cert: selectedCert,
							adhoc: selectedCert == nil,
							overrideName: overrideName,
							overrideID: overrideID
						)
						targetApp = await MainActor.run {
							let req = Signed.fetchRequest()
							req.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
							req.fetchLimit = 1
							return (try? Storage.shared.context.fetch(req).first) ?? app
						}
					}

					if iosSubMode == 0 {
						let vm = await MainActor.run { InstallerStatusViewModel() }
						let archiveHandler = await ArchiveHandler(app: targetApp, viewModel: vm)
						try await archiveHandler.move()
						let ipaURL = try await archiveHandler.archive()
						await MainActor.run {
							isRunning = false
							statusMessage = ""
							let panel = NSSavePanel()
							panel.nameFieldStringValue = "\(overrideName ?? targetApp.name ?? "SignedApp").ipa"
							panel.canCreateDirectories = true
							if panel.runModal() == .OK, let dest = panel.url {
								try? FileManager.default.removeItem(at: dest)
								try? FileManager.default.copyItem(at: ipaURL, to: dest)
								exportedIPAURL = dest
							}
						}
					} else {
						await MainActor.run {
							isRunning = false
							statusMessage = ""
							showLegacyOTAInstaller = true
						}
					}
				}
			} catch {
				await MainActor.run {
					errorMessage = error.localizedDescription
					isRunning = false
					statusMessage = ""
				}
			}
		}
	}

	private func signAppToSignedStorage(
		cert: CertificatePair?,
		adhoc: Bool,
		overrideName: String?,
		overrideID: String?
	) async throws -> URL {
		var opts = OptionsManager.shared.options
		opts.doAdhocSigning = adhoc
		if let overrideName { opts.appName = overrideName }
		if let overrideID { opts.appIdentifier = overrideID }

		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			FR.signPackageFile(app, using: opts, icon: nil, certificate: cert) { err in
				if let err {
					cont.resume(throwing: err)
				} else {
					cont.resume()
				}
			}
		}

		return try await MainActor.run {
			let req = Signed.fetchRequest()
			req.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
			req.fetchLimit = 1
			guard let newest = try Storage.shared.context.fetch(req).first,
				  let dir = Storage.shared.getAppDirectory(for: newest) else {
				throw MacSideloadError.installerFailed("Signed bundle could not be located in storage.")
			}
			return dir
		}
	}
}
#endif
