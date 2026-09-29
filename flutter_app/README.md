# V2rayAG VPN — Flutter client

A mobile VPN app by **V2rayAG telegram channel and HashtagAlireza**. Official channel: [@V2rayAG](https://t.me/V2rayAG).

## Current implementation

- The original Flutter UI remains, with actual connect/disconnect, OS VPN permission, engine status, traffic counters, and latency calls wired to `flutter_vless` 1.1.6 on Android.
- Share-link parsing for VLESS, VMess, Shadowsocks, and Trojan uses the Xray-backed plugin.
- Connection config is held in app memory and handed to the native engine only when connecting. The Flutter app does not write it to preferences or log it. Native runtime retention and diagnostic behavior have not yet been audited; do not commit live configs or share diagnostics/screenshots containing server details.
- The app never obtains or displays the device/source/public IP. It shows the destination host and port from the imported profile. Country remains explicitly unknown until a trusted, privacy-reviewed metadata source is chosen.
- Subscription import supports Base64 or newline-separated VLESS, VMess, Shadowsocks, and Trojan links from direct HTTPS URLs. Redirects are rejected to avoid forwarding credential-bearing URLs. User subscription URLs are stored only through Android Keystore-backed encrypted storage; imported server profiles remain in app memory.
- The Connect screen has an **Exclusive V2rayAG Subs** one-tap path. No private provider URL is bundled: the user must enter or scan it once in the app. Other subscriptions can be added by name using clipboard paste or QR scanning, edited, refreshed, or removed.
- One-tap Exclusive connection tries up to eight profiles sequentially only after the native engine specifically rejects a profile configuration. Permission and general platform-start failures stop the retry loop; manual server selection remains available.

## Platform status

The Dart connect flow currently targets Android. It refuses to start another tunnel until the native engine explicitly reports `disconnected`, and it permits stopping a pending startup. If status remains unknown, connecting stays disabled rather than guessing whether a system VPN is already active. GitHub Actions generates the Android scaffold, analyzes/tests Dart, and packages APKs to verify compilation; no on-device end-to-end VPN connection has been verified. The plugin uses Android `VpnService`; encrypted storage requires minSdk 23 or newer, which CI configures. The plugin wrapper is pinned to 1.1.6 for reproducible parser/runtime behavior.

iPhone is not configured yet. It requires an iOS Packet Tunnel / Network Extension target, App Group and shared Keychain setup, Apple Developer signing, and physical-device tests. The Dart engine intentionally reports Android-only until that integration is completed. Web is a management companion only and cannot tunnel all device traffic.

## Release distribution and Play Protect

CI does not publish installable APK artifacts. Version tags produce a signed AAB for Google Play only after the owner configures a unique permanent Android application ID and upload-key secrets. Follow [ANDROID_RELEASE.md](ANDROID_RELEASE.md). A sideloaded APK may still receive a Play Protect warning; no code or signing-key change can guarantee otherwise. Distribute through Google Play with Play App Signing for the supported no-sideload-warning path.

## Generate and run Android locally

Install a Flutter stable release with Dart 3.8+ and the Android SDK/Android Studio. From this folder:

```sh
flutter create --platforms=android --project-name=v2rayag_vpn .
flutter pub get
flutter test
flutter analyze
flutter run -d android
```

If Android packaging requires it, follow the plugin's documented Gradle native-library extraction setting (`useLegacyPackaging = true`). Keep generated signing files local and out of Git.

Use a server link you control for device testing. Never commit credentials, UUIDs, passwords, subscription URLs, signing keys, or private certificates.

## Core and source references

- Flutter wrapper: [`flutter_vless`](https://pub.dev/packages/flutter_vless) v1.1.6 (MIT wrapper; preserve its notices).
- Native Xray runtimes have their own bundled notices and licensing. Review and ship the exact required notices before release; this project does not make a legal determination.
- [Android integration guide](https://github.com/XIIIFOX/flutter_vless/blob/main/doc/platform/android.md)
- [iOS integration guide](https://github.com/XIIIFOX/flutter_vless/blob/main/doc/platform/ios.md)
- [Security boundaries](https://github.com/XIIIFOX/flutter_vless/blob/main/doc/security.md)

## Still to build

1. Generate/check in Android platform scaffolding and run real-device tests.
2. Verify the Xray runtime notices and dependency checksums in release builds.
3. Test secure subscription storage, HTTPS refresh, clipboard/QR import, and the exclusive one-tap flow on real Android devices.
4. Add the iPhone extension, entitlements, signing, and device testing.
5. Add trusted server-country metadata without any lookup or display of the user's source IP.

The earlier interactive prototype remains in `../prototype/`.
