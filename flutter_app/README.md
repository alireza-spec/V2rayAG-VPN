# V2rayAG VPN — Flutter foundation

Flutter client foundation for **V2rayAG VPN**.

- Source: Telegram [@V2rayAG](https://t.me/V2rayAG)
- Developer: V2rayAG telegram channel and HashtagAlireza

## Current milestone

This Flutter app provides a responsive mobile interface, local light/dark and accessibility preferences, and a single-link **metadata preview** for VLESS, VMess, Shadowsocks, and Trojan share links.

It is **not a VPN client yet**: there is no tunnel engine, no traffic routing, no live ping, no IP geolocation, no notification service, and no Android/iOS VPN service integration. The connect control is intentionally inactive. Imported links are parsed in memory for a preview; the original URI and credentials are discarded, and no subscription URL is fetched or stored.

The app never obtains or displays the device's public/source IP. It displays only the host and port from the selected server link. A country is shown as unknown until trusted server metadata is integrated; this milestone does not perform geolocation.

## Run

Install Flutter (3.27 or newer) and the Android or iOS toolchain, then:

```sh
flutter pub get
flutter test
flutter run
```

Flutter platform folders (`android/`, `ios/`, and web build scaffolding) are generated with `flutter create` as a separate setup step. No signing credentials or live VPN configs belong in Git.

## Next engineering milestones

1. Generate and validate Android and iOS Flutter platform projects.
2. Select a maintained VPN core and confirm its licensing, protocol coverage, platform support, and update/security posture before integration.
3. Design a secure configuration model and encrypted local storage; implement subscription URL fetching only with clear consent and careful redirect/secret handling.
4. Add Android `VpnService` integration and test on real devices; then handle Apple's Network Extension entitlement, signing, and iOS integration.
5. Add real server metadata and latency checks without querying or displaying a user's source IP.
6. Add integration tests and release builds. Web remains a management companion, not a device-wide VPN tunnel.

The prototype remains in `prototype/`; this folder is the Flutter app source foundation.
