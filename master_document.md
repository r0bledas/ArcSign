# Master Document: ESign, KSign & Native macOS IPA Sideloading (`ArcSign`)

## 1. Overview of On-Device iOS Sideloading

iOS and iPadOS enforce strict code-signing requirements: every executable application must carry a valid cryptographic signature recognized by Apple (`amfid` / CoreTrust) before the kernel permits execution. Traditionally, sideloading `.ipa` files outside the App Store required a computer (e.g., AltStore or Sideloadly) to sign apps using a free or paid Apple ID.

**ESign** and **KSign** are on-device IPA signers that perform code signing natively using imported signing credentials (`.p12` + `.mobileprovision`).

### Core Cryptographic & Packaging Entities

* **`.ipa` (iOS App Store Package):** A ZIP archive containing `Payload/<AppName>.app` (Mach-O ARM64 executable, `Info.plist`, assets, embedded frameworks, and extensions).
* **FairPlay DRM (`LC_ENCRYPTION_INFO_64` / `cryptid`):** Binaries downloaded directly from the App Store are encrypted with FairPlay (`cryptid != 0`) bound to the purchaser's Apple ID. Third-party sideloaders require **decrypted** `.ipa`s (`cryptid == 0`), except when installing one's own App Store `.ipa` via macOS's built-in `iOS App Installer.app`.
* **`.p12` (PKCS#12 Archive):** Password-protected container holding the private cryptographic key and X.509 signing certificate issued by Apple.
* **`.mobileprovision` (CMS-Signed Provisioning Profile):** Maps an App ID (`CFBundleIdentifier`), Team ID, allowed Entitlements, and authorized devices (`ProvisionedDevices` UDIDs, or `ProvisionsAllDevices = true` for Enterprise In-House profiles).
* **Anti-Revoke DNS (iOS):** Because free iOS sideloading frequently relies on shared/leaked Enterprise certificates that Apple revokes, iOS users install custom DNS/VPN profiles blocking Apple's verification domains (`ppq.apple.com`, `ocsp.apple.com`, `ocsp2.apple.com`) so iOS cannot receive revocation updates.

---

## 2. ESign (iOS Reference)

**ESign** is one of the earliest heavy-duty on-device iOS IPA signers, designed around a dense file-manager workflow for deep `.ipa` manipulation.

### Key Mechanics & Features
1. **No-PC Installation:** Installed via Safari (`itms-services://`) using an Enterprise certificate and trusted under *Settings > General > VPN & Device Management*.
2. **Encrypted & Standard Repo Integration:** Supports both standard AltStore `.json` repositories and obfuscated/AES-encrypted ESign repository feeds (`source[...]`).
3. **Deep Payload & Binary Tweaking:**
   * Unpacks `.ipa` archives for direct file editing inside `Payload/<App>.app`, including `Info.plist` and hex editing.
   * Injects or removes `.dylib` and `.deb` tweaks (`CydiaSubstrate` / `ElleKit` load-command patching).
   * Alters `CFBundleIdentifier` (for side-by-side duplicate apps), display name, version, minimum OS version, and strips Watch/PlugIn extensions.
4. **Local Signing Engine:** Signs modified bundles locally with `.p12` + `.mobileprovision` and installs via a local loopback HTTPS `itms-services://` server.

---

## 3. KSign & Feather Architecture (Open-Source Ecosystem)

**KSign** (`Nyasami/Ksign`), built atop **Feather** (`claration/feather`), modernizes ESign's capabilities inside a clean SwiftUI architecture backed by modular Swift packages:

* **`Zsign` / `ZsignSwift` (`zhlynn/zsign` + `khcrysalis/Zsign-Package`):** C++17 + OpenSSL engine that parses Mach-O load commands, injects/removes `@rpath` `.dylib` entries, generates `CodeResources` SHA-1/SHA-256 hashes, embeds CMS signatures and entitlements, and queries OCSP responders (`checkCert`).
* **`AltSourceKit`:** Parses AltStore `.json` repositories and includes `ASDecrypt` + `EsignSourceKey` to decrypt ESign-format repository sources natively.
* **`ArArchiveKit` + `SWCompression` + `ZIPFoundation`:** Extracts `.deb` (`ar` + `tar.gz`/`tar.xz`) tweaks, bundles `ellekit.deb`, and packs/unpacks `.ipa`/`.tipa` archives.
* **`IDeviceKit` (`jkcoxson/idevice`):** Communicates with USB/Wi-Fi paired iOS/iPadOS devices for remote installation.
* **UI Features:** Adds **Bulk Signing**, background queue processing, built-in `PlistEditorView` & `HexEditorView`, certificate management, and system logs.

---

## 4. Apple Silicon macOS IPA Sideloading: How It Actually Works

Apple Silicon Macs (`arm64`) can natively execute iOS binaries, yet individual macOS sideloading methods fail in different scenarios. Understanding the kernel, `amfid` (Apple Mobile File Integrity), and `securityd` rules with **System Integrity Protection (SIP) enabled** explains why:

### Why Single-Method Mac Tools Fail

1. **Official `/System/Library/CoreServices/Applications/iOS App Installer.app`:**
   * Works **only** for FairPlay-encrypted `.ipa`s purchased by the same Apple ID (when the developer hasn't opted out of Mac execution) or MDM-authorized packages. Silently rejects decrypted `.ipa`s, tweaked apps, and quarantine-flagged bundles.
2. **Raw `WrappedBundle` + Leaked iOS Enterprise Certificates (`Killed: 9`):**
   * Native iOS-on-Mac apps use a wrapper bundle structure in `/Applications`:
     ```text
     <AppName>.app/
     ├── WrappedBundle -> Wrapper/<PayloadApp>.app
     └── Wrapper/
         └── <PayloadApp>.app/
     ```
   * On modern macOS (Sonoma, Sequoia, and newer) with **SIP enabled**, `amfid` **blocks** unmodified `PLATFORM_IOS (2)` binaries signed with leaked iOS Enterprise certificates (`ProvisionsAllDevices = true`) unless enrolled via corporate MDM—immediately terminating them with `SIGKILL` (`Killed: 9`).
   * `WrappedBundle` (`PLATFORM_IOS`) **does** work with SIP enabled when signed by a **Developer / Free Apple ID profile that explicitly lists the Mac's Provisioning UDID** in `ProvisionedDevices`.
3. **Mach-O `MacCatalyst` Conversion + Ad-Hoc Signing (PlayCover-style):**
   * Unlike iOS (which forbids ad-hoc `codesign -s -` signatures), **macOS with SIP enabled permits ad-hoc signed `arm64` binaries** if their Mach-O `LC_BUILD_VERSION` load command targets `PLATFORM_MACCATALYST (6)` instead of `PLATFORM_IOS (2)` and `@rpath/libswiftUIKit.dylib` is remapped to `/System/iOSSupport/usr/lib/swift/libswiftUIKit.dylib`.
   * **Advantage:** Requires **zero certificates**, **zero Apple ID**, **never expires**, and **never revokes**.
   * **Catch (`errSecMissingEntitlement = -34018`):** Because ad-hoc binaries have no Apple Team ID, macOS `securityd` denies Data Protection Keychain calls (`SecItemAdd` / `SecItemCopyMatching`). Apps like **Instagram** crash or fail login unless a Keychain interposer (`MacKeychainShim.dylib` / PlayCover's `PlayChain`) redirects `-34018` calls to local container storage, or unless signed via a UDID-provisioned Apple ID profile (`WrappedBundle`).

---

## 5. Certificate Revocation: macOS vs. iOS

| Aspect | iOS / iPadOS | macOS (Apple Silicon) |
| :--- | :--- | :--- |
| **Verification Daemons** | `amfid`, `misagent`, `trustd` | `amfid`, `syspolicyd` (Gatekeeper), `trustd` |
| **Apple Endpoints Checked** | `ppq.apple.com`, `ocsp.apple.com`, `ocsp2.apple.com` | `ocsp.apple.com`, `ocsp2.apple.com`, `crl.apple.com` |
| **Revocation Error** | *"Unable to Verify App"* / immediate crash | `CSSMERR_TP_CERT_REVOKED` / Gatekeeper block / `Killed: 9` |
| **OCSP Caching** | Aggressive profile/PPQ invalidation | `trustd` caches OCSP responses locally for ~3–7 days |
| **Anti-Revoke DNS / Hosts** | Common via NextDNS / local VPN profiles | `/etc/hosts` `ocsp.apple.com` block only works *before* revocation is cached and can break Mac App Store / Xcode auth |
| **Certless Alternative?** | No (requires TrollStore exploit or jailbreak) | **Yes** (`MacCatalyst` Mach-O conversion + ad-hoc `codesign -s -`) |

---

## 6. `ArcSign` Unified 5-Method Architecture

Forked from `Nyasami/Ksign` and ported natively to Apple Silicon macOS (`SDKROOT = macosx`, `arm64`), **`ArcSign`** unifies **all 5 sideloading and signing engines** in one application:

| Method | Cert Required? | Expires / Revokes? | Best For |
| :--- | :--- | :--- | :--- |
| **1. Certless Mac (`MacCatalyst` + Ad-Hoc + `MacKeychainShim.dylib`)** | **None** | **Never** | 80–90% of decrypted `.ipa`s, tweaked apps, games (default Mac mode) |
| **2. `WrappedBundle` (`.p12` + `.mobileprovision` via `ZsignSwift`)** | Dev `.p12` with Mac UDID | Per cert (1 yr / OCSP) | Apps requiring unmodified `PLATFORM_IOS` binary execution |
| **3. Local Xcode / Keychain Identity (`WrappedBundle`)** | Free/Paid Xcode login | 7 days (Free) / 1 yr (Paid) | Stock apps (e.g., stock Instagram) needing real Apple Keychain entitlements without exporting `.p12` |
| **4. Official macOS `iOS App Installer.app` Handoff** | Apple ID ownership / MDM | Never (App Store) | FairPlay-encrypted (`cryptid != 0`) `.ipa`s owned by your Apple ID |
| **5. Export `.ipa` / USB-WiFi (`IDeviceKit`) / LAN OTA (`ServerInstaller`)** | Enterprise or Dev `.p12` | Per cert / Anti-Revoke DNS | Signing on Mac and installing onto iPhones & iPads |

### Cloned Open-Source Reference Repositories (`references/`, Gitignored)
* `references/Ksign` — Upstream `Nyasami/Ksign` (SwiftUI + `AltSourceKit` + `NimbleKit` + `Zsign` + `IDeviceKit`).
* `references/Feather` — Upstream `claration/feather`.
* `references/zsign` & `references/Zsign-Package` — Core C++17 / OpenSSL Mach-O code-signing library.
* `references/PlayCover` — Reference for Apple Silicon `Macho.convertMacho`, entitlements, and `PlayChain` concepts.
