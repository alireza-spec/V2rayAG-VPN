# V2rayAG VPN

A privacy-focused VPN app project by **V2rayAG telegram channel and HashtagAlireza**. Official Telegram channel: [@V2rayAG](https://t.me/V2rayAG).

## Project status

The repository contains two distinct parts:

- `prototype/` — the original interactive React/TypeScript UI concept. Its connection, traffic, and latency are illustrative; it does not route VPN traffic.
- `flutter_app/` — the first Flutter client foundation, with a mobile UI, working appearance/accessibility preferences, and single-link metadata preview for VLESS, VMess, Shadowsocks, and Trojan. It does not yet contain a VPN tunnel or native Android/iOS project scaffolding.

The Flutter import preview keeps only a server name, protocol, host, and port in memory. It does not save credentials or fetch subscription URLs. Neither app reads or displays the device's public/source IP. The Flutter UI shows only the selected destination host and port; country stays unknown until trusted server metadata exists.

## Run the Flutter foundation

Install Flutter 3.27+ plus the Android/iOS toolchains, then from `flutter_app/`:

```sh
flutter pub get
flutter test
flutter run
```

Android, iOS, and web platform project folders are not generated yet. Web can be a management companion but cannot route device-wide VPN traffic.

## Next steps

1. Generate platform projects and establish clean Android/iOS debug builds.
2. Select a maintained VPN core after reviewing license, protocol support, platform compatibility, and security maintenance.
3. Design secure profile parsing and encrypted storage; implement subscription refresh with explicit user consent.
4. Integrate Android `VpnService`, then Apple's Network Extension (requires entitlement and signing).
5. Add verified destination country metadata and live ping only after the tunnel/server sources are defined.
6. Test on devices and create release builds.

Never commit live subscription URLs, server credentials, UUIDs, private keys, signing credentials, or API secrets.

## Credits

- Source: [Telegram · @V2rayAG](https://t.me/V2rayAG)
- Developer: V2rayAG telegram channel and HashtagAlireza
