# ArcSign

**Native Apple Silicon macOS 5-Engine IPA Signer, Tweaker & Sideloader**

**ArcSign** is a lightweight, native macOS (`arm64`, macOS 14.0+) desktop IPA signer and sideloader forked from [Nyasami/Ksign](https://github.com/Nyasami/Ksign) (built on [Feather](https://github.com/claration/feather) and [zsign](https://github.com/zhlynn/zsign)).

Unlike single-purpose macOS sideloaders that break when Apple's `amfid` blocks leaked iOS Enterprise certificates (`Killed: 9`), when ad-hoc binaries hit `errSecMissingEntitlement (-34018)` on Keychain logins, or when an `.ipa` is FairPlay-encrypted, **ArcSign unifies all 5 macOS & iOS sideloading engines** inside one native AppKit/SwiftUI application—with **SIP enabled**.

---

## Unified 5-Engine Architecture

When you drop an `.ipa` or `.tipa` into ArcSign, `MacBundleInstaller` inspects the Mach-O header (`LC_BUILD_VERSION`, `arm64` slice, and FairPlay `LC_ENCRYPTION_INFO_64` `cryptid`) and recommends the best installation path while letting you choose any of the 5 engines:

| Engine | Certificate Required? | Expires / Revokes? | How It Works & Best Use Case |
| :--- | :--- | :--- | :--- |
| **1. Certless Mac (`MacCatalyst` + Ad-Hoc + `MacKeychainShim.dylib`)** | **None** | **Never** | Rewrites `PLATFORM_IOS (2)` $\rightarrow$ `PLATFORM_MACCATALYST (6)`, remaps `@rpath/libswiftUIKit.dylib` to `/System/iOSSupport/...`, injects `MacKeychainShim.dylib` (`DYLD_INTERPOSE` container Keychain store preventing `-34018` crashes), and ad-hoc signs (`codesign -s -`). Runs permanently on Apple Silicon Macs with SIP enabled. |
| **2. `WrappedBundle` Mac Install (`.p12` + `.mobileprovision`)** | Dev `.p12` with Mac UDID | Per cert (OCSP) | Signs unmodified `PLATFORM_IOS` binaries via `ZsignSwift` and wraps them in macOS's native `Wrapper/<App>.app` + `WrappedBundle` symlink structure. Includes live OCSP revocation checking (`Security.framework`) and Mac Provisioning UDID verification. |
| **3. Local Xcode / Apple ID Sign (`WrappedBundle`)** | Free or Paid Xcode login | 7 days (Free) / 1 yr (Paid) | Auto-discovers `Apple Development` identities in your Mac's login Keychain and matching Xcode profiles in `~/Library/Developer/Xcode/UserData/Provisioning Profiles` for stock apps needing genuine Apple Keychain entitlements without exporting a `.p12`. |
| **4. Official macOS `iOS App Installer.app` Handoff** | Apple ID ownership / MDM | Never (App Store) | Strips quarantine attributes and hands off FairPlay-encrypted (`cryptid != 0`) App Store `.ipa`s owned by your Apple ID directly to `/System/Library/CoreServices/Applications/iOS App Installer.app`. |
| **5. Export `.ipa` / USB-WiFi (`devicectl`) / LAN OTA** | Dev or Enterprise `.p12` | Per cert / Anti-Revoke DNS | Signs `.ipa`s on your Mac with `.dylib`/`.deb` tweak injection (`ElleKit`), bundle ID/name spoofing, and Plist/Hex editing, then exports `.ipa`, installs directly to paired iPhones/iPads via `xcrun devicectl`, or serves `itms-services://` over LAN (`Network.framework`). |

---

## Key Features

- **Lightweight Native Footprint (~32 MB `.app`):** Replaces heavy multi-hundred-megabyte external binary frameworks and server stacks with Apple's built-in `Network.framework` (`NWListener`) for LAN OTA and `xcrun devicectl` for iOS USB/Wi-Fi installation.
- **Window Mode & Scale Controls (`MacWindowShim`):** Choose **iPhone (`9:16`)**, **iPad (`4:3`)**, or **Desktop (Free)** aspect ratios and `0.75×` / `1.0×` / `1.25×` scaling per app, with automatic macOS `Contents/` bundle restructuring and stripping of encrypted iOS-only `.appex` extensions.
- **In-App Storage & App Data Cleaner:** Auto-cleans `.ipa` archive caches after install, displays live workspace cache usage in **Settings**, and lets you wipe saved logins (`.ArcSignKeychain`), preferences, and caches for sideloaded apps in one click.
- **AltStore & Encrypted ESign Repo Browser:** Built-in `AltSourceKit` support for browsing, decrypting (`ASDecrypt`), and downloading from both AltStore `.json` sources and encrypted ESign repositories.
- **Tweak & Payload Studio:** Inject `.dylib` and `.deb` tweaks, bundle `ellekit.deb`, edit `Info.plist` and binary files in-app, strip extensions, or clone apps side-by-side with custom `CFBundleIdentifier`s.
- **Live OCSP Certificate & Mac UDID Inspector:** Verifies `.p12` revocation status live against Apple OCSP via `Security.framework` (with WWDR G2–G6 support) and checks whether `.mobileprovision` files authorize your Mac's Provisioning UDID—without modifying `/etc/hosts`.

---

## Requirements

- **Hardware:** Apple Silicon Mac (`arm64` — M1 / M2 / M3 / M4 or newer)
- **OS:** macOS 14.0 (Sonoma) or newer (System Integrity Protection **enabled** supported)
- **Build Tools:** Xcode 16+ with Command Line Tools (`xcrun`, `vtool`, `codesign`)

---

## Building & Running Tests

Clone the repository and build from Xcode (`ArcSign.xcodeproj`) or from the terminal:

```bash
# Build ArcSign.app (Debug)
xcodebuild -project ArcSign.xcodeproj \
  -scheme ArcSign \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  build

# Run the automated end-to-end test suite (compiles a mock iOS arm64 binary,
# converts it to MacCatalyst + injects MacKeychainShim.dylib, ad-hoc signs it,
# and executes a live Keychain roundtrip on macOS with SIP enabled)
xcodebuild -project ArcSign.xcodeproj \
  -scheme ArcSign \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  test
```

See [master_document.md](master_document.md) for a deep technical breakdown of ESign, KSign, macOS `amfid` / `WrappedBundle` internals, OCSP revocation mechanics, and Mach-O `LC_BUILD_VERSION` conversion.

---

## Credits & License

ArcSign builds upon the open-source iOS/macOS signing community:
- **[Nyasami/Ksign](https://github.com/Nyasami/Ksign)** & **[claration/feather](https://github.com/claration/feather)** — Core SwiftUI library, repository browser, and tweak workflow (GPL-3.0)
- **[zhlynn/zsign](https://github.com/zhlynn/zsign)** & **[khcrysalis/Zsign-Package](https://github.com/khcrysalis/Zsign-Package)** — C++17 / OpenSSL Mach-O code-signing and dylib injection engine
- **[PlayCover](https://github.com/PlayCover/PlayCover)** — Architectural inspiration for Apple Silicon `MacCatalyst` Mach-O header conversion and container Keychain interposition

Licensed under the **GNU General Public License v3.0** (see [LICENSE](LICENSE)).
