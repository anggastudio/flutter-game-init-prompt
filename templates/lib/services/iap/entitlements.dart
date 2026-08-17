import '../../core/env/env.dart';

/// A thing the player can buy, expressed as what it does rather than as a
/// product ID.
///
/// Prices, titles, descriptions and even which products exist all come from
/// the RevenueCat dashboard at runtime. Only the *behaviour* of each perk is
/// compiled in, keyed by an entitlement identifier read from `.env`. That
/// means the catalogue can be reshaped, repriced or A/B tested without a new
/// build; only introducing a genuinely new kind of perk needs code.
enum Perk {
  /// Hides every banner and interstitial. The rewarded ad stays available,
  /// because taking it away would punish the purchase.
  removeAds,

  /// Unlocks the alternate colour schemes.
  skins;

  /// The RevenueCat entitlement identifier this perk is bound to.
  String get entitlementId => switch (this) {
    Perk.removeAds => Env.entitlementRemoveAds,
    Perk.skins => Env.entitlementSkins,
  };

  /// Resolves an entitlement id coming back from RevenueCat to a perk this
  /// build knows how to act on. Returns null for anything unrecognised, which
  /// happens whenever the dashboard is ahead of the shipped app.
  static Perk? fromEntitlementId(String id) {
    for (final perk in Perk.values) {
      if (perk.entitlementId == id) return perk;
    }
    return null;
  }
}

/// What the player currently owns.
///
/// An immutable value type so it can be compared cheaply and pushed through a
/// stream without the listeners having to diff anything themselves.
class Entitlements {
  Entitlements(Set<Perk> owned) : _owned = Set.unmodifiable(owned);

  const Entitlements.none() : _owned = const {};

  final Set<Perk> _owned;

  bool has(Perk perk) => _owned.contains(perk);

  bool get adsRemoved => has(Perk.removeAds);

  bool get isEmpty => _owned.isEmpty;

  Iterable<Perk> get all => _owned;

  @override
  bool operator ==(Object other) =>
      other is Entitlements &&
      other._owned.length == _owned.length &&
      other._owned.containsAll(_owned);

  @override
  int get hashCode => Object.hashAllUnordered(_owned);

  @override
  String toString() =>
      'Entitlements(${_owned.map((p) => p.name).join(', ')})';
}
