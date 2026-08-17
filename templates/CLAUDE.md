# AI agent rules for this repo

Rules for any AI coding agent (Claude Code, Cursor, Codex) working on this
game. Follow them exactly. They override default agent behaviour.

Read this first, then `docs/ROADMAP.md` to see where work left off, then
`docs/AGENT_LOG.md` for the running history.

## What this is

<< One paragraph: the genre, the core loop, the platforms. >>

## Stack

- **Flutter 3.44+ / Dart 3** for Android and iOS, portrait only.
- **Flame** or **CustomPainter** for rendering. See `docs/ARCHITECTURE.md`.
- **Riverpod** (`flutter_riverpod`) for state. Hand-written providers, declared
  in `lib/core/di/providers.dart`. No code generation.
- **RevenueCat** (`purchases_flutter`) for in-app purchases.
- **AdMob** (`google_mobile_ads`) for ads.
- **Sentry** (`sentry_flutter`) for crash reporting, release builds only.

Bundle id / applicationId: `<< com.company.game >>` on both platforms.

## Secrets and config files

- **Never read or edit `.env`.** It is the developer's real, gitignored config
  and is theirs alone. Do not open it, cat it, grep it, print it, or change it,
  not even to check a value or add an empty placeholder line. Treat it as if it
  does not exist.
- **Only edit `.env.example`.** When code needs a new config value, add the key
  there with a placeholder (e.g. `SENTRY_DSN=`) so the developer knows what to
  set. The developer copies the real value into `.env` themselves.
- Never paste a real key, DSN, token, or password into any committed file.
- `__secrets/` holds build-time credentials. Never read from it, never list it.

## Architecture rules

- **The engine is pure Dart.** Nothing in `lib/game/engine/` may import
  `package:flutter`. Use `package:meta` if you need an annotation.
- **The view decides nothing.** Anything that decides whether a move is legal,
  costs a life, or ends the run goes through the controller or the engine.
  Renderers and widgets only draw and forward input.
- **Monetization stays behind the service interfaces.** Call sites depend on
  `AdService` and `PurchaseService` only, never on the plugins directly.
- **The app must run with no `.env`.** Every config getter has a fallback. A
  fresh clone gets test ads, no Sentry, an unavailable store, and a fully
  playable game.
- **Test the logic.** New rule behaviour gets a test in `test/` against the
  engine, not against the UI.

## Committing

- **Do not commit while iterating, tweaking, or doing small steps.** Make the
  change and stop so the developer can review and test it first.
- **Only commit when the developer explicitly asks** ("commit this", "commit
  and push"). When unsure, leave the change uncommitted.
- **Do not push to `master`** unless the developer asks.
- When you do commit, author as the developer only. No `Co-Authored-By` trailer,
  and never pass `-c user.email=` / `-c user.name=` overrides. Let git use the
  configured identity.
- Prefer explicit file paths over `git add -A`, so unrelated or secret files are
  never swept into a commit.

## Common commands

```bash
make            # list every target
make android    # boot the emulator if needed, then run
make ios        # boot the simulator if needed, then run
make test       # unit tests
make analyze    # static analysis, must be clean
make sync-env   # regenerate ios/Flutter/Env.xcconfig after an ADMOB_APP_ID change
```

## Writing style

- **Never use em dashes** in any file: code, comments, strings, docs, or commit
  messages. Use a period, a comma, or parentheses instead.
- Comments explain **why**, not what. Match the density of the surrounding file.
- Single quotes, trailing commas, `dart format` clean.
- User-facing copy is plain and warm. No exclamation-mark spam, no corporate
  cheer.

## When you finish a unit of work

1. Run `flutter analyze` and keep it clean.
2. Run `flutter test`.
3. Append a dated entry to `docs/AGENT_LOG.md` saying what changed and why.
4. Update `docs/ROADMAP.md` if a phase item moved.

That log is the project's memory across sessions.
