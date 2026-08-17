# Configuration contract

One `.env` file at the repo root. Gitignored, bundled as a Flutter asset, read
once at startup through a typed `Env` class.

## What belongs where

| Kind of value | Lives in | Why |
| --- | --- | --- |
| AdMob app ids and ad unit ids | `.env` | Publishable. Every shipped app exposes them. |
| RevenueCat **public** SDK keys (`goog_`, `appl_`) | `.env` | Designed to ship in a client binary. |
| Sentry DSN | `.env` | A write-only ingest URL, not a credential. |
| Entitlement identifiers | `.env` | So the catalogue can change without a build. |
| Economy tuning knobs | `.env` | Retune during a test cycle without shipping. |
| Upload keystore (`.jks`) | `__secrets/` | Build-time credential. Never in the binary. |
| Play service account JSON | `__secrets/` | Publish-time credential. |
| App Store Connect API key | `__secrets/` | Publish-time credential. |
| RevenueCat **secret** key | Nowhere in the repo | Server-side only. |

The rule of thumb: if the value is already inside every copy of your published
APK, keeping it out of git buys you nothing but portability. If it can sign or
publish a build, it never touches the repo.

## Three consumers, one file

`.env` is read by three different systems at three different times.

**1. Dart, at runtime.** Through `flutter_dotenv`, because `.env` is listed as
an asset in `pubspec.yaml`. This covers ad unit ids, RevenueCat keys, the Sentry
DSN, and every tuning knob.

**2. Gradle, at Android configuration time.** The AdMob **app id** must sit in
`AndroidManifest.xml`, which is assembled long before any Dart runs. Parse
`.env` in `android/app/build.gradle.kts` and inject it as a
`manifestPlaceholder`. This keeps one source of truth instead of the id being
written down in two places that drift apart.

Parse it by hand, splitting on the first `=` only. Do not use
`Properties.load`: it treats `:` as a second separator and `\` as an escape,
which quietly mangles any value containing either.

**3. Xcode, at iOS build time.** Same problem, no equivalent hook. Generate
`ios/Flutter/Env.xcconfig` from `.env` with `tool/sync_env.dart`, gitignore the
generated file, and keep a committed `ios/Flutter/EnvDefaults.xcconfig` holding
the test-id fallbacks. Include the generated file **after** the defaults so its
values win when present.

Export only the keys iOS actually needs. An xcconfig is not a secret store, and
a value containing characters Xcode treats specially (a `//` inside a URL, for
instance) truncates silently.

## Degradation is the whole point

Every getter in `Env` has a fallback, and a missing `.env` is a `debugPrint`,
not a crash. A teammate who clones the repo and runs `flutter run` immediately
gets:

- Google's public AdMob **test** ids, serving real-looking test ads.
- No Sentry.
- A store screen reporting itself unavailable.
- A fully playable game.

That property is worth protecting. It is what makes the repo cloneable, what
keeps CI green without secrets, and what stops a forgotten key from becoming a
startup crash in production.

One exception matters: an **empty** AdMob app id makes the Ads SDK crash the app
at launch on Android. The Gradle fallback to the public test app id
(`ca-app-pub-3940256099942544~3347511713`) is not a nicety, it is what prevents
that crash.

## Test mode

`ADS_TEST_MODE=true` puts the SDK into test-device mode so it only ever serves
test ads, regardless of the unit ids configured. Keep it true in development.
Serving live ads to yourself is how an AdMob account gets flagged for invalid
traffic.

`ADS_TEST_DEVICE_IDS` takes the hashes AdMob prints to logcat or the Xcode
console after the first ad request. Add your own device and you can keep real
unit ids in `.env` while still only seeing test ads.

## Keeping `.env.example` honest

`.env.example` is committed and is the only file an agent may edit. Every key
carries a comment saying what it does and **where in which dashboard** to find
its value. When code needs a new value, the key lands in `.env.example` with an
empty placeholder and the developer copies the real value across themselves.

Gitignore every `.env` variant, not just `.env`:

```gitignore
.env
.env.*
!.env.example
```

`/.env` alone leaves `.env.local` and `.env.production` committable.
