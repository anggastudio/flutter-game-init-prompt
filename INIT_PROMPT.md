# Flutter Mobile Game: Init Prompt

Copy everything between the two rulers into a fresh AI coding agent session
(Claude Code, Cursor, Codex, whatever) in an empty directory. Fill the
`<<< >>>` placeholders first. Delete any section that does not apply.

---

## THE PROMPT

You are setting up a new mobile game from scratch. Read this whole brief before
writing a single file, then build it in the phase order given at the end.

### 1. The game

- **Working title**: `<<< Game Name >>>`
- **Dart package name**: `<<< game_name >>>` (snake_case, internal only)
- **Bundle id / applicationId**: `<<< com.company.gamename >>>` (same on both platforms)
- **Platforms**: Android and iOS. Portrait only unless stated otherwise.
- **Genre / core loop**: `<<< one paragraph. What the player does in the first
  ten seconds, what makes them tap again, what ends a run. >>>`
- **Session length**: `<<< 30 seconds to 3 minutes, hyper-casual >>>`
- **Progression**: `<<< levels? endless with a high score? both? >>>`
- **Art direction**: `<<< pixel / flat vector / minimal geometric >>>`, palette
  `<<< hex list >>>`.
- **Audio**: `<<< short SFX only / SFX plus a loop >>>`, always mutable from the
  first screen.

### 2. Stack

Use exactly this. Do not substitute, do not add a state management library or a
code generator that is not listed.

| Concern | Package | Notes |
| --- | --- | --- |
| Rendering | `flame` **or** raw `CustomPainter` | See "Choosing a renderer" below. |
| State | `flutter_riverpod` | Hand-written providers. No `riverpod_generator`. |
| Routing | `go_router` | Only if there are more than three screens. Otherwise `Navigator`. |
| Config | `flutter_dotenv` | Single `.env` asset, see the env contract. |
| Storage | `shared_preferences` | Progress, settings, high scores. |
| Ads | `google_mobile_ads` | Banner plus rewarded. Interstitial only if the loop earns it. |
| IAP | `purchases_flutter` (RevenueCat) | Never the raw `in_app_purchase` plugin. |
| Crash reporting | `sentry_flutter` | Release builds only. |
| iOS tracking prompt | `app_tracking_transparency` | Required before personalised ads on iOS. |
| Audio | `audioplayers` | |
| Fonts | `google_fonts`, or a bundled `.ttf` for pixel art | |
| Icons / splash | `flutter_launcher_icons`, `flutter_native_splash` | dev dependencies |
| Lints | `flutter_lints` | `flutter analyze` must be clean at every handoff. |

Choosing a renderer: use **Flame** when the game has sprites, a physics-ish
update loop, particles, or a camera. Use a plain **`CustomPainter`** plus a
`Ticker` when the board is geometric and redraws are cheap (grid puzzles, snake,
2048, match-3). A `CustomPainter` game ships smaller and is easier to test.

### 3. Architecture

Dependencies point inward. The rules layer knows nothing about Flutter.

```
lib/
  main.dart                 Bootstrap only. Env, orientation, Sentry, runApp.
  app.dart                  MaterialApp, theme, router.
  core/
    env/env.dart            Typed access to .env. Every getter has a fallback.
    di/providers.dart       The whole Riverpod graph, declared in one file.
    theme/                  Palette, spacing, radii, durations, text styles.
    router/                 go_router config, if used.
    widgets/                Shared chrome: banner host, menu scaffold.
  game/
    engine/                 PURE DART. No Flutter import. The rules live here.
    models/                 Immutable value types the engine operates on.
    controller/             Riverpod notifier. The only place input meets rules.
    render/                 Flame components or CustomPainter layers. View only.
    config/                 Tuning constants: speeds, spawn rates, curves.
  features/
    <screen>/               One folder per screen: page plus its widgets.
  services/
    ads/ad_service.dart     AdMob wrapper.
    iap/purchase_service.dart
    iap/entitlements.dart   Perks as behaviour, keyed by entitlement id.
    storage/storage_service.dart
    audio/audio_service.dart
  l10n/                     ARB files, if localised.
test/
  engine/                   Unit tests against lib/game/engine. No widget harness.
```

Non-negotiable rules:

1. **The engine is pure Dart.** `lib/game/engine/` must compile and test on the
   plain Dart VM with no Flutter binding. If you need an annotation, use
   `package:meta`. This is what makes the rules testable in milliseconds.
2. **The view decides nothing.** Flame components and painters render state and
   forward input. Whether a move is legal, whether a life is lost, whether the
   run ended: all of that lives in the controller or the engine.
3. **Monetization sits behind service interfaces.** Screens depend on
   `AdService` and `PurchaseService`, never on `google_mobile_ads` or
   `purchases_flutter` types. Flattening the SDK types at the service boundary
   is deliberate.
4. **The app must run with no configuration.** A fresh clone with no `.env`
   falls back to Google's public AdMob test ids, skips Sentry, and reports the
   store as unavailable. Nothing crashes and the game is fully playable.

### 4. Configuration contract

One `.env` file at the repo root, gitignored, bundled as a Flutter asset. One
committed `.env.example` documenting every key with a comment saying where to
find its value.

Everything in `.env` is client-visible. Publishable ad unit ids, RevenueCat
**public** SDK keys, and the Sentry DSN are all designed to ship inside a mobile
binary. A Play service account JSON or a signing keystore is not; those live in
a gitignored `__secrets/` folder and are read at build time only.

Two values cannot reach the app through Dart, because they are needed before any
Dart runs:

- **Android**: `ADMOB_APP_ID_ANDROID` goes into `AndroidManifest.xml`. Parse
  `.env` in `android/app/build.gradle.kts` at configuration time and inject it
  as a `manifestPlaceholder`. Never write the id down twice.
- **iOS**: `ADMOB_APP_ID_IOS` goes into `Info.plist` via the
  `GAD_APPLICATION_IDENTIFIER` xcconfig variable. Xcode has no `.env` hook, so
  write `tool/sync_env.dart` that generates `ios/Flutter/Env.xcconfig` from
  `.env`, gitignore the generated file, and keep a committed
  `ios/Flutter/EnvDefaults.xcconfig` with the test-id fallbacks included before
  it so the real values win when present.

Required keys, at minimum:

```
APP_ENV=dev                     # dev | staging | prod
SENTRY_DSN=
SENTRY_TRACES_SAMPLE_RATE=0.2
ADMOB_APP_ID_ANDROID=           # ca-app-pub-XXXX~YYYY  (note the ~)
ADMOB_APP_ID_IOS=
ADMOB_BANNER_ANDROID=           # ca-app-pub-XXXX/ZZZZ  (note the /)
ADMOB_BANNER_IOS=
ADMOB_REWARDED_ANDROID=
ADMOB_REWARDED_IOS=
ADS_TEST_MODE=true
ADS_TEST_DEVICE_IDS=
REVENUECAT_API_KEY_ANDROID=     # goog_...
REVENUECAT_API_KEY_IOS=         # appl_...
REVENUECAT_OFFERING_ID=default
RC_ENTITLEMENT_REMOVE_ADS=remove_ads
```

Plus one `RC_ENTITLEMENT_*` line per perk, and a "gameplay tuning" block for the
economy knobs (revive counts, invincibility windows, ad cooldowns) so the numbers
can be retuned without a new build during a test cycle.

### 5. Monetization

Free to play, ad supported, with purchases that remove friction rather than sell
power.

**Ads.**

- Anchored **adaptive** banner on menu screens only. Never over live gameplay,
  never over a button.
- **Rewarded** ad as the one ad the player chooses: revive, extra hint, double
  coins. Preload it at startup and again immediately after each show, so the
  offer never spins. A revive prompt that loads for five seconds is a prompt
  nobody accepts.
- Grant the reward **only** on the SDK's reward callback, never on dismissal.
- Interstitials: only between runs, never mid-run, with a floor of at least
  three runs or 90 seconds between shows. Skip them entirely for a first
  session.
- On iOS, request App Tracking Transparency **before** `MobileAds.initialize()`,
  with a ~250ms delay after the app becomes active or the prompt is silently
  dropped.
- Every failure resolves to an outcome enum the caller can act on. Ads never
  throw into gameplay code.

**IAP through RevenueCat.**

- Model perks as **behaviour**, not as product ids. A `Perk` enum maps each perk
  to an entitlement identifier read from `.env`. Prices, titles, descriptions,
  and which products exist all come from the dashboard at runtime, so the
  catalogue can be repriced or A/B tested without a build.
- Ship at least `remove_ads`. Removing ads must not remove the rewarded ad,
  because taking that away punishes the purchase.
- Wire a single `addCustomerInfoUpdateListener`. It covers purchases, restores,
  and server-side changes with one code path.
- A **Restore purchases** button is mandatory for non-consumables on both
  stores.
- A cancelled purchase is not an error. Never report it as one, never show a
  failure toast for it.
- No key configured means the store screen shows an "unavailable" state and the
  game still runs.

**Ordering at startup.** Resolve purchases before initialising the ad SDK.
Entitlements decide whether ads should load at all, and booting AdMob for
someone who paid to remove ads is a wasted request.

### 6. Monitoring

- Sentry, initialised only when a DSN is present.
- `beforeSend` drops events in debug builds. Debug noise is the developer's own
  doing and would drown the real reports.
- `sendDefaultPii = false`. A casual game has no business collecting device
  identifiers.
- Tag every event with `APP_ENV`.
- `tracesSampleRate` from `.env`, low in production.
- Enable auto native breadcrumbs. Taps and navigation make a crash legible
  without the player having to describe what they were doing.
- Wrap the service warm-up in a try/catch that reports to Sentry and then
  continues. A failed ad SDK must never keep the menu from appearing.
- Add lightweight funnel breadcrumbs at: first launch, run started, run ended
  with score, rewarded offer shown, rewarded accepted, store opened, purchase
  completed. These are the only analytics that matter early, and they cost
  nothing.

### 7. Startup sequence

`main()` does exactly this, in this order:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `await Env.load()` (everything below reads from it, including whether Sentry
   starts at all)
3. Lock orientation, set edge-to-edge system UI
4. Open and migrate storage
5. Build the `ProviderContainer` with storage overridden in
6. Kick off service warm-up **unawaited**. Nothing here gates the first frame:
   a slow network on a cold start must not hold the menu hostage.
7. `SentryFlutter.init(..., appRunner: () => runApp(...))` when a DSN exists,
   otherwise plain `runApp`.

### 8. Tooling to create

- **`Makefile`** with self-documenting help: `android`, `ios`, `devices`, `get`,
  `test`, `analyze`, `format`, `clean`, `android:aab`, `android:aab:submit`,
  and a `shots` target that runs with ads disabled for store screenshots.
- **`scripts/run-android.sh` / `run-ios.sh`** that boot the emulator or
  simulator if it is not running, then `flutter run`, passing through extra
  args.
- **`scripts/build-aab.sh`** that reads signing config from `__secrets/`, builds
  a release App Bundle into `dist/<name>_<version>(<build>).aab`, and with
  `--submit` bumps the build number and uploads to the Play internal track via
  fastlane.
- **`tool/sync_env.dart`** for the iOS xcconfig, as described above.
- **`__secrets/README.md`** listing exactly which credential files go there and
  where each one comes from. Everything else in that folder is gitignored.

### 9. Documentation to write

Keep these current as the project moves. They are the project's memory across
agent sessions.

| File | Contents |
| --- | --- |
| `README.md` | What the game is, the 3-command quick start, project layout table, monetization summary. |
| `CLAUDE.md` | Agent rules: never touch `.env`, do not commit unless asked, run `flutter analyze` before handing back, writing style. |
| `docs/ARCHITECTURE.md` | The layering diagram, folder map, and the data flow for one player input, end to end. |
| `docs/GAME_DESIGN.md` | The loop, the difficulty curve, the economy. |
| `docs/ROADMAP.md` | Phases with checkboxes. Where work left off. |
| `docs/AGENT_LOG.md` | A dated entry per unit of work: what changed and why. |
| `docs/DECISIONS.md` | Short ADRs. One paragraph each, why not just what. |
| `docs/store-listing.md` | Title, short and full description, keywords, screenshot plan. |

### 10. Testing

- Unit tests for the engine, run on the Dart VM. Rules get a test; the UI does
  not.
- A test for every scoring, collision, or win condition rule, written against
  the models rather than the widgets.
- One smoke widget test that pumps the app and reaches the menu.
- `flutter analyze` clean is part of "done", not a separate chore.

### 11. Writing style for everything you produce

- No em dashes anywhere: code, comments, docs, commit messages. Use a period, a
  comma, or parentheses.
- Comments explain **why**, not what. Match the density of the surrounding file.
- Single quotes, trailing commas, `dart format` clean.
- User-facing copy is plain and warm. No exclamation-mark spam, no corporate
  cheer.

### 12. Build order

Ship each phase in a runnable state before starting the next. Stop after each
phase and let me test it.

1. **Scaffold.** `flutter create`, bundle id, package rename, lints, `.gitignore`
   (including the `.env*` variants and `__secrets/`), `Makefile`, run scripts,
   `README.md`, `CLAUDE.md`. Verify: `make android` and `make ios` both run the
   default counter app.
2. **Engine.** Pure Dart rules plus their unit tests, with no UI at all. Verify:
   `flutter test` passes and covers every rule.
3. **Playable core.** Renderer, controller, one screen. The game is playable and
   loses no state on a rebuild. No monetization yet, no persistence yet.
4. **Shell.** Menu, settings, pause, game over, storage of progress and high
   score, audio with a working mute.
5. **Config plumbing.** `.env`, `.env.example`, `Env`, the Gradle parse, the
   iOS xcconfig generator. Verify: the app still runs with `.env` deleted.
6. **Monetization.** Ad service, purchase service, entitlements, store screen,
   restore button. Verify with test ids and a RevenueCat sandbox account.
7. **Monitoring.** Sentry plus the funnel breadcrumbs. Verify: a deliberate
   throw in a release build reaches the dashboard.
8. **Polish.** Icons, splash, haptics, animation and transitions, reduce-motion
   handling.
9. **Release pipeline.** Keystore in `__secrets/`, signing config, `android:aab`,
   fastlane internal track, iOS archive and TestFlight, store listing assets.

### 13. How to work with me

- Do not commit while iterating. Make the change and stop so I can review and
  test it.
- Only commit when I explicitly ask. Never push to `master` unprompted.
- Never read or edit `.env`. It is my real, gitignored config. When code needs a
  new value, add the key to `.env.example` with a placeholder and tell me.
- Prefer explicit file paths over `git add -A`.
- Run `flutter analyze` after code changes and keep it clean before handing back.
- Append to `docs/AGENT_LOG.md` when you finish a unit of work.

Start with phase 1 now. Before you write anything, restate the game's core loop
in two sentences so I can confirm you understood it.

---

## Companion files

The [`reference/`](reference/) folder expands each section above into a spec you
can paste as a follow-up when the agent needs detail. The
[`templates/`](templates/) folder holds working implementations of every piece
this prompt describes.
