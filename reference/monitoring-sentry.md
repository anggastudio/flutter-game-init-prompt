# Monitoring: Sentry

Package: `sentry_flutter`. Wired in `main.dart`, configured from `Env`.

## Configuration

```dart
void _configureSentry(SentryFlutterOptions options) {
  options
    ..dsn = Env.sentryDsn
    ..environment = Env.environment.name
    ..tracesSampleRate = Env.sentryTracesSampleRate
    ..replay.sessionSampleRate = 0
    ..replay.onErrorSampleRate = Env.sentryReplaySampleRate
    ..attachStacktrace = Env.sentryAttachStacktrace
    ..enableAutoNativeBreadcrumbs = true
    ..debug = !Env.environment.isProduction && kDebugMode
    ..sendDefaultPii = false
    ..beforeSend = (event, hint) => kDebugMode ? null : event;
}
```

Each line earns its place:

- **`dsn` from `.env`, and Sentry only starts when it is non-empty.** A fresh
  clone has no DSN and simply runs without error reporting rather than refusing
  to start.
- **`environment`** tags every event `dev`, `staging`, or `prod`, so a
  developer's own crash never lands in the same bucket as a player's.
- **`enableAutoNativeBreadcrumbs`** records taps and navigation. That is what
  makes a crash report legible without needing the player to describe what they
  were doing.
- **`sendDefaultPii = false`.** Sending device identifiers for a casual game is
  a poor trade against the privacy label you then have to declare.
- **`beforeSend` dropping debug events.** Debug-build noise is the developer's
  own doing and would drown the real reports coming from released builds.
- **Session replay off, error replay optional.** Replay is expensive in both
  quota and bandwidth. Keep `SENTRY_REPLAY_SAMPLE_RATE=0.0` until there is a
  crash worth watching.

## Wrapping runApp

```dart
if (Env.sentryEnabled) {
  await SentryFlutter.init(_configureSentry, appRunner: () => _runApp(container));
} else {
  _runApp(container);
}
```

Using `appRunner` rather than calling `runApp` yourself is what lets Sentry hook
the zone and catch async errors that never reach `FlutterError.onError`.

## Warm-up must not crash the app

Service initialisation runs in a try/catch that reports and then continues:

```dart
try {
  await audioService.init();
  await purchaseService.init();
  if (!entitlements.adsRemoved) await adService.init();
} catch (error, stack) {
  debugPrint('Startup: service warm-up failed ($error)');
  if (Env.sentryEnabled) await Sentry.captureException(error, stack);
}
```

A failed ad SDK is a monetization problem. It must never be a "the game does not
open" problem.

## Breadcrumbs are your analytics

Before reaching for a full analytics SDK, add breadcrumbs at the points that
answer the only questions that matter early:

| Breadcrumb | Answers |
| --- | --- |
| `app.first_launch` | How many installs actually open the game. |
| `run.started` | Do players start a second run? |
| `run.ended` with score and duration | Where the difficulty wall is. |
| `ad.rewarded_offered` / `ad.rewarded_accepted` | Is the revive offer worth its screen space? |
| `store.opened` / `purchase.completed` | The conversion funnel, in two events. |

```dart
Sentry.addBreadcrumb(Breadcrumb(
  category: 'run',
  message: 'ended',
  data: {'score': score, 'seconds': duration.inSeconds, 'level': level},
));
```

These cost nothing, ship with the crash reporter you already have, and arrive
attached to any crash that follows them. When the game earns a real analytics
budget, add Firebase or PostHog on top. Not before.

## Release health and source maps

- Set the release name from `package_info_plus` so Sentry groups by build.
- Upload debug symbols for Android (`flutter build appbundle --split-debug-info`
  plus `sentry-cli upload-dif`) and dSYMs for iOS. Without them, an obfuscated
  release stack trace is unreadable and the whole setup is decorative.
- Add the upload step to the release script, not to a developer's memory.

## What not to send

- No player identifiers, no device ids, no IP-derived location.
- Never a purchase receipt or a RevenueCat customer id.
- Filter out the noisy vendor exceptions you cannot fix: ad SDK load failures
  are already handled as outcomes and do not belong in the crash feed.
