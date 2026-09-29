# Android release and Play Protect

The repository is public. Never commit an upload keystore, passwords, subscription URLs, server credentials, or provider tokens.

## Distribution policy

- Push builds run analysis/tests and package preview APKs for CI verification, but do not publish them as downloadable artifacts.
- Version tags (`v…`) create a **signed Android App Bundle (AAB)** only. The draft GitHub Release is for transferring that AAB to Google Play Console.
- To avoid sideloading warnings, publish through Google Play and enable **Play App Signing**. A stable upload-key signature is required for updates, but it cannot guarantee Play Protect approval for an APK installed outside Google Play.
- Do not publish a version tag until the application ID, signing secrets, legal/runtime notices, and device tests are ready.

## One-time setup required by the owner

1. Choose a unique Android application ID before the first store upload. It is permanent after publication. Configure it as the repository **Actions variable** `ANDROID_APPLICATION_ID` (for example, a reverse-domain ID you own; do not copy the example unless you control that domain).
2. On a trusted computer, create an upload key and keep a backup in a password manager or encrypted offline storage:

   ```sh
   keytool -genkeypair -v -keystore v2rayag-upload.jks -alias v2rayag-upload -keyalg RSA -keysize 2048 -validity 10000
   ```

3. In **GitHub → V2rayAG-VPN → Settings → Secrets and variables → Actions**, create these repository secrets:
   - `ANDROID_UPLOAD_KEYSTORE_BASE64` — Base64 of the `.jks` file (macOS: `base64 < v2rayag-upload.jks | tr -d '\n'`; Linux: `base64 -w 0 v2rayag-upload.jks`).
   - `ANDROID_UPLOAD_KEYSTORE_PASSWORD`
   - `ANDROID_UPLOAD_KEY_ALIAS`
   - `ANDROID_UPLOAD_KEY_PASSWORD`
4. Keep the keystore and its passwords private. Never send them to the agent or add them to a commit.
5. Increase the app version/build number in `flutter_app/pubspec.yaml` for every Play upload. In Play Console, create the app using the **same** application ID, enroll in Play App Signing, and upload the signed AAB to an internal-testing track. Install the test build using the Play Store testing link; do not use a GitHub APK for the no-sideload-warning path.

Until the application ID and signing secrets are configured, a version-tag build intentionally stops instead of creating a misleading or unsigned Play release.
