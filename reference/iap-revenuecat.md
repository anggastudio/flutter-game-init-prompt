# In-app purchases: RevenueCat

Package: `purchases_flutter`. Wrapper: `lib/services/iap/purchase_service.dart`
plus `lib/services/iap/entitlements.dart`. Reference implementations in
[`templates/lib/services/iap/`](../templates/lib/services/iap/).

Use RevenueCat rather than the raw `in_app_purchase` plugin. It gives you
receipt validation, cross-device restore, and one entitlement model across both
stores, none of which you want to hand-roll for a game.

## Model perks as behaviour, not as products

The single most useful decision in this stack. A `Perk` enum maps each perk to
an **entitlement identifier read from `.env`**:

```dart
enum Perk { removeAds, revivePack, skins, starterBoost;
  String get entitlementId => switch (this) {
    Perk.removeAds => Env.entitlementRemoveAds,
    // ...
  };
}
```

Prices, titles, descriptions, and even which products exist all come from the
RevenueCat dashboard at runtime. Only the **behaviour** of each perk is compiled
in. The catalogue can be reshaped, repriced, or A/B tested without shipping a
build. Only a genuinely new kind of perk needs code.

## Flatten the SDK at the boundary

The store screen should never see a `Package` or a `CustomerInfo`. Expose a
plain value type:

```dart
class StoreOffer {
  final Package package;      // opaque handle, passed back to purchase()
  final String title;
  final String description;
  final String priceString;   // already localised and currency-formatted
  final Perk? perk;
}
```

A null `perk` means the dashboard is selling something this build does not
recognise. Show the row anyway and let it be purchased. It simply has no local
behaviour attached yet, and the entitlement will still arrive through the
customer info listener.

RevenueCat does not tell you what a package **will** unlock before it is bought,
only what the customer owns afterwards. Map package to perk by convention: the
package or product identifier is expected to contain the entitlement id. A miss
costs you an icon in the store row, nothing more.

## One listener covers everything

```dart
Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
_onCustomerInfo(await Purchases.getCustomerInfo());
```

That single callback fires on purchases, on restores, and on server-side changes
such as a subscription lapsing or a refund. One code path keeps the app in step
with the account. Push the result into a broadcast `Stream<Entitlements>` and
let the ad service and the UI both listen.

## Outcomes, not exceptions

```dart
enum PurchaseOutcome { success, cancelled, failed, unavailable }
```

A **cancelled** purchase is not an error. The player backed out. It gets no
error toast, no Sentry event, no retry prompt. Detect it specifically:

```dart
final code = PurchasesErrorHelper.getErrorCode(error);
if (code == PurchasesErrorCode.purchaseCancelledError) {
  return PurchaseOutcome.cancelled;
}
```

`unavailable` means no key is configured. The store screen shows an unavailable
state and the game runs on.

## Restore is mandatory

Both stores require a visible **Restore purchases** action for non-consumables.
It is also the fix for a player who reinstalled or switched devices, which is
the single most common support email a paid-perk game receives. Put it in
settings and in the store screen.

## Startup ordering

Resolve purchases **before** initialising the ad SDK. Entitlements decide
whether ads should load at all, and booting AdMob for someone who paid to remove
ads is a wasted request and a wasted second.

```dart
await purchaseService.init();
final entitlements = container.read(entitlementsProvider);
if (!entitlements.adsRemoved) {
  await adService.init();
}
```

Both of these run **unawaited** relative to the first frame. A slow network on a
cold start must not hold the menu hostage.

## Dashboard setup, in order

1. Create the products in the Play Console and in App Store Connect. Use the
   same product ids on both platforms where possible.
2. Create an **entitlement** per perk in RevenueCat. The identifier here is what
   goes into `.env` as `RC_ENTITLEMENT_*`, and it must match exactly.
3. Attach products to entitlements.
4. Build an **offering** (usually `default`) containing the packages to display.
   Leaving `REVENUECAT_OFFERING_ID=default` uses whichever offering is marked
   current in the dashboard, which is what you want unless A/B testing.
5. Add the Play service account credentials and the App Store Connect shared
   secret in RevenueCat so receipt validation works.

## Testing

- **Android**: upload a signed build to an internal test track first. License
  testers listed in the Play Console are charged nothing. Products do not
  resolve at all until a build containing them has been reviewed once.
- **iOS**: a StoreKit configuration file gets you local testing in the
  simulator. Sandbox accounts from App Store Connect test the real flow on
  device.
- Test the cancel path, the restore path, and the "already owns it" path. Those
  are where the bugs live, not in the happy path.

## Store rules worth knowing

- Anything that helps the player in a way the game presents as necessary should
  not sit behind a purchase in a title marketed to children. Cosmetics are
  always safe.
- Do not describe a non-consumable as a subscription or vice versa in the
  listing. Review teams check.
- If the game has loot boxes or randomised rewards, both stores require the odds
  to be disclosed.
