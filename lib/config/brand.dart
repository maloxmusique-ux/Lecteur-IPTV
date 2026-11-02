import 'dart:io';

/// Nom, contacts et serveur de licences de l'application.
/// Pour renommer l'app ou brancher le vrai serveur, tout se change ici
/// (et pour le serveur, aussi a la compilation avec --dart-define).
class Brand {
  Brand._();

  /// Nom court affiche dans l'app.
  static const name = 'Canalix';

  /// Nom complet (boutiques, recus).
  static const fullName = 'Canalix Player';

  /// Adresse du service client.
  static const supportEmail = 'support@canalixtv.com';

  /// Site web (aide, conditions, confidentialite).
  static const website = 'https://canalixtv.com';

  /// URL de la fonction Supabase "license" (vide = mode test local).
  static const licenseApi = String.fromEnvironment('LICENSE_API');

  /// Cle publique Supabase (anon), requise par les fonctions.
  static const licenseKey = String.fromEnvironment('LICENSE_KEY');

  static bool get testMode => licenseApi.isEmpty;

  /// Canal de distribution, fixe a la compilation (--dart-define=STORE=...).
  /// apple : App Store / Mac App Store, google : Google Play,
  /// none : telechargement direct (Windows, Mac hors boutique, APK).
  /// L'iPhone passe toujours par l'App Store.
  static const _store = String.fromEnvironment('STORE');
  static String get store =>
      _store.isNotEmpty ? _store : (Platform.isIOS ? 'apple' : 'none');

  /// Paiement par la boutique (obligatoire chez Apple et Google) :
  /// pas de Stripe ni de codes maison dans ces versions.
  static bool get storeBilling => store == 'apple' || store == 'google';

  /// Pages publiques (exigees par les boutiques).
  static const pages = 'https://maloxmusique-ux.github.io/Lecteur-IPTV';
  static const privacyUrl = '$pages/confidentialite.html';
  static const termsUrl = '$pages/conditions.html';
  static const supportUrl = '$pages/aide.html';

  /// Duree de l'essai gratuit.
  static const trialDays = 7;
}

/// Forfaits proposes (prix en cents, dollars canadiens).
enum Plan {
  monthly(1, 299),
  quarterly(3, 799),
  semiannual(6, 1299),
  yearly(12, 1999),
  lifetime(0, 3999);

  /// Duree en mois (0 = a vie).
  final int months;
  final int priceCents;
  const Plan(this.months, this.priceCents);

  /// Identifiant du produit dans l'App Store et Google Play.
  String get storeId => 'canalix_$name';

  bool get recurring => months > 0;

  String get price =>
      '${(priceCents / 100).toStringAsFixed(2).replaceAll('.', ',')} \$';

  /// Prix ramene au mois, pour comparer.
  double get monthlyEquivalent =>
      months == 0 ? 0 : priceCents / 100 / months;

  static Plan? byName(String? n) {
    for (final p in values) {
      if (p.name == n) return p;
    }
    return null;
  }
}
