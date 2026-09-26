# Build, test and release

## Toolchain

The tested toolchain is Flutter **3.47.5** (Dart **3.13.4**), JDK **17**, and an Android SDK accepted by `flutter doctor`. Install the versions required by `pubspec.yaml`, `pubspec.lock` and the Android Gradle configuration. Do not commit machine-specific `android/local.properties`.

```sh
flutter doctor
flutter pub get
flutter analyze --no-pub
flutter test --reporter expanded
flutter build apk --release --target-platform android-arm64
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

On a resource-limited builder, bound Gradle concurrency rather than assuming every build failure is an out-of-memory error:

```sh
export GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.jvmargs=-Xmx3g'
```

Use a real Android phone to validate background behavior, lifecycle transitions, notification permissions and layout. Unit/widget tests cover protocol and UI regressions but cannot establish long-term device reliability.

## Signing

With no signing environment, `flutter build apk --release` uses the Android **development/debug key**. That is convenient for local testing, not the maintainer's public release identity.

To sign a distribution build, supply all of:

- `HERMES_ANDROID_KEYSTORE`: absolute path to your private keystore, outside the repository.
- `HERMES_ANDROID_STORE_PASSWORD`: keystore password.
- `HERMES_ANDROID_KEY_PASSWORD`: key password.
- `HERMES_ANDROID_KEY_ALIAS`: alias (defaults to `hermes-mobile`).

Read these values from your private secret store/build environment. Never print them to logs, include them in screenshots, commit them, or attach the keystore to a release. Back up the signing key securely: future updates require the same signing identity.

GitHub Release APKs are signed with the maintainer's dedicated distribution key. The Actions workflow does **not** receive that key; it uploads clearly labeled development-signed build artifacts instead. An APK signed by a different key cannot update an existing installation. Do not uninstall an existing app without considering its local credentials and downloaded files.

## Release checklist

1. Run analysis and the full test suite.
2. Build a signed ARM64 release using the private environment above.
3. Inspect APK metadata and signing certificate with Android SDK `aapt` and `apksigner`.
4. Scan both staged source and compiled application strings for credentials, private addresses and personal data.
5. Copy the APK to `hermes-mobile-android-arm64.apk` (keep this filename stable for the README direct-download button).
6. Compute the manifest:

```sh
sha256sum hermes-mobile-android-arm64.apk > SHA256SUMS.txt
```

7. Create a GitHub release with the matching version tag, attach both files and describe compatibility/known limits.
8. Download the published asset back, verify its hash and signing identity, and test the README's `/releases/latest/download/hermes-mobile-android-arm64.apk` link.

## Verify a download

Download the APK and `SHA256SUMS.txt` from the same release, then run:

```sh
sha256sum -c SHA256SUMS.txt
```

On systems without `sha256sum`, use the platform's SHA-256 tool and compare the complete digest. Checksums detect corruption but do not substitute for trusting the publishing account and signing identity.

## CI artifacts versus releases

Every push or pull request triggers the Android workflow: dependency resolution, static analysis, tests, ARM64 APK build and artifact upload. Download these artifacts from the workflow run's **Artifacts** section (GitHub sign-in may be required).

For regular installation, use the **Release APK** linked from the README. It has a stable maintainer signing identity, a direct-download URL and a checksum manifest. Re-running CI may generate a new development signing key, so Actions artifacts should not be treated as a stable update channel.
