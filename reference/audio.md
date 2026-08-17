# Audio

Package: `audioplayers`. Wrapper: `lib/services/audio/audio_service.dart`.
Reference implementation:
[`templates/lib/services/audio/audio_service.dart`](../templates/lib/services/audio/audio_service.dart).

Audio is decoration. A device with a busy audio session, a revoked codec, or a
missing asset must still be playable. Every failure path in the service is
logged and swallowed, never thrown.

## The audio focus trap

This is the single bug that costs the most time, so it goes first.

**Set the global audio context in `main()` before any `AudioPlayer` is
constructed.** A player created before the context is set is born holding
`GAIN` audio focus. The symptom is bizarre and hard to trace: the background
music plays fine until the first sound effect fires, then the music pauses,
resumes, and ducks again on every subsequent effect.

```dart
// In main(), before runApp and before any AudioPlayer exists.
await AudioPlayer.global.setAudioContext(
  AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      // The important line. Every player born after this asks for no focus,
      // so effects mix over the music instead of interrupting it.
      audioFocus: AndroidAudioFocus.none,
    ),
    // `ambient` mixes within the app and respects the hardware silent switch.
    // Note that `mixWithOthers` is not a valid option with this category.
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  ),
);
```

Wrap it in a try/catch. Failing here is non-fatal: audio still plays, effects
may just briefly duck the music.

## Respecting the player's own music

A casual game is played on a bus with someone's podcast already running.
Interrupting it is the fastest way to be closed and never reopened.

- **iOS**: `AVAudioSessionCategory.ambient`. It mixes with other apps and obeys
  the ringer switch, which is what a player who muted their phone expects.
- **Android**: `AndroidAudioFocus.none` for a game that mixes, or
  `gainTransientMayDuck` if you genuinely need the game to be foregrounded.
  Never `gain`, which stops the other app entirely.

If your game has its own background music, default it to **off** or duck it hard
when other audio is already playing. Sound effects are welcome over a podcast.
A second music track is not.

## Two players, two jobs

**Sound effects** need a small **pool** of preloaded players, round-robined.
Games routinely overlap sounds: a coin collected on the same tick a power-up
expires. A single player cuts the first sound off mid-note. Four voices covers
the busiest moment in a casual game without letting a runaway source allocate
without bound.

Preload each effect with `setSource` at init and `ReleaseMode.stop`. Retriggering
is then `seek(Duration.zero)` plus `resume()`, with no reload and no per-play
focus churn. That difference is audible: a reload adds tens of milliseconds and
makes a tap feel unresponsive.

**Music** is one dedicated player with `ReleaseMode.loop`. Start and stop it
from the settings toggle directly, not from a rebuild.

## Map events, not asset paths

Callers should never write a filename. Define the vocabulary as an enum and let
the service translate a game event into the sound plus the haptic that goes with
it:

```dart
enum Sfx {
  tap('tap.wav'),
  collect('collect.wav'),
  lifeLost('life_lost.wav'),
  gameOver('game_over.wav');
  const Sfx(this.asset);
  final String asset;
  String get path => 'audio/$asset';
}

void handleGameEvent(GameEvent event) {
  switch (event) {
    case GameEvent.collect:
      play(Sfx.collect);
      _haptic(HapticStrength.light);
    // ...
  }
}
```

One place decides which cue goes with which event. That is also where you notice
you are firing two sounds on the same frame, which just muddies both. When one
cue already covers the moment, play the haptic alone.

## Mute has to work on the first screen

Sound and music toggles are separate, persisted through `shared_preferences`,
and reachable from the first screen. Not buried two menus deep.

Read the toggle at **play time**, not at init, so flipping it takes effect
instantly. The service holds a settings object that the settings layer refreshes
with `updateSettings`.

Haptics get their own toggle. Some players want silent feedback, some find
vibration unpleasant, and on Android the two are genuinely independent
hardware paths.

## Haptics

`HapticFeedback` from `flutter/services` is enough on iOS, where the Taptic
engine is good. On Android it is too faint to feel through a case, so a game
that leans on haptics wants the `vibration` package with explicit amplitude
control. Check `hasVibrator()` and `hasAmplitudeControl()` once at init and
cache the answers.

Map three strengths and no more: light for routine feedback, medium for a
reward, heavy for a loss. More granularity than that is not perceivable.

## Generating sound effects

For a casual game, six short beeps do not justify a sample library or a
licensing search. Synthesise them with a build-time script and commit the
script, not just the WAVs:

```
tool/generate_sfx.py    # Python stdlib only: math, struct, wave
assets/audio/*.wav      # generated output, committed
```

Keeping it a script means the sounds stay tweakable. Change a frequency,
re-run, hear the difference. Committed binaries are opaque and nobody ever
adjusts them. See
[`templates/tool/generate_sfx.py`](../templates/tool/generate_sfx.py) for a
working synth covering sine, square, triangle, saw, and filtered noise bursts
with an exponential decay envelope.

This also sidesteps the whole licensing question for effects. Music is
different, see below.

## Formats and size

| Use | Format | Why |
| --- | --- | --- |
| Short effects | 16-bit mono WAV, 22.05kHz | No decode latency. A 200ms effect is ~9KB. |
| Music loop | `.m4a` (AAC) or `.ogg` | A 2 minute WAV loop is 20MB. AAC is ~2MB. |

Mono is correct for effects in a portrait phone game. Stereo doubles the size
for a stage nobody perceives through a phone speaker.

Watch the total. Audio is usually the second largest thing in a casual game
binary after images, and install size measurably affects conversion.

## Licensing

For music, the only safe sources are: something you commissioned, something you
made, CC0, or a license you actually paid for and kept the receipt of. "Free
for non-commercial use" does not cover an ad-supported game, which is
commercial. A royalty-free track still requires you to keep proof of purchase,
because a takedown gives you days to produce it.

Record what you used and where it came from in `assets/audio/README.md`. Future
you will not remember, and a content ID claim on a gameplay trailer is a bad
time to start looking.

## Checklist

- [ ] Global audio context set in `main()` before any player is constructed.
- [ ] Music keeps playing when a sound effect fires.
- [ ] The player's own background audio is not interrupted.
- [ ] The iOS silent switch mutes the game.
- [ ] Sound, music, and haptics toggles are separate, persisted, and reachable
      from the first screen.
- [ ] Toggling mute takes effect immediately, not on next launch.
- [ ] A missing audio asset logs and continues rather than crashing.
- [ ] Audio pauses on app backgrounding and resumes on return.
- [ ] Music licensing recorded in `assets/audio/README.md`.
