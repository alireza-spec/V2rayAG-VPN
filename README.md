# V2rayAG VPN

A privacy-focused VPN client by **V2rayAG telegram channel and HashtagAlireza**. Official Telegram channel: [@V2rayAG](https://t.me/V2rayAG).

## Project status

- `prototype/` — original interactive React/TypeScript design prototype. It does not route VPN traffic.
- `flutter_app/` — Flutter client source with an Android connect flow wired to the Xray-backed `flutter_vless` plugin. It supports importing individual VLESS, VMess, Shadowsocks, and Trojan share links. Profile configs remain in app memory; the Flutter app does not store them in preferences or log them. Native runtime retention/diagnostics are not yet audited.

The Flutter code never reads or displays the device's public/source IP. It displays only a destination host and port parsed from the chosen server profile. Country is marked unknown; no geolocation is performed. Subscription URLs are not fetched or stored.

## Important build status

The Dart Android connect flow is wired but cannot build/run yet: the Flutter Android platform folder has not been generated, and no APK has been built or tested on a device. It fails closed when native tunnel status is unknown and allows a pending startup to be stopped. iPhone still requires a Packet Tunnel/Network Extension, App Group/Keychain configuration, Apple signing, and physical-device tests. Web is management-only, not a device-wide VPN.

## Android setup

Install Flutter 3.27+ and Android Studio/SDK, then in `flutter_app/`:

```sh
flutter create --platforms=android --project-name=v2rayag_vpn .
flutter pub get
flutter test
flutter analyze
flutter run -d android
```

The selected plugin's Android guide requires minSdk 23 or newer. See `flutter_app/README.md` for platform details and links.

## Security

Do not commit live subscription links, server credentials, UUIDs, passwords, private keys, or signing material. Review the required license and notice files for the wrapper and bundled native runtime before distributing builds.

## Credits

- Source: [Telegram · @V2rayAG](https://t.me/V2rayAG)
- Developer: V2rayAG telegram channel and HashtagAlireza
