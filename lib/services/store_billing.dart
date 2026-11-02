import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/brand.dart';

/// Achats integres de l'App Store et de Google Play.
///
/// L'abonnement appartient au compte Apple / Google de l'utilisateur
/// (tous ses appareils). Les droits actifs sont relus a chaque demarrage
/// sans rien demander (StoreKit 2 : droits en cours ; Google : achats actifs).
class StoreBilling extends ChangeNotifier {
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  final Map<Plan, ProductDetails> products = {};

  /// Forfait actif selon la boutique (null = aucun).
  Plan? entitled;
  DateTime? lastPurchase;

  Completer<bool>? _buying;
  final Set<Plan> _seen = {};

  Future<void> init() async {
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
    try {
      available = await _iap.isAvailable();
      if (!available) return;
      final r = await _iap.queryProductDetails({for (final p in Plan.values) p.storeId});
      for (final d in r.productDetails) {
        final plan = Plan.values.where((p) => p.storeId == d.id).firstOrNull;
        if (plan != null) products[plan] = d;
      }
      await refresh();
    } catch (e) {
      debugPrint('Boutique indisponible : $e');
    }
    notifyListeners();
  }

  /// Prix affiche par la boutique (devise et taxes du pays).
  String? priceOf(Plan p) => products[p]?.price;

  /// Relit les droits actifs. Aucun ecran ne s'affiche.
  Future<void> refresh() async {
    if (!available) return;
    _seen.clear();
    try {
      await _iap.restorePurchases();
      // Les droits arrivent par le flux d'achats juste apres.
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
      return;
    }
    final best = _best(_seen);
    if (best != entitled) {
      entitled = best;
      notifyListeners();
    }
  }

  static Plan? _best(Iterable<Plan> plans) {
    if (plans.isEmpty) return null;
    if (plans.contains(Plan.lifetime)) return Plan.lifetime;
    return plans.reduce((a, b) => a.months >= b.months ? a : b);
  }

  void _onPurchases(List<PurchaseDetails> list) {
    for (final p in list) {
      final plan = Plan.values.where((x) => x.storeId == p.productID).firstOrNull;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (plan != null) {
            _seen.add(plan);
            entitled = _best({?entitled, plan});
            lastPurchase = DateTime.now();
            notifyListeners();
          }
          _buying?.complete(true);
          _buying = null;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          _buying?.complete(false);
          _buying = null;
        case PurchaseStatus.pending:
          break;
      }
      if (p.pendingCompletePurchase) _iap.completePurchase(p);
    }
  }

  /// Ouvre la fenetre de paiement de la boutique. Vrai si achete.
  Future<bool> buy(Plan plan) async {
    final d = products[plan];
    if (d == null) throw StateError('product unavailable');
    _buying = Completer<bool>();
    final param = PurchaseParam(productDetails: d);
    final started = plan.recurring
        ? await _iap.buyNonConsumable(purchaseParam: param) // abonnements
        : await _iap.buyNonConsumable(purchaseParam: param); // a vie
    if (!started) {
      _buying = null;
      return false;
    }
    return _buying!.future.timeout(const Duration(minutes: 10), onTimeout: () => false);
  }

  /// Restaurer les achats (bouton exige par Apple).
  Future<bool> restore() async {
    await refresh();
    return entitled != null;
  }

  /// Gerer ou annuler l'abonnement dans la boutique.
  static Future<void> manage() async {
    final url = Brand.store == 'google'
        ? 'https://play.google.com/store/account/subscriptions?package=com.canalixtv.app'
        : 'https://apps.apple.com/account/subscriptions';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static String get storeName => Brand.store == 'google'
      ? 'Google Play'
      : (Platform.isMacOS ? 'Mac App Store' : 'App Store');

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
