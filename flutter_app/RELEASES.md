# V2rayAG VPN release builds

## Android preview APKs

Pushing Flutter app changes to `main`, opening a Flutter pull request, or manually starting **Android preview builds** runs formatting checks, tests, and three Android APK builds. Pushing a version tag such as `v0.1.0` runs the same checks and creates a **draft** GitHub Release with:

- `V2rayAG-arm64-v8a.apk` — 64-bit ARM
- `V2rayAG-armeabi-v7a.apk` — 32-bit ARM
- `V2rayAG-universal.apk` — Flutter's combined Android target architectures

The Android platform scaffold is generated during CI because it is not checked in yet. Builds are for preview/device testing, not store publication: no production signing key is configured, and VPN behavior still needs verification on real devices. The app must never include a user's subscription URL or server credentials in the repository, CI logs, or release notes.

## Other platforms

- **iPhone/iOS:** not included yet. The repository does not have the iOS Packet Tunnel / Network Extension implementation, app entitlements, or Apple signing setup required for a device-installable VPN app.
- **Web:** a browser cannot tunnel all device traffic. A web companion/management app is a separate product and is not currently packaged as a standalone release.
- **Windows `.exe`:** not included yet. The current Flutter app deliberately enables VPN operations only on Android; a desktop UI without a working tunnel would be misleading.

Add those release targets only after each platform has a functional, tested implementation. The iOS release also needs the owner's Apple Developer signing assets, held as protected GitHub secrets—not committed to the repository.
