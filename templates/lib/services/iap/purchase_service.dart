import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/env/env.dart';
import 'entitlements.dart';

/// How a purchase attempt ended.
enum PurchaseOutcome {
  success,

  /// The player backed out. Not an error, and must not be reported as one.
  cancelled,

  failed,

  /// Purchases are not configured in this build.
  unavailable,
}

/// One buyable row in the store, flattened out of RevenueCat's offering so the
/// UI never has to touch the SDK's types.
class StoreOffer {
  const StoreOffer({
    required this.package,
    required this.title,
    required this.description,
    required this.priceString,
    required this.perk,
  });

  final Package package;
  final String title;
  final String description;

  /// Already localised and currency-formatted by the store.
  final String priceString;

  /// The perk this unlocks, or null when the dashboard is selling something
  /// this build does not recognise. Such a row is still shown and still
  /// purchasable; it simply has no local behaviour attached yet.
  final Perk? perk;

  String get id => package.identifier;
}

/// Wraps RevenueCat.
///
/// The whole service degrades to a no-op when no API key is configured, so a
/// developer can clone the repo, skip the RevenueCat setup entirely, and still
/// build and play the game. [isAvailable] tells the UI which state it is in.
class PurchaseService {
  PurchaseService();

  final StreamController<Entitlements> _entitlementsController =
      StreamController<Entitlements>.broadcast();

  Entitlements _entitlements = const Entitlements.none();
  bool _configured = false;

  /// Latest known entitlements. Safe to read before [init] completes; it
  /// simply reports nothing owned.
  Entitlements get entitlements => _entitlements;

  /// Emits whenever entitlements change, including from a purchase made on
  /// another device or a subscription lapsing server-side.
  Stream<Entitlements> get entitlementsStream => _entitlementsController.stream;

  bool get isAvailable => _configured;

  /// Configures the SDK and fetches the current customer.
  ///
  /// Never throws. A network failure here leaves the player with no perks for
  /// this session, which [restore] can fix, rather than blocking startup.
  Future<void> init() async {
    if (!Env.purchasesEnabled) {
      debugPrint('PurchaseService: no RevenueCat key, store disabled');
      return;
    }

    try {
      await Purchases.setLogLevel(
        Env.environment.isProduction ? LogLevel.warn : LogLevel.debug,
      );
      await Purchases.configure(PurchasesConfiguration(Env.revenueCatApiKey));
      _configured = true;

      // Fires on purchases, restores, and server-side changes alike, so this
      // one listener keeps the app in step with the account.
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);

      _onCustomerInfo(await Purchases.getCustomerInfo());
    } catch (error, stack) {
      debugPrint('PurchaseService: init failed ($error)');
      debugPrintStack(stackTrace: stack);
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    final owned = <Perk>{};
    for (final id in info.entitlements.active.keys) {
      final perk = Perk.fromEntitlementId(id);
      if (perk != null) owned.add(perk);
    }

    final next = Entitlements(owned);
    if (next == _entitlements) return;

    _entitlements = next;
    if (!_entitlementsController.isClosed) {
      _entitlementsController.add(next);
    }
  }

  /// Everything currently on sale.
  ///
  /// Reads the offering named in `.env`, or the dashboard's current offering
  /// when that is left at `default`. Returns an empty list rather than
  /// throwing, so the store screen can show an empty state instead of an
  /// error for a project whose offerings are not set up yet.
  Future<List<StoreOffer>> loadOffers() async {
    if (!_configured) return const [];

    try {
      final offerings = await Purchases.getOfferings();
      final offeringId = Env.revenueCatOfferingId;
      final offering = offeringId.isEmpty
          ? offerings.current
          : offerings.all[offeringId];

      if (offering == null) {
        debugPrint(
          'PurchaseService: no offering found '
          '(${offeringId.isEmpty ? "current" : offeringId}). '
          'Check the RevenueCat dashboard.',
        );
        return const [];
      }

      return offering.availablePackages.map((package) {
        final product = package.storeProduct;
        return StoreOffer(
          package: package,
          title: product.title,
          description: product.description,
          priceString: product.priceString,
          perk: _perkForPackage(package),
        );
      }).toList(growable: false);
    } catch (error) {
      debugPrint('PurchaseService: could not load offerings ($error)');
      return const [];
    }
  }

  /// Guesses which perk a package grants.
  ///
  /// RevenueCat does not tell you what a package *will* unlock before it is
  /// bought, only what the customer owns afterwards, so the mapping is by
  /// convention: the package or product identifier is expected to contain the
  /// entitlement id. A miss only costs the little perk icon in the store row;
  /// the purchase itself still works and the entitlement still arrives
  /// through the customer info listener.
  Perk? _perkForPackage(Package package) {
    final haystack =
        '${package.identifier} ${package.storeProduct.identifier}'
            .toLowerCase();
    for (final perk in Perk.values) {
      if (haystack.contains(perk.entitlementId.toLowerCase())) return perk;
    }
    return null;
  }

  /// Runs the platform purchase flow.
  Future<PurchaseOutcome> purchase(StoreOffer offer) async {
    if (!_configured) return PurchaseOutcome.unavailable;

    try {
      final result = await Purchases.purchase(
        PurchaseParams.package(offer.package),
      );
      _onCustomerInfo(result.customerInfo);
      return PurchaseOutcome.success;
    } on PlatformException catch (error) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      debugPrint('PurchaseService: purchase failed (${code.name})');
      return PurchaseOutcome.failed;
    } catch (error) {
      debugPrint('PurchaseService: purchase failed ($error)');
      return PurchaseOutcome.failed;
    }
  }

  /// Re-syncs entitlements from the store.
  ///
  /// Required by both app stores for non-consumables, and the fix for a
  /// player who reinstalled or switched devices.
  ///
  /// Returns the entitlements found, or null if the restore itself failed.
  Future<Entitlements?> restore() async {
    if (!_configured) return null;

    try {
      _onCustomerInfo(await Purchases.restorePurchases());
      return _entitlements;
    } catch (error) {
      debugPrint('PurchaseService: restore failed ($error)');
      return null;
    }
  }

  Future<void> dispose() async {
    if (_configured) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    }
    await _entitlementsController.close();
  }
}
