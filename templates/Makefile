# Developer shortcuts. Run `make` for the list.

.DEFAULT_GOAL := help
.PHONY: help android ios run shots devices get clean test analyze format \
        icons splash sync-env android\:aab android\:aab\:submit

help: ## Show this help
	@grep -E '^[a-zA-Z_.-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo "  \033[36mandroid:aab\033[0m          Build a signed release App Bundle into dist/"
	@echo "  \033[36mandroid:aab:submit\033[0m   Bump build number, build, upload to Play internal test"
	@echo "                       Add release notes with: NOTES=\"what changed\""

android: ## Boot the Android emulator if needed, then run
	@bash scripts/run-android.sh $(ARGS)

ios: ## Boot the iOS simulator if needed, then run
	@bash scripts/run-ios.sh $(ARGS)

run: ## Run on whatever device flutter picks
	flutter run $(ARGS)

shots: ## Run with ads disabled, for clean store screenshots
	@bash scripts/run-android.sh --dart-define=DISABLE_ADS=true $(ARGS)

devices: ## List connected devices and emulators
	flutter devices

get: ## Fetch packages
	flutter pub get

test: ## Run unit tests
	flutter test

analyze: ## Static analysis. Must be clean before any handoff.
	flutter analyze lib test

format: ## Format Dart sources
	dart format lib test

clean: ## Clean build artifacts
	flutter clean

sync-env: ## Regenerate ios/Flutter/Env.xcconfig from .env
	dart run tool/sync_env.dart

android\:aab:
	@bash scripts/build-aab.sh $(ARGS)

# Pass release notes through as: make android:aab:submit NOTES="what changed"
android\:aab\:submit:
	@if [ -n "$(NOTES)" ]; then \
		bash scripts/build-aab.sh --submit --notes "$(NOTES)" $(ARGS); \
	else \
		bash scripts/build-aab.sh --submit $(ARGS); \
	fi

# DANGER: both generators below overwrite checked-in Android branding
# resources. flutter_native_splash:create also strips the
# windowSplashScreenAnimatedIcon line from values-v31/styles.xml. Only run them
# if you intend to redo the branding by hand afterwards. Guarded so a stray
# `make icons` cannot silently wreck the drawables.
icons: ## DANGER regenerate launcher icons (clobbers hand-edited resources)
	@echo "This overwrites the launcher icon resources."
	@echo "Re-run with CONFIRM=1 if that is really what you want."
	@test "$(CONFIRM)" = "1" || exit 1
	dart run flutter_launcher_icons

splash: ## DANGER regenerate the native splash (clobbers hand-edited resources)
	@echo "This rewrites the splash drawables and values-v31/styles.xml."
	@echo "Re-run with CONFIRM=1 if that is really what you want."
	@test "$(CONFIRM)" = "1" || exit 1
	dart run flutter_native_splash:create
