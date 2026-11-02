import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/brand.dart';
import 'store_billing.dart';

enum LicenseStatus { trial, active, expired }

/// Un paiement (recu).
class Payment {
  final DateTime date;
  final int amountCents;
  final String currency;
  final Plan? plan;
  final String receiptUrl;

  const Payment(this.date, this.amountCents, this.currency, this.plan,
      this.receiptUrl);

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        DateTime.tryParse('${j['date']}') ?? DateTime.now(),
        (j['amount'] as num?)?.toInt() ?? 0,
        '${j['currency'] ?? 'cad'}',
        Plan.byName(j['plan'] as String?),
        '${j['receiptUrl'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'amount': amountCents,
        'currency': currency,
        'plan': plan?.name,
        'receiptUrl': receiptUrl,
      };
}

/// Etat de la licence de cet appareil.
class LicenseInfo {
  final LicenseStatus status;
  final DateTime trialEndsAt;
  final Plan? plan;

  /// Fin de la periode payee (null = a vie).
  final DateTime? expiresAt;

  /// Renouvellement automatique actif (abonnements).
  final bool autoRenew;

  /// stripe, apple, google, gift ou test.
  final String source;
  final List<Payment> payments;

  const LicenseInfo({
    required this.status,
    required this.trialEndsAt,
    this.plan,
    this.expiresAt,
    this.autoRenew = false,
    this.source = '',
    this.payments = const [],
  });

  bool get canPlay => status != LicenseStatus.expired;

  int get trialDaysLeft {
    final h = trialEndsAt.difference(DateTime.now()).inHours;
    return h <= 0 ? 0 : (h / 24).ceil();
  }

  factory LicenseInfo.fromJson(Map<String, dynamic> j) {
    DateTime? d(String k) => j[k] == null ? null : DateTime.tryParse('${j[k]}');
    return LicenseInfo(
      status: LicenseStatus.values.firstWhere((s) => s.name == j['status'],
          orElse: () => LicenseStatus.expired),
      trialEndsAt: d('trialEndsAt') ?? DateTime.now(),
      plan: Plan.byName(j['plan'] as String?),
      expiresAt: d('expiresAt'),
      autoRenew: j['autoRenew'] == true,
      source: '${j['source'] ?? ''}',
      payments: [
        for (final p in (j['payments'] as List? ?? const []))
          Payment.fromJson(p as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'trialEndsAt': trialEndsAt.toIso8601String(),
        'plan': plan?.name,
        'expiresAt': expiresAt?.toIso8601String(),
        'autoRenew': autoRenew,
        'source': source,
        'payments': [for (final p in payments) p.toJson()],
      };
}

/// Resultat d'une demande de paiement.
class CheckoutSession {
  final String url;
  const CheckoutSession(this.url);
}

/// Licence par appareil : essai gratuit, abonnement, annulation.
///
/// L'appareil est identifie par une adresse de type MAC generee une fois
/// (les vraies adresses MAC ne sont plus lisibles par les apps sur iPhone
/// et Android). Un secret aleatoire, connu seulement de l'appareil,
/// empeche quelqu'un d'autre d'annuler ou de modifier son abonnement.
class LicenseService extends ChangeNotifier {
  late SharedPreferences _prefs;
  late String mac;
  late String _secret;

  LicenseInfo info = LicenseInfo(
      status: LicenseStatus.trial,
      trialEndsAt: DateTime.now().add(const Duration(days: Brand.trialDays)));

  bool loading = false;
  String? error;
  Timer? _timer;

  /// Achats App Store / Google Play (versions publiees dans ces boutiques).
  final StoreBilling? _store = Brand.storeBilling ? StoreBilling() : null;

  /// Boutique active. En developpement (pas de serveur de licences) et tant
  /// que les produits ne sont pas crees dans la boutique, l'app garde
  /// l'essai et les paiements simules pour pouvoir etre testee.
  StoreBilling? get store {
    final st = _store;
    if (st == null) return null;
    if (Brand.testMode && st.products.isEmpty) return null;
    return st;
  }

  /// Derniere reponse du serveur (acces offert par le portail, etc.).
  LicenseInfo? _server;

  bool get canPlay => info.canPlay;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadIdentity();
    final cached = _prefs.getString('license_cache');
    if (cached != null) {
      try {
        info = LicenseInfo.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        info = _recompute(info);
      } catch (_) {}
    }
    if (_store != null) {
      _store.addListener(() => _set(_server ?? info));
      unawaited(_store.init());
    }
    unawaited(refresh());
    // Verification reguliere (fin d'essai, renouvellement).
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => refresh());
  }

  /// Identite de l'appareil, gardee hors des reglages (survit a une
  /// restauration de sauvegarde et a l'effacement du cache).
  Future<void> _loadIdentity() async {
    File? file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File('${dir.path}/device.json');
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        mac = j['mac'] as String;
        _secret = j['secret'] as String;
        await _prefs.setString('license_mac', mac);
        return;
      }
    } catch (_) {}
    final m = _prefs.getString('license_mac');
    final s = _prefs.getString('license_secret');
    if (m != null && s != null) {
      mac = m;
      _secret = s;
    } else {
      final r = Random.secure();
      final bytes = List<int>.generate(6, (_) => r.nextInt(256));
      bytes[0] = (bytes[0] & 0xFC) | 0x02; // adresse "locale", jamais celle d'un vrai materiel
      mac = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
      _secret = base64Url.encode(List<int>.generate(24, (_) => r.nextInt(256)));
    }
    await _prefs.setString('license_mac', mac);
    await _prefs.setString('license_secret', _secret);
    try {
      await file?.writeAsString(jsonEncode({'mac': mac, 'secret': _secret}));
    } catch (_) {}
  }

  /// Versions boutiques : l'abonnement vient d'Apple ou de Google. L'essai
  /// gratuit est l'offre de bienvenue de la boutique (pas de minuterie
  /// maison). Un acces offert par le portail reste valable.
  LicenseInfo _storeMerge(LicenseInfo i) {
    final st = store;
    if (st == null) return i;
    final plan = st.entitled;
    if (plan != null) {
      return LicenseInfo(
        status: LicenseStatus.active,
        trialEndsAt: i.trialEndsAt,
        plan: plan,
        autoRenew: plan.recurring,
        source: Brand.store,
        payments: i.payments,
      );
    }
    if (i.status == LicenseStatus.active && i.source == 'gift') return i;
    return LicenseInfo(
        status: LicenseStatus.expired, trialEndsAt: DateTime.now(), payments: i.payments);
  }

  /// Statut recalcule localement (fin d'essai ou d'abonnement sans reseau).
  LicenseInfo _recompute(LicenseInfo i) {
    final now = DateTime.now();
    // Abonnement echu (3 jours de grace si le renouvellement est en cours).
    final grace = i.autoRenew ? const Duration(days: 3) : Duration.zero;
    if (i.status == LicenseStatus.active &&
        i.expiresAt != null &&
        i.expiresAt!.add(grace).isBefore(now)) {
      return LicenseInfo(
          status: LicenseStatus.expired,
          trialEndsAt: i.trialEndsAt,
          plan: i.plan,
          expiresAt: i.expiresAt,
          source: i.source,
          payments: i.payments);
    }
    if (i.status == LicenseStatus.trial && i.trialEndsAt.isBefore(now)) {
      return LicenseInfo(
          status: LicenseStatus.expired,
          trialEndsAt: i.trialEndsAt,
          payments: i.payments);
    }
    return i;
  }

  void _set(LicenseInfo i) {
    _server = i;
    info = _storeMerge(_recompute(i));
    _prefs.setString('license_cache', jsonEncode(info.toJson()));
    notifyListeners();
  }

  // ------------------------------------------------------------- Serveur

  Future<Map<String, dynamic>> _call(String action,
      [Map<String, Object?> extra = const {}]) async {
    if (Brand.testMode) return _testCall(action, extra);
    final res = await http
        .post(
          Uri.parse(Brand.licenseApi),
          headers: {
            'Content-Type': 'application/json',
            if (Brand.licenseKey.isNotEmpty)
              'Authorization': 'Bearer ${Brand.licenseKey}',
            if (Brand.licenseKey.isNotEmpty) 'apikey': Brand.licenseKey,
          },
          body: jsonEncode({
            'action': action,
            'device': mac,
            'secret': _secret,
            'platform': Platform.operatingSystem,
            ...extra,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      throw Exception(body is Map ? body['error'] ?? 'HTTP ${res.statusCode}' : 'HTTP ${res.statusCode}');
    }
    return body as Map<String, dynamic>;
  }

  Future<void> refresh() async {
    unawaited(_store?.refresh());
    try {
      final j = await _call('status');
      error = null;
      _set(LicenseInfo.fromJson(j));
    } catch (e) {
      // Hors ligne : on garde le dernier etat connu.
      error = '$e';
      _set(info);
    }
  }

  /// Demande une page de paiement pour un forfait.
  Future<CheckoutSession> checkout(Plan plan) async {
    final j = await _call('checkout', {'plan': plan.name});
    return CheckoutSession('${j['url']}');
  }

  /// Annule le renouvellement (l'acces reste actif jusqu'a la fin).
  Future<void> cancel() async {
    loading = true;
    notifyListeners();
    try {
      _set(LicenseInfo.fromJson(await _call('cancel')));
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Reactive le renouvellement apres une annulation.
  Future<void> resume() async {
    loading = true;
    notifyListeners();
    try {
      _set(LicenseInfo.fromJson(await _call('resume')));
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Utilise un code cadeau. Renvoie null si c'est bon, sinon la cle
  /// de traduction de l'erreur.
  Future<String?> redeem(String code) async {
    loading = true;
    notifyListeners();
    try {
      _set(LicenseInfo.fromJson(await _call('redeem', {'code': code})));
      return null;
    } catch (e) {
      final m = '$e';
      for (final k in const ['invalid_code', 'used', 'already_redeemed',
          'already_subscribed', 'already_lifetime']) {
        if (m.contains(k)) return 'code_err_$k';
      }
      return 'code_err_network';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Attend la confirmation du paiement (apres la page de paiement).
  Future<bool> waitForActivation(
      {Duration timeout = const Duration(minutes: 15)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await refresh();
      if (info.status == LicenseStatus.active) return true;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  // ------------------------------------------- Mode test (sans serveur)

  /// Simule le serveur localement pour essayer les ecrans.
  Future<Map<String, dynamic>> _testCall(
      String action, Map<String, Object?> extra) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final raw = _prefs.getString('license_test');
    final now = DateTime.now();
    Map<String, dynamic> s = raw == null
        ? {
            'trialEndsAt':
                now.add(const Duration(days: Brand.trialDays)).toIso8601String(),
            'payments': <Map<String, dynamic>>[],
          }
        : jsonDecode(raw) as Map<String, dynamic>;
    switch (action) {
      case 'checkout':
        final plan = Plan.byName(extra['plan'] as String?) ?? Plan.monthly;
        return {'url': 'test://checkout/${plan.name}'};
      case 'pay': // appele par l'ecran de paiement simule
        final plan = Plan.byName(extra['plan'] as String?) ?? Plan.monthly;
        s['plan'] = plan.name;
        s['paidAt'] = now.toIso8601String();
        s['expiresAt'] = plan.recurring
            ? DateTime(now.year, now.month + plan.months, now.day).toIso8601String()
            : null;
        s['autoRenew'] = plan.recurring;
        s['source'] = 'test';
        (s['payments'] as List).insert(0, {
          'date': now.toIso8601String(),
          'amount': plan.priceCents,
          'currency': 'cad',
          'plan': plan.name,
          'receiptUrl': '',
        });
      case 'cancel':
        s['autoRenew'] = false;
      case 'resume':
        if (s['plan'] != null) s['autoRenew'] = true;
      case 'redeem':
        // Codes d'essai : TEST-1M, TEST-12M, TEST-VIE.
        final code = '${extra['code']}'.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
        const months = {'TEST1M': 1, 'TEST12M': 12, 'TESTVIE': 0};
        final m = months[code];
        if (m == null) throw Exception('invalid_code');
        final used = (s['codes'] as List?)?.cast<String>() ?? <String>[];
        if (used.contains(code)) throw Exception('already_redeemed');
        if (s['plan'] == 'lifetime') throw Exception('already_lifetime');
        if (s['autoRenew'] == true) throw Exception('already_subscribed');
        s['codes'] = [...used, code];
        if (m == 0) {
          s['plan'] = 'lifetime';
          s['expiresAt'] = null;
        } else {
          final cur = s['expiresAt'] == null ? null : DateTime.parse(s['expiresAt'] as String);
          final base = cur != null && cur.isAfter(now) ? cur : now;
          s['plan'] = m == 1 ? 'monthly' : 'yearly';
          s['expiresAt'] = DateTime(base.year, base.month + m, base.day).toIso8601String();
        }
        s['autoRenew'] = false;
        s['source'] = 'gift';
      case 'reset':
        s = {
          'trialEndsAt': now
              .add(Duration(days: extra['expired'] == true ? -1 : Brand.trialDays))
              .toIso8601String(),
          'payments': <Map<String, dynamic>>[],
        };
    }
    await _prefs.setString('license_test', jsonEncode(s));
    final plan = s['plan'] as String?;
    final exp = s['expiresAt'] == null ? null : DateTime.parse(s['expiresAt'] as String);
    final active = plan != null && (exp == null || exp.isAfter(now));
    final trialEnd = DateTime.parse(s['trialEndsAt'] as String);
    return {
      'status': active
          ? 'active'
          : (trialEnd.isAfter(now) && plan == null ? 'trial' : 'expired'),
      'trialEndsAt': s['trialEndsAt'],
      'plan': plan,
      'expiresAt': s['expiresAt'],
      'autoRenew': s['autoRenew'] ?? false,
      'source': s['source'] ?? 'test',
      'payments': s['payments'],
    };
  }

  /// Mode test : simule un paiement reussi.
  Future<void> testPay(Plan plan) async {
    _set(LicenseInfo.fromJson(await _testCall('pay', {'plan': plan.name})));
  }

  /// Mode test : recommence l'essai (ou le termine) pour essayer les ecrans.
  Future<void> testReset({bool expired = false}) async {
    _set(LicenseInfo.fromJson(await _testCall('reset', {'expired': expired})));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
