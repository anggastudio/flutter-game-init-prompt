import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/di/providers.dart';
import 'core/env/env.dart';
import 'services/audio/audio_service.dart';
import 'services/storage/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuration first: everything below reads from it, including whether
  // Sentry should start at all.
  await Env.load();

  // Portrait only. The layout assumes a tall window; allowing rotation would
  // mean maintaining a second layout for an orientation nobody plays a
  // one-thumb game in.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Before any AudioPlayer is constructed, anywhere. A player created earlier
  // is born holding GAIN audio focus, and every sound effect then pauses the
  // music instead of mixing over it.
  await configureGlobalAudioContext();

  final storage = await StorageService.open();
  await storage.migrate();

  final container = ProviderContainer(
    overrides: [storageServiceProvider.overrideWithValue(storage)],
  );

  // Started in the background. None of these gate the first frame: a slow
  // network on a cold start must not hold the menu hostage.
  unawaited(_warmUpServices(container));

  if (Env.sentryEnabled) {
    await SentryFlutter.init(
      _configureSentry,
      appRunner: () => _runApp(container),
    );
  } else {
    // No DSN configured, which is the normal state for a fresh clone. Run
    // without error reporting rather than refusing to start.
    _runApp(container);
  }
}

void _runApp(ProviderContainer container) {
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GameApp(),
    ),
  );
}

void _configureSentry(SentryFlutterOptions options) {
  options
    ..dsn = Env.sentryDsn
    ..environment = Env.environment.name
    ..tracesSampleRate = Env.sentryTracesSampleRate
    ..replay.sessionSampleRate = 0
    ..replay.onErrorSampleRate = Env.sentryReplaySampleRate
    ..attachStacktrace = Env.sentryAttachStacktrace
    // Breadcrumbs from taps and navigation make a crash report legible
    // without needing the player to describe what they were doing.
    ..enableAutoNativeBreadcrumbs = true
    ..debug = !Env.environment.isProduction && kDebugMode
    // Nothing in this app collects personal data, and sending device
    // identifiers for a casual game would be a poor trade.
    ..sendDefaultPii = false
    // Debug-build noise is the developer's own doing and would drown the real
    // reports coming from released builds.
    ..beforeSend = (event, hint) => kDebugMode ? null : event;
}

/// Boots the audio, purchase and ad SDKs.
///
/// Ordered so purchases resolve first: entitlements decide whether ads should
/// be suppressed at all, and initialising the ad SDK for someone who paid to
/// remove ads is wasted work and a wasted request.
Future<void> _warmUpServices(ProviderContainer container) async {
  try {
    await container.read(audioServiceProvider).init();
    await container.read(purchaseServiceProvider).init();

    // Reading this wires the entitlements listener into the ad service.
    final entitlements = container.read(entitlementsProvider);

    if (!entitlements.adsRemoved) {
      await container.read(adServiceProvider).init();
    }
  } catch (error, stack) {
    debugPrint('Startup: service warm-up failed ($error)');
    if (Env.sentryEnabled) {
      await Sentry.captureException(error, stackTrace: stack);
    }
  }
}
