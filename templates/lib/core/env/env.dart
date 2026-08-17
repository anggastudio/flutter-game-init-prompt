import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Which build this is, for Sentry tagging and debug affordances.
enum AppEnvironment {
  dev,
  staging,
  prod;

  static AppEnvironment parse(String? raw) => switch (raw?.toLowerCase()) {
    'prod' || 'production' => AppEnvironment.prod,
    'staging' || 'stage' => AppEnvironment.staging,
    _ => AppEnvironment.dev,
  };

  bool get isProduction => this == AppEnvironment.prod;
}

/// Typed access to everything in `.env`.
///
/// Call [load] once before `runApp`. Every getter has a safe default, so a
/// missing or malformed `.env` degrades the app rather than crashing it: no
/// Sentry DSN simply means no error reporting, no RevenueCat key means the
/// store shows as unavailable. That matters because `.env` is a build-time
/// asset a teammate can easily forget to create.
///
/// See `.env.example` for what each key means and where to find its value.
abstract final class Env {
  static bool _loaded = false;

  /// Reads `.env` from the bundled assets. Safe to call more than once.
  ///
  /// Returns false when the file was missing, which the caller may want to
  /// surface in debug builds.
  static Future<bool> load() async {
    if (_loaded) return true;
    try {
      await dotenv.load();
      _loaded = true;
      return true;
    } catch (error) {
      // A missing .env is a setup mistake, not a crash. Everything below
      // falls back to a default and the app still runs.
      debugPrint(
        'Env: could not load .env ($error). '
        'Copy .env.example to .env. Running with defaults.',
      );
      return false;
    }
  }

  static String _string(String key, [String fallback = '']) {
    if (!_loaded) return fallback;
    final value = dotenv.env[key];
    if (value == null || value.trim().isEmpty) return fallback;
    return value.trim();
  }

  static bool _bool(String key, {required bool fallback}) {
    final raw = _string(key).toLowerCase();
    if (raw.isEmpty) return fallback;
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  static double _double(String key, double fallback) =>
      double.tryParse(_string(key)) ?? fallback;

  static int _int(String key, int fallback) =>
      int.tryParse(_string(key)) ?? fallback;

  /// Picks the Android or iOS variant of a key. Anything that is not a phone
  /// (a widget test, for instance) gets the Android value, which keeps tests
  /// deterministic.
  static String _perPlatform(String androidKey, String iosKey) {
    if (kIsWeb) return _string(androidKey);
    return Platform.isIOS ? _string(iosKey) : _string(androidKey);
  }

  // ---------------------------------------------------------------------
  // App
  // ---------------------------------------------------------------------

  static AppEnvironment get environment =>
      AppEnvironment.parse(_string('APP_ENV', 'dev'));

  // ---------------------------------------------------------------------
  // Sentry
  // ---------------------------------------------------------------------

  static String get sentryDsn => _string('SENTRY_DSN');

  /// Sentry is only started when a DSN is configured.
  static bool get sentryEnabled => sentryDsn.isNotEmpty;

  static double get sentryTracesSampleRate =>
      _double('SENTRY_TRACES_SAMPLE_RATE', 0.2).clamp(0.0, 1.0);

  static double get sentryReplaySampleRate =>
      _double('SENTRY_REPLAY_SAMPLE_RATE', 0.0).clamp(0.0, 1.0);

  static bool get sentryAttachStacktrace =>
      _bool('SENTRY_ATTACH_STACKTRACE', fallback: true);

  // ---------------------------------------------------------------------
  // AdMob
  //
  // App ids are not read here. They have to be in the native manifest before
  // any Dart runs, so Android parses .env in build.gradle.kts and iOS reads
  // the xcconfig written by tool/sync_env.dart.
  // ---------------------------------------------------------------------

  static String get admobBannerUnitId =>
      _perPlatform('ADMOB_BANNER_ANDROID', 'ADMOB_BANNER_IOS');

  static String get admobInterstitialUnitId =>
      _perPlatform('ADMOB_INTERSTITIAL_ANDROID', 'ADMOB_INTERSTITIAL_IOS');

  static String get admobRewardedUnitId =>
      _perPlatform('ADMOB_REWARDED_ANDROID', 'ADMOB_REWARDED_IOS');

  /// Ads are on as soon as any unit id is configured. With none, every method
  /// on the ad service becomes a no-op instead of a stream of load failures.
  static bool get adsEnabled =>
      admobBannerUnitId.isNotEmpty ||
      admobInterstitialUnitId.isNotEmpty ||
      admobRewardedUnitId.isNotEmpty;

  /// Forces the SDK to serve test ads only. Must be false in a release build
  /// or the app earns no revenue; must be true in development or the account
  /// risks being flagged for invalid traffic.
  static bool get adsTestMode => _bool('ADS_TEST_MODE', fallback: true);

  static List<String> get adsTestDeviceIds => _string('ADS_TEST_DEVICE_IDS')
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);

  /// Seconds to wait before a banner may appear on a fresh install, so a
  /// first-time player is not hit with an ad immediately.
  static int get adsBannerDelaySeconds => _int('ADS_BANNER_DELAY_SECONDS', 0);

  /// Minimum runs between interstitials. Zero disables interstitials.
  static int get adsInterstitialRunInterval =>
      _int('ADS_INTERSTITIAL_RUN_INTERVAL', 3);

  // ---------------------------------------------------------------------
  // RevenueCat
  // ---------------------------------------------------------------------

  static String get revenueCatApiKey =>
      _perPlatform('REVENUECAT_API_KEY_ANDROID', 'REVENUECAT_API_KEY_IOS');

  static bool get purchasesEnabled => revenueCatApiKey.isNotEmpty;

  /// Empty means "whichever offering is current in the dashboard", which is
  /// what you want unless you are A/B testing.
  static String get revenueCatOfferingId {
    final id = _string('REVENUECAT_OFFERING_ID', 'default');
    return id == 'default' ? '' : id;
  }

  // Entitlement identifiers, as configured in the RevenueCat dashboard. The
  // app looks these up by name, so they must match the dashboard exactly.
  static String get entitlementRemoveAds =>
      _string('RC_ENTITLEMENT_REMOVE_ADS', 'remove_ads');

  static String get entitlementSkins => _string('RC_ENTITLEMENT_SKINS', 'skins');

  // ---------------------------------------------------------------------
  // Gameplay tuning
  //
  // Knobs, not secrets. They live in .env so the economy can be retuned
  // without shipping a new build during a test cycle.
  // ---------------------------------------------------------------------

  static int get maxAdRevivesPerRun => _int('MAX_AD_REVIVES_PER_RUN', 1);

  static int get reviveInvincibilitySeconds =>
      _int('REVIVE_INVINCIBILITY_SECONDS', 3);
}
