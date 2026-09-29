# V2rayAG VPN

A privacy-focused VPN app project by **V2rayAG telegram channel and HashtagAlireza**. Official Telegram channel: [@V2rayAG](https://t.me/V2rayAG).

## Current status

This repository currently contains the source for the interactive **UI prototype**. It is not yet a functioning VPN client and does not create a VPN tunnel. The connect animation, latency, endpoint examples, and traffic values are illustrative. The example endpoint IPs are reserved documentation addresses, not live servers.

The prototype deliberately does not read or display the device's real/public IP address. It shows only the selected destination endpoint and country. Do not enter a live subscription URL into the prototype; its import screen is only a visual flow and does not fetch or securely store subscriptions.

## Project contents

- `prototype/` — current Tasklet-hosted React/TypeScript interface source: overview, location selector, subscription preview, settings, and responsive styling.
- `prototype/components/` — reusable UI elements.

The prototype uses Tasklet's preview bridge for saving preferences. This source is not yet a standalone web app, Android APK, or iPhone app; it has no production tunnel implementation or release build configuration.

## Planned production work

1. Convert the interface into a production project with Android and iPhone clients, plus a web companion for account and subscription management.
2. Implement VLESS, VMess, Shadowsocks, and Trojan support using a maintained core, with platform-compliant VPN integrations (Android `VpnService` and Apple's Network Extension entitlement/signing).
3. Import and refresh subscription profiles with secure on-device credential storage. Never commit subscription URLs, server credentials, private keys, signing material, or API secrets.
4. Replace sample locations, pings, status, and traffic with live measurements from configured servers; ensure only destination endpoint IP and country are shown in the UI.
5. Add tests, privacy/security review, and platform build and release workflows.

A web app can manage profiles and settings, but browsers cannot provide a full-device VPN tunnel.

## Credits

- Source: [Telegram · @V2rayAG](https://t.me/V2rayAG)
- Developer: V2rayAG telegram channel and HashtagAlireza
