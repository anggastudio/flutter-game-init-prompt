import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/env/env.dart';

/// How showing a rewarded ad ended.
enum RewardOutcome {
  /// The player watched it through and earned the reward.
  earned,

  /// Closed early, so no reward. Not an error.
  dismissed,

  /// Nothing was loaded in time.
  notReady,

  /// The SDK refused to show it.
  failed,
}

/// Owns the AdMob SDK: the anchored banner, the between-runs interstitial, and
/// the rewarded revive.
///
/// Two rules shape this class:
///
/// 1. Ads are optional. With no unit IDs configured, or with the remove-ads
///    entitlement owned, every method here becomes a cheap no-op rather than a
///    stream of load failures.
/// 2. Ads never block gameplay. Loads happen ahead of time and every failure
///    resolves to an outcome the caller can act on, never an exception.
class AdService {
  AdService();

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;
  bool _rewardedLoading = false;
  bool _initialised = false;
  int _runsSinceInterstitial = 0;

  /// Set from the entitlements stream. Suppresses banners and interstitials;
  /// the rewarded ad stays available because it is opt-in and the player may
  /// still want it.
  bool adsRemoved = false;

  bool get isEnabled => _initialised && Env.adsEnabled;

  bool get shouldShowBanner => isEnabled && !adsRemoved;

  bool get isRewardedReady => _rewardedAd != null;

  String get bannerUnitId => Env.admobBannerUnitId;

  /// Initialises the SDK and preloads the first rewarded ad.
  ///
  /// On iOS this first asks for tracking permission. Requesting before the
  /// SDK starts is what lets AdMob serve personalised ads when the player
  /// agrees; asking afterwards means the session is stuck non-personalised.
  Future<void> init() async {
    if (_initialised || !Env.adsEnabled) return;

    try {
      if (!kIsWeb && Platform.isIOS) {
        await _requestTrackingAuthorization();
      }

      await MobileAds.instance.initialize();

      if (Env.adsTestMode || Env.adsTestDeviceIds.isNotEmpty) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: Env.adsTestDeviceIds),
        );
      }

      _initialised = true;
      unawaited(preloadRewarded());
      unawaited(_preloadInterstitial());
    } catch (error) {
      debugPrint('AdService: init failed ($error), continuing without ads');
    }
  }

  /// Shows the iOS App Tracking Transparency prompt once.
  ///
  /// A short delay first: iOS silently drops the prompt if it is requested
  /// while the app is still becoming active, which shows up as a permission
  /// dialog that never appears.
  Future<void> _requestTrackingAuthorization() async {
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status != TrackingStatus.notDetermined) return;

      await Future<void>.delayed(const Duration(milliseconds: 250));
      await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (error) {
      // Declining, or an older iOS with no ATT at all, is fine. Ads simply
      // run non-personalised.
      debugPrint('AdService: tracking prompt skipped ($error)');
    }
  }

  // -----------------------------------------------------------------------
  // Banner
  // -----------------------------------------------------------------------

  /// Builds an anchored adaptive banner for the given width.
  ///
  /// Returns null when banners are suppressed. The caller is responsible for
  /// disposing the returned ad.
  Future<BannerAd?> createBanner({
    required int width,
    required void Function() onLoaded,
  }) async {
    if (!shouldShowBanner || bannerUnitId.isEmpty) return null;

    try {
      // Adaptive sizing asks AdMob for the height that suits this device,
      // rather than assuming the legacy 320x50. The app is portrait-locked, so
      // the orientation-agnostic variant is the right one here.
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      if (size == null) return null;

      final banner = BannerAd(
        adUnitId: bannerUnitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) => onLoaded(),
          onAdFailedToLoad: (ad, error) {
            debugPrint(
              'AdService: banner failed (${error.code}) ${error.message}',
            );
            ad.dispose();
          },
        ),
      );

      await banner.load();
      return banner;
    } catch (error) {
      debugPrint('AdService: banner error ($error)');
      return null;
    }
  }

  // -----------------------------------------------------------------------
  // Interstitial
  // -----------------------------------------------------------------------

  Future<void> _preloadInterstitial() async {
    if (!isEnabled || adsRemoved) return;
    if (Env.admobInterstitialUnitId.isEmpty) return;
    if (Env.adsInterstitialRunInterval <= 0) return;
    if (_interstitialAd != null) return;

    try {
      await InterstitialAd.load(
        adUnitId: Env.admobInterstitialUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _interstitialAd = ad,
          onAdFailedToLoad: (error) {
            debugPrint('AdService: interstitial failed (${error.code})');
            _interstitialAd = null;
          },
        ),
      );
    } catch (error) {
      debugPrint('AdService: interstitial load error ($error)');
    }
  }

  /// Shows an interstitial if enough runs have passed since the last one.
  ///
  /// Call this between runs only, never mid-run. Returns whether an ad was
  /// actually shown, which the caller can use to skip its own transition.
  Future<bool> maybeShowInterstitial() async {
    if (!isEnabled || adsRemoved) return false;

    final interval = Env.adsInterstitialRunInterval;
    if (interval <= 0) return false;

    _runsSinceInterstitial++;
    if (_runsSinceInterstitial < interval) return false;

    final ad = _interstitialAd;
    if (ad == null) {
      unawaited(_preloadInterstitial());
      return false;
    }

    _interstitialAd = null;
    _runsSinceInterstitial = 0;

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        unawaited(_preloadInterstitial());
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        unawaited(_preloadInterstitial());
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      await ad.show();
    } catch (error) {
      debugPrint('AdService: interstitial show threw ($error)');
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future;
  }

  // -----------------------------------------------------------------------
  // Rewarded
  // -----------------------------------------------------------------------

  /// Loads a rewarded ad into the chamber.
  ///
  /// Called at startup and again after each show, so that by the time the
  /// player dies and is offered a revive, the ad is already there. A revive
  /// prompt that spins for five seconds is a prompt nobody accepts.
  Future<void> preloadRewarded() async {
    if (!isEnabled || Env.admobRewardedUnitId.isEmpty) return;
    if (_rewardedAd != null || _rewardedLoading) return;

    _rewardedLoading = true;
    final completer = Completer<void>();

    try {
      await RewardedAd.load(
        adUnitId: Env.admobRewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedAd = ad;
            _rewardedLoading = false;
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              'AdService: rewarded failed (${error.code}) ${error.message}',
            );
            _rewardedAd = null;
            _rewardedLoading = false;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );
      await completer.future;
    } catch (error) {
      debugPrint('AdService: rewarded load error ($error)');
      _rewardedLoading = false;
    }
  }

  /// Shows the rewarded ad and resolves once the player is back in the app.
  ///
  /// The reward is only granted on the SDK's own reward callback, never on
  /// dismissal, so closing the ad early correctly earns nothing.
  Future<RewardOutcome> showRewarded() async {
    final ad = _rewardedAd;
    if (ad == null) {
      // Start fetching one so a second attempt has a chance of working.
      unawaited(preloadRewarded());
      return RewardOutcome.notReady;
    }

    _rewardedAd = null;
    final completer = Completer<RewardOutcome>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        unawaited(preloadRewarded());
        if (!completer.isCompleted) {
          completer.complete(
            earned ? RewardOutcome.earned : RewardOutcome.dismissed,
          );
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdService: rewarded show failed (${error.message})');
        ad.dispose();
        unawaited(preloadRewarded());
        if (!completer.isCompleted) completer.complete(RewardOutcome.failed);
      },
    );

    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (error) {
      debugPrint('AdService: rewarded show threw ($error)');
      if (!completer.isCompleted) completer.complete(RewardOutcome.failed);
    }

    return completer.future;
  }

  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
