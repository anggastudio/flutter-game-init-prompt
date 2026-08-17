# Ads: AdMob

Package: `google_mobile_ads`. Wrapper: `lib/services/ads/ad_service.dart`.
Reference implementation: [`templates/lib/services/ads/ad_service.dart`](../templates/lib/services/ads/ad_service.dart).

## Two rules shape the service

1. **Ads are optional.** With no unit ids configured, or with the remove-ads
   entitlement owned, every method is a cheap no-op rather than a stream of
   load failures.
2. **Ads never block gameplay.** Loads happen ahead of time and every failure
   resolves to an outcome the caller can act on, never an exception thrown into
   game code.

## Placement

| Format | Where | Rule |
| --- | --- | --- |
| Anchored adaptive banner | Menu, level select, settings | Never over live gameplay. Never over a button. |
| Rewarded | Revive, extra hint, double coins | The one ad the player chooses. |
| Interstitial | Between runs only | Floor of 3 runs or 90 seconds. Skip in the first session. |
| App open | Do not ship it | It is the fastest way to a one-star review. |

Use `AdSize.getLargeAnchoredAdaptiveBannerAdSize(width)` rather than the legacy
320x50. It asks AdMob for the height that suits the device. In a portrait-locked
game the orientation-agnostic variant is the right one.

Reserve the banner's height in the layout **before** it loads, so the UI does
not jump when the ad arrives. A layout shift under the player's thumb causes
accidental taps, and accidental taps are what invalid-traffic flags are made of.

## Rewarded ads

Preload at startup and again immediately after every show. By the time the
player dies and is offered a revive, the ad is already in the chamber. A revive
prompt that spins for five seconds is a prompt nobody accepts.

Grant the reward **only** on the SDK's `onUserEarnedReward` callback. Never on
dismissal. Closing an ad early correctly earns nothing.

Model the ending as an enum, not a bool:

```dart
enum RewardOutcome { earned, dismissed, notReady, failed }
```

`dismissed` is a normal player choice and gets no error UI. `notReady` should
kick off a fresh preload so a second attempt has a chance of working.

## Removing ads

The `remove_ads` entitlement suppresses **banners and interstitials only**. The
rewarded revive stays available, because taking away an opt-in bonus the player
actively wants would punish the purchase.

The ad service holds a plain `adsRemoved` flag fed from the entitlements stream.
That keeps the dependency one-directional: purchases know nothing about ads.

## iOS App Tracking Transparency

Request tracking authorization **before** `MobileAds.instance.initialize()`.
Asking afterwards leaves the session stuck on non-personalised ads for its whole
lifetime.

Wait roughly 250ms after the app becomes active before prompting. iOS silently
drops the request if it arrives while the app is still becoming active, which
presents as a permission dialog that simply never appears.

Declining, or an older iOS with no ATT at all, is fine. Ads run
non-personalised.

`Info.plist` needs `NSUserTrackingUsageDescription` with a plain sentence about
showing more relevant ads.

## Android manifest

The app id is a manifest entry, injected from `.env` at Gradle configuration
time:

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="${admobAppId}" />
```

An empty value here crashes the app at launch. See the
[env contract](env-contract.md) for the Gradle side and its test-id fallback.

## Google's public test ids

Safe to ship in a debug build. They serve real-looking test ads.

| Unit | Android | iOS |
| --- | --- | --- |
| App id | `ca-app-pub-3940256099942544~3347511713` | `ca-app-pub-3940256099942544~1458002511` |
| Banner | `ca-app-pub-3940256099942544/6300978111` | `ca-app-pub-3940256099942544/2934735716` |
| Interstitial | `ca-app-pub-3940256099942544/1033173712` | `ca-app-pub-3940256099942544/4411468910` |
| Rewarded | `ca-app-pub-3940256099942544/5224354917` | `ca-app-pub-3940256099942544/1712485313` |

Note the punctuation: app ids use `~`, ad units use `/`. Swapping them is a
common and confusing mistake, because the SDK's error message does not say so.

## Before release

- [ ] `ADS_TEST_MODE=false` and real unit ids in the production `.env`.
- [ ] Real app ids reach both the manifest and `Info.plist`. Check the built
      artifacts, not just the source.
- [ ] `app-ads.txt` published on the developer website listed in the store, and
      the URL matches the store listing exactly.
- [ ] AdMob account linked to the Play Console and to App Store Connect.
- [ ] The Play Data safety form declares advertising id usage, and the manifest
      keeps the `AD_ID` permission (Android 13+ requires it to be declared).
- [ ] A `make shots` run with ads disabled, for clean store screenshots.
