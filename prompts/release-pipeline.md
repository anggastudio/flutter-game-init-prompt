# Follow-up prompt: release pipeline

Paste this for phase 9, once the game is feature complete and you want one
command to produce a signed, uploadable artifact.

---

Build the release pipeline. No credential may touch git, and one command must
produce a signed artifact.

## 1. `__secrets/`

Create the folder with a committed `README.md` listing exactly which files go
there and where each comes from: the upload keystore, the signing credentials,
the Play service account JSON, the App Store Connect API key. Gitignore
everything else in it with `/__secrets/` plus `!__secrets/README.md`.

Also gitignore `*.jks`, `*.keystore`, `/android/key.properties`, `/dist/`, and
`/ios/Flutter/Env.xcconfig`.

## 2. Android signing

In `android/app/build.gradle.kts`, read signing credentials from `__secrets/`,
accepting two layouts in this order: `keystore.env` with `ANDROID_*` names,
then `keystore.properties` with the Gradle-conventional names. Parse by hand,
splitting on the first `=` only. `Properties.load` mangles values containing
`:` or `\`.

Three details that save an afternoon:

- A blank key password means "same as the store password". That is what
  `keytool` does when you press enter at its prompt.
- Resolve the keystore path against several candidates: absolute, relative to
  the project root, and the bare filename inside `__secrets/`. A shared
  credentials file that moved but was not re-pathed then still resolves.
- With no signing config present, fall back to **debug** signing rather than
  failing the build, so a contributor without the keystore can still build.

Enable `isMinifyEnabled` and `isShrinkResources` on release, with a
`proguard-rules.pro` that keeps whatever the ad and purchase SDKs need.

## 3. `scripts/build-aab.sh`

Driven by `make android:aab` and `make android:aab:submit NOTES="..."`.

1. Read the version from `pubspec.yaml`. That file is the single source of
   truth for the store build.
2. On `--submit`, bump the build number (after the `+`) and write it back
   **before** building. Play rejects a duplicate versionCode and it is always
   the thing you forget.
3. `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`.
4. Copy the artifact to `dist/<name>_<version>(<build>).aab`, which is the name
   you want when three builds are sitting in the folder.
5. Upload debug symbols to Sentry with `sentry-cli`.
6. On `--submit`, run fastlane supply against the **internal** test track,
   passing the release notes through.

Fail loudly and early when a credential is missing, naming the exact file and
where to get it. Never fall through to an unsigned upload.

## 4. iOS

`make ios:archive` builds and exports the IPA; upload with fastlane `pilot`
using the App Store Connect API key from `__secrets/`.

Check these before the first upload, because each one fails silently:

- `dart run tool/sync_env.dart` has been run, so `Info.plist` carries the real
  `GAD_APPLICATION_IDENTIFIER`. Otherwise the build ships the previous id.
- `NSUserTrackingUsageDescription` is present, or ATT never prompts.
- `PrivacyInfo.xcprivacy` declares the required-reason APIs your own code uses,
  usually `UserDefaults`. AdMob and RevenueCat ship their own manifests.
- dSYMs go to Sentry, or every release crash report is unreadable.

## 5. Store assets

```
store/
  listing.md            Title, short description, full description, keywords.
  play-icon-512.png
  feature-graphic.png   1024x500, Play only.
  screenshots/          Captured with `make shots` (ads disabled).
```

Add a `make shots` target that runs with ads disabled. Never ship a screenshot
with a banner ad in it. The first two screenshots carry the hook, since they are
the only ones most people see.

## 6. Checklist

Write `docs/RELEASE.md` with the pre-submission checklist:

- [ ] `flutter analyze` clean, `flutter test` green.
- [ ] `ADS_TEST_MODE=false`, real ad unit ids, real RevenueCat keys.
- [ ] Version and build number bumped.
- [ ] Debug symbols and dSYMs uploaded to Sentry.
- [ ] A deliberate crash in a release build reached the Sentry dashboard.
- [ ] Purchase and restore both tested on a real device, on both stores.
- [ ] `app-ads.txt` live at the developer URL in the listing, matching exactly.
- [ ] Play Data safety and App Privacy answers match what the SDKs actually
      collect. Copy from AdMob's and RevenueCat's published disclosures rather
      than guessing.
- [ ] Content rating questionnaire completed.
- [ ] Target API level meets the current Play requirement.
- [ ] Tested on a low-end device, not just the emulator. A casual game lives or
      dies on cheap hardware.
