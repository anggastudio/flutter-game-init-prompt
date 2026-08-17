# Flutter Game Init Prompt

A template prompt for AI coding agents that sets up a **monetized Flutter mobile
game** from an empty directory: Android and iOS, AdMob, RevenueCat in-app
purchases, Sentry crash reporting, a signed release pipeline, and the folder
architecture that keeps the game rules testable.

Handing an agent "build me a Flutter game" gets you a counter app with a sprite
in it. Handing it [`INIT_PROMPT.md`](INIT_PROMPT.md) gets you a project with the
monetization plumbing, the config contract, and the release lane already in the
right shape, because every decision in it came out of games that actually
shipped.

## Use it

1. Create an empty directory and open your agent there (Claude Code, Cursor,
   Codex, whichever).
2. Open [`INIT_PROMPT.md`](INIT_PROMPT.md), fill in the `<<< >>>` placeholders
   at the top (game name, bundle id, core loop, art direction), and delete any
   section that does not apply.
3. Paste the whole thing.
4. The agent builds in nine phases, stopping after each so you can test.

The prompt is one message on purpose. It carries enough context that the agent
does not have to guess at architecture, config layout, or ad placement, and it
ends by asking the agent to restate your core loop so you catch a
misunderstanding before any code exists.

## What is in here

| Path | What it is |
| --- | --- |
| [`INIT_PROMPT.md`](INIT_PROMPT.md) | **The prompt.** Copy-paste this. |
| [`prompts/monetization.md`](prompts/monetization.md) | Follow-up prompt for the ads and IAP phase. |
| [`prompts/release-pipeline.md`](prompts/release-pipeline.md) | Follow-up prompt for signing, AAB, and store upload. |
| [`reference/architecture.md`](reference/architecture.md) | The layering, the folder map, why the engine is pure Dart. |
| [`reference/env-contract.md`](reference/env-contract.md) | What goes in `.env` versus `__secrets/`, and the three systems that read it. |
| [`reference/ads-admob.md`](reference/ads-admob.md) | Placement rules, rewarded ad handling, ATT, test ids. |
| [`reference/iap-revenuecat.md`](reference/iap-revenuecat.md) | Entitlements as behaviour, outcomes not exceptions, dashboard setup. |
| [`reference/monitoring-sentry.md`](reference/monitoring-sentry.md) | Config line by line, plus breadcrumbs as your first analytics. |
| [`reference/release.md`](reference/release.md) | Signing, the AAB lane, store assets, pre-submission checklist. |
| [`templates/`](templates/) | Working implementations of everything above. |

The reference docs exist so you can paste one as a follow-up when the agent
needs detail on a specific area, without bloating the initial prompt.

## Templates

Drop-in files, not pseudocode.

```
templates/
  lib/main.dart                          Bootstrap in the right order.
  lib/core/env/env.dart                  Typed .env access, every getter with a fallback.
  lib/services/ads/ad_service.dart       Banner, interstitial, rewarded, ATT.
  lib/services/iap/entitlements.dart     Perks as behaviour, keyed by entitlement id.
  lib/services/iap/purchase_service.dart RevenueCat wrapper, SDK types flattened.
  tool/sync_env.dart                     Generates ios/Flutter/Env.xcconfig from .env.
  android/build.gradle.kts.snippet       .env parsing plus release signing.
  dotfiles/env.example                   Every key, commented with where to find its value.
  dotfiles/gitignore                     Including the .env variants people forget.
  __secrets/README.md                    What credentials go where.
  CLAUDE.md                              Agent rules for the generated project.
  Makefile                               android, ios, test, analyze, aab, submit.
  pubspec.yaml                           The dependency set.
  analysis_options.yaml                  Lints that catch game-specific bugs.
```

## The decisions worth arguing about

Everything here is opinionated. The opinions that matter most:

**The game engine is pure Dart.** Nothing in `lib/game/engine/` imports
`package:flutter`. Rule tests then run on the plain Dart VM in milliseconds with
no widget harness. The discipline is the real payoff: the moment a rule needs a
`BuildContext`, it has stopped being a rule.

**The app must run with no `.env`.** A fresh clone gets Google's test ad ids, no
Sentry, a store that reports itself unavailable, and a fully playable game. That
property is what keeps the repo cloneable and stops a forgotten key from
becoming a production startup crash.

**Perks are behaviour, not product ids.** A `Perk` enum maps to entitlement
identifiers read from `.env`. Prices, titles, and which products exist all come
from the RevenueCat dashboard at runtime, so the catalogue can be repriced or
A/B tested without a build.

**Purchases resolve before ads initialise.** Entitlements decide whether ads
should load at all. Booting AdMob for someone who paid to remove ads is a wasted
request and a wasted second.

**Removing ads does not remove the rewarded ad.** It is opt-in and the player
actively wants it. Taking it away punishes the purchase.

**Ads never throw into gameplay.** Every failure resolves to an outcome enum the
caller can act on. A rewarded ad that did not load is a `notReady`, not an
exception on the game-over screen.

**Config lives in one file read by three systems.** Dart reads `.env` at
runtime, Gradle parses it at Android configuration time for the manifest, and
`tool/sync_env.dart` generates an xcconfig for iOS. One source of truth beats an
app id written down in three places that drift apart.

## Where this came from

Distilled from seven shipped and in-progress Flutter games (puzzle, arcade,
snake, platformer, shooter) built for Android and iOS with the same stack. The
patterns here are the ones that survived contact with the Play Console, App
Store review, and a real AdMob account.

## License

MIT. Use it, fork it, change the opinions you disagree with.
