# Follow-up prompt: monetization

Paste this when the game is playable and you are ready for phase 6. It assumes
`.env`, `Env`, and the Riverpod graph already exist.

---

Wire up monetization. Ads through AdMob, purchases through RevenueCat. Build it
in this order and stop after each numbered step so I can test.

## 1. Config

Add these keys to `.env.example` with placeholder values and a comment saying
where each one is found in its dashboard. Do not touch `.env`.

```
ADMOB_APP_ID_ANDROID=       ADMOB_APP_ID_IOS=
ADMOB_BANNER_ANDROID=       ADMOB_BANNER_IOS=
ADMOB_INTERSTITIAL_ANDROID= ADMOB_INTERSTITIAL_IOS=
ADMOB_REWARDED_ANDROID=     ADMOB_REWARDED_IOS=
ADS_TEST_MODE=true
ADS_TEST_DEVICE_IDS=
ADS_INTERSTITIAL_RUN_INTERVAL=3
REVENUECAT_API_KEY_ANDROID= REVENUECAT_API_KEY_IOS=
REVENUECAT_OFFERING_ID=default
RC_ENTITLEMENT_REMOVE_ADS=remove_ads
```

Add matching typed getters to `Env`, each with a fallback. `adsEnabled` is true
when any unit id is set; `purchasesEnabled` is true when a RevenueCat key is
set. Default the ad ids to Google's public test ids so a fresh clone shows test
ads.

Then wire the two native paths:

- `android/app/build.gradle.kts` parses `.env` at configuration time and injects
  `ADMOB_APP_ID_ANDROID` as a `manifestPlaceholder`, falling back to Google's
  test app id. An empty value crashes the Ads SDK at launch, so the fallback is
  load-bearing.
- `tool/sync_env.dart` generates `ios/Flutter/Env.xcconfig` with
  `ADMOB_APP_ID_IOS` for `GAD_APPLICATION_IDENTIFIER`. Gitignore the generated
  file, commit an `EnvDefaults.xcconfig` with the test id, and include the
  generated one after it. Add a `make sync-env` target.

## 2. Entitlements

`lib/services/iap/entitlements.dart`.

A `Perk` enum where each value maps to an entitlement identifier **read from
`.env`**, not hardcoded. Ship `removeAds` at minimum. Add
`Perk.fromEntitlementId(String)` returning null for anything this build does not
recognise, which happens whenever the dashboard is ahead of the shipped app.

An immutable `Entitlements` value class holding the owned set, with a working
`==` and `hashCode` so it can be pushed through a stream without listeners
having to diff.

## 3. Purchase service

`lib/services/iap/purchase_service.dart`.

- Degrades to a no-op when no key is configured. `isAvailable` tells the UI.
- `init()` never throws. A network failure leaves the session with no perks,
  which `restore()` can fix, rather than blocking startup.
- One `addCustomerInfoUpdateListener` covers purchases, restores, and
  server-side changes. Push results into a broadcast `Stream<Entitlements>`.
- `loadOffers()` returns a list of plain `StoreOffer` value types. The store
  screen must never see a `Package` or a `CustomerInfo`. Return an empty list
  rather than throwing when offerings are not set up.
- `purchase()` returns `PurchaseOutcome { success, cancelled, failed,
  unavailable }`. Detect cancellation specifically with
  `PurchasesErrorHelper.getErrorCode`. A cancelled purchase is not an error and
  gets no error UI.
- `restore()` re-syncs from the store and returns the entitlements found, or
  null if the restore itself failed.

## 4. Ad service

`lib/services/ads/ad_service.dart`.

- `init()`: on iOS, request App Tracking Transparency **before**
  `MobileAds.initialize()`, with a ~250ms delay first or the prompt is silently
  dropped. Apply `RequestConfiguration(testDeviceIds:)` when test mode is on.
  Wrap everything so a failure logs and continues rather than throwing.
- Banner: `AdSize.getLargeAnchoredAdaptiveBannerAdSize(width)`, not the legacy
  320x50. Returns null when suppressed. Caller disposes.
- Interstitial: preload, show between runs only, respect the run interval,
  never mid-run.
- Rewarded: preload at startup and again after every show. `showRewarded()`
  returns `RewardOutcome { earned, dismissed, notReady, failed }`. Grant the
  reward only on the SDK's `onUserEarnedReward` callback, never on dismissal.
- A public `adsRemoved` flag, fed from the entitlements stream. It suppresses
  banners and interstitials but **not** the rewarded ad, because taking away an
  opt-in bonus would punish the purchase.

## 5. Wiring

In `providers.dart`, expose `adServiceProvider`, `purchaseServiceProvider`, and
an `entitlementsProvider` that listens to the purchase stream and pushes
`adsRemoved` into the ad service.

In `main.dart`'s warm-up, resolve purchases **before** initialising ads, and
skip the ad SDK entirely when ads are removed. Run the whole warm-up unawaited
so it never gates the first frame, inside a try/catch that reports to Sentry and
continues.

## 6. UI

- A banner host widget that reserves the ad's height **before** it loads, so the
  layout does not jump under the player's thumb. Accidental taps are what
  invalid-traffic flags are made of.
- A store screen listing offers with title, description, and price string, an
  owned state per row, an unavailable empty state, and a **Restore purchases**
  button. Also put Restore in settings.
- A revive prompt on game over, shown only when `isRewardedReady`, with a
  countdown so it cannot sit there forever.

## 7. Docs

Write `docs/IAP_SETUP.md` covering the dashboard steps in order: create products
in both stores, create entitlements in RevenueCat with identifiers matching the
`RC_ENTITLEMENT_*` values, attach products to entitlements, build the `default`
offering, add the Play service account and App Store shared secret for receipt
validation. Include how to test: Play internal track with license testers,
StoreKit config file plus sandbox accounts on iOS.

Verify before handing back: the app still runs with `.env` deleted, `flutter
analyze` is clean, and a test rewarded ad grants the reward only when watched
through.
