import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/game_settings.dart';

/// Every sound the game can make, mapped to its asset.
///
/// Callers name a cue, never a filename, so renaming an asset touches one line.
enum Sfx {
  tap('tap.wav'),
  collect('collect.wav'),
  powerUp('power_up.wav'),
  lifeLost('life_lost.wav'),
  gameOver('game_over.wav'),
  win('win.wav');

  const Sfx(this.asset);

  final String asset;

  String get path => 'audio/$asset';
}

enum HapticStrength { light, medium, heavy }

/// Sets the process-wide audio context.
///
/// Call this from `main()` BEFORE any [AudioPlayer] is constructed. A player
/// created earlier is born holding GAIN audio focus, and the symptom is
/// baffling: the music plays until the first sound effect, then pauses and
/// resumes on every effect after it.
///
/// Non-fatal on failure. Audio still plays; effects may briefly duck the music.
Future<void> configureGlobalAudioContext() async {
  try {
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          // Ask for no focus at all, so game audio mixes over whatever the
          // player already had running instead of stopping it.
          audioFocus: AndroidAudioFocus.none,
        ),
        // `ambient` mixes within the app and respects the hardware silent
        // switch, which is what someone who muted their phone expects.
        // `mixWithOthers` is not a valid option with this category.
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ),
    );
  } catch (error) {
    debugPrint('Audio: could not set global context ($error)');
  }
}

/// Plays sound effects and the music loop, and fires haptics.
///
/// Holds a small pool of players rather than one, because games routinely
/// overlap sounds: a coin collected on the same tick a power-up expires. A
/// single player would cut the first sound off mid-note.
///
/// Every failure path is swallowed. Audio is decoration; a device with a busy
/// audio session or a revoked codec should still be playable.
class AudioService {
  AudioService({GameSettings settings = const GameSettings()})
    : _settings = settings;

  /// Enough voices for the busiest moment in a casual game, without letting a
  /// runaway sound source allocate without bound.
  static const int _poolSize = 4;

  static const String _musicAsset = 'audio/music.m4a';

  final List<AudioPlayer> _pool = [];
  final Map<Sfx, AudioPlayer> _preloaded = {};
  AudioPlayer? _musicPlayer;

  int _nextVoice = 0;
  bool _ready = false;

  GameSettings _settings;

  /// Keeps volumes and mute toggles in step with Settings.
  ///
  /// Read at play time rather than at init, so flipping a toggle takes effect
  /// on the very next sound instead of on next launch.
  void updateSettings(GameSettings settings) {
    final wasMusicOn = _settings.musicEnabled;
    _settings = settings;

    if (settings.musicEnabled && !wasMusicOn) {
      unawaited(startMusic());
    } else if (!settings.musicEnabled && wasMusicOn) {
      unawaited(stopMusic());
    }
  }

  /// Warms up the player pool and preloads every effect. Safe to call twice.
  ///
  /// Assumes [configureGlobalAudioContext] already ran.
  Future<void> init() async {
    if (_ready) return;

    try {
      for (var i = 0; i < _poolSize; i++) {
        final player = AudioPlayer(playerId: 'sfx_voice_$i');
        await player.setReleaseMode(ReleaseMode.stop);
        _pool.add(player);
      }

      // Preloading turns a retrigger into seek(0) plus resume, with no reload
      // and no per-play focus churn. The difference is audible: a reload adds
      // tens of milliseconds and makes a tap feel unresponsive.
      for (final sfx in Sfx.values) {
        try {
          final player = AudioPlayer(playerId: 'sfx_${sfx.name}');
          await player.setReleaseMode(ReleaseMode.stop);
          await player.setSource(AssetSource(sfx.path));
          _preloaded[sfx] = player;
        } catch (error) {
          // A missing asset costs that one cue, not the whole service.
          debugPrint('AudioService: ${sfx.name} preload failed ($error)');
        }
      }

      final music = AudioPlayer(playerId: 'music');
      await music.setReleaseMode(ReleaseMode.loop);
      _musicPlayer = music;

      _ready = true;
    } catch (error) {
      debugPrint('AudioService: init failed ($error), running silent');
    }
  }

  // -----------------------------------------------------------------------
  // Sound effects
  // -----------------------------------------------------------------------

  /// Plays a one-shot. Returns immediately; the sound finishes on its own.
  void play(Sfx sfx) {
    if (!_settings.soundEnabled || !_ready) return;

    final volume = _settings.soundVolume.clamp(0.0, 1.0);

    // The preloaded player retriggers fastest, so use it when the same cue is
    // not already mid-flight. Otherwise fall back to a pool voice so the two
    // can overlap.
    final preloaded = _preloaded[sfx];
    if (preloaded != null) {
      unawaited(
        preloaded
            .seek(Duration.zero)
            .then((_) => preloaded.setVolume(volume))
            .then((_) => preloaded.resume())
            .catchError((Object error) {
              debugPrint('AudioService: ${sfx.name} failed ($error)');
            }),
      );
      return;
    }

    if (_pool.isEmpty) return;

    // Round-robin so a new sound never cuts off the one just started.
    final player = _pool[_nextVoice];
    _nextVoice = (_nextVoice + 1) % _pool.length;

    unawaited(
      player.play(AssetSource(sfx.path), volume: volume).catchError((
        Object error,
      ) {
        debugPrint('AudioService: could not play ${sfx.name} ($error)');
      }),
    );
  }

  // -----------------------------------------------------------------------
  // Music
  // -----------------------------------------------------------------------

  Future<void> startMusic() async {
    if (!_settings.musicEnabled) return;

    final music = _musicPlayer;
    if (music == null) return;

    try {
      await music.stop();
      await music.setVolume(_settings.musicVolume.clamp(0.0, 1.0));
      await music.play(AssetSource(_musicAsset));
    } catch (error) {
      debugPrint('AudioService: music failed, add assets/$_musicAsset');
    }
  }

  Future<void> stopMusic() async {
    try {
      await _musicPlayer?.stop();
    } catch (_) {
      // Stopping a player that never started is not worth reporting.
    }
  }

  /// Call from an app lifecycle listener. Music that keeps playing after the
  /// player switched apps is a uninstall waiting to happen.
  Future<void> pauseForBackground() async {
    try {
      await _musicPlayer?.pause();
    } catch (_) {}
  }

  Future<void> resumeFromBackground() async {
    if (!_settings.musicEnabled) return;
    try {
      await _musicPlayer?.resume();
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // Haptics
  // -----------------------------------------------------------------------

  /// Translates an engine event into sound and haptics, so callers do not have
  /// to remember which cue goes with which event.
  ///
  /// Replace the cases with this game's own event enum.
  void handleGameEvent(GameEvent event) {
    switch (event) {
      case GameEvent.collect:
        play(Sfx.collect);
        haptic(HapticStrength.light);
      case GameEvent.powerUp:
        play(Sfx.powerUp);
        haptic(HapticStrength.medium);
      case GameEvent.lifeLost:
        play(Sfx.lifeLost);
        haptic(HapticStrength.heavy);
      case GameEvent.gameOver:
        play(Sfx.gameOver);
        haptic(HapticStrength.heavy);
      case GameEvent.win:
        play(Sfx.win);
        haptic(HapticStrength.heavy);
      case GameEvent.blocked:
        // The life-lost cue already covers the moment; a second sound on the
        // same frame just muddies it.
        haptic(HapticStrength.light);
    }
  }

  /// Haptics have their own toggle. Some players want silent feedback, some
  /// find vibration unpleasant, and on Android the two are independent
  /// hardware paths.
  void haptic(HapticStrength strength) {
    if (!_settings.hapticsEnabled) return;

    switch (strength) {
      case HapticStrength.light:
        unawaited(HapticFeedback.selectionClick());
      case HapticStrength.medium:
        unawaited(HapticFeedback.lightImpact());
      case HapticStrength.heavy:
        unawaited(HapticFeedback.mediumImpact());
    }
  }

  Future<void> dispose() async {
    for (final player in [..._pool, ..._preloaded.values]) {
      await player.dispose();
    }
    await _musicPlayer?.dispose();
    _pool.clear();
    _preloaded.clear();
    _musicPlayer = null;
    _ready = false;
  }
}

/// Placeholder. Replace with this game's own event enum, emitted by the engine.
enum GameEvent { collect, powerUp, lifeLost, gameOver, win, blocked }
