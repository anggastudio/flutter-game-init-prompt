# Architecture

The shape every game in this template family uses. Dependencies point inward:
the view knows about the rules, the rules know nothing about the view.

```
engine/          pure rules and data        (no Flutter import at all)
   ^
controller/      state, input, outcomes     (Riverpod notifier)
   ^
render/          Flame or CustomPainter     (view only, decides nothing)
   ^
features/        screens and HUD            (widgets, Riverpod consumers)

services/        monetization and platform seams, called from anywhere above
```

## Folder map

```
lib/
  main.dart                 Bootstrap only: Env, orientation, storage, Sentry, runApp.
  app.dart                  MaterialApp, theme, router.
  core/
    env/env.dart            Typed .env access. Every getter has a fallback.
    di/providers.dart       The entire Riverpod graph, in one readable file.
    theme/tokens.dart       Palette, Gap, Radii, Durations, Motion curves.
    theme/app_theme.dart    ThemeData assembly and the palette extension.
    router/app_router.dart  go_router config, when there are more than 3 screens.
    widgets/                Shared chrome: ad banner host, menu scaffold.
  game/
    engine/                 PURE DART. Rules, collision, scoring, win/lose.
    models/                 Immutable value types with copyWith, ==, hashCode.
    controller/             The only place player input meets the rules.
    render/                 Painter layers or Flame components. One per concern.
    config/                 Tuning constants: speeds, spawn rates, curves.
  features/
    home/                   One folder per screen: page.dart plus widgets/.
    game/
    store/
    settings/
  services/
    ads/                    AdService, RewardOutcome.
    iap/                    PurchaseService, Entitlements, Perk.
    storage/                StorageService plus the typed records it holds.
    audio/                  AudioService with a working mute.
  l10n/                     ARB files. English is the source of truth.
test/
  engine/                   Runs on the Dart VM. Milliseconds, not seconds.
```

## Why the engine is pure Dart

`lib/game/engine/` must compile and run with no Flutter binding. If you need an
annotation, import `package:meta`, never `package:flutter`.

The payoff is concrete. Rule tests run on the plain Dart VM in milliseconds with
no widget harness, no pumping, no golden files. The same engine can later back a
level editor, a solver, or a headless balance simulation. And the discipline
itself is the point: the moment a rule needs a `BuildContext`, it has stopped
being a rule and started being UI.

## Why the view decides nothing

The renderer receives state and forwards input. It never asks whether a move is
legal.

The data flow for one tap, end to end:

1. The player taps. A Flame component or a `GestureDetector` fires.
2. The view calls a single callback: `controller.tap(id)`.
3. The controller asks the engine whether that is legal.
4. The engine returns a new immutable state plus an outcome.
5. The controller emits the new state.
6. The screen listens and pushes it into the renderer, which animates the
   difference.

The renderer never branches on rules. That is what lets you swap sprites,
themes, and skins without any risk of changing what the game does.

## Choosing Flame or CustomPainter

Use **Flame** for sprites, a physics-ish update loop, particles, a camera, or
tilemaps. It brings a component tree, a game loop, collision helpers, and asset
management you would otherwise write yourself.

Use a plain **`CustomPainter`** driven by a `Ticker` for geometric boards: grid
puzzles, snake, 2048, match-3, card games. Draw calls are cheap, the binary is
smaller, and there is no second framework's lifecycle to reason about. Split the
painting into layers (board, entities, effects, overlays) so each stays short.

Either way, wrap animated subtrees in `RepaintBoundary` and never rebuild a
whole screen for a ticking counter. The floor is 60fps.

## State with Riverpod, no code generation

Hand-written providers, declared in `lib/core/di/providers.dart`. Read that file
before adding state. One file that shows the entire graph is worth more than
generated providers scattered across the tree.

Domain models are hand-written immutable classes with `copyWith`, `==`,
`hashCode`, and `toJson`/`fromJson` where needed. Do not introduce `freezed` or
`json_serializable` for a game this size. The generated code costs more build
time than the boilerplate costs to write, and it obscures the classes that
matter most.

Services that need async setup are constructed in `main.dart` and injected with
`overrideWithValue`, so the provider itself never has to model a loading state.

## Services are seams

Screens depend on `AdService` and `PurchaseService`. They never import
`google_mobile_ads` or `purchases_flutter`. The SDK types are flattened at the
service boundary into plain enums and value classes.

This is what makes it possible to stub monetization entirely in early phases,
swap ad networks later, and test screens without a network.

## Theme tokens, never literals

Colours come from `context.palette`, spacing from `Gap`, radii from `Radii`,
durations from `Durations`, curves from `Motion`. All declared in
`lib/core/theme/tokens.dart`. Brand colours never come from
`Theme.of(context).colorScheme`, which is for Material's own surfaces.

Every animation checks the platform reduce-motion setting and degrades to a
cross-fade when the OS asks it to.
