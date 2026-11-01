/// Nom, contacts et serveur de licences de l'application.
/// Pour renommer l'app ou brancher le vrai serveur, tout se change ici
/// (et pour le serveur, aussi a la compilation avec --dart-define).
class Brand {
  Brand._();

  /// Nom court affiche dans l'app.
  static const name = 'Canalix';

  /// Nom complet (boutiques, recus).
  static const fullName = 'Canalix IPTV Player';

  /// Adresse du service client.
  static const supportEmail = 'support@canalixtv.com';

  /// Site web (aide, conditions, confidentialite).
  static const website = 'https://canalixtv.com';

  /// URL de la fonction Supabase "license" (vide = mode test local).
  static const licenseApi = String.fromEnvironment('LICENSE_API');

  /// Cle publique Supabase (anon), requise par les fonctions.
  static const licenseKey = String.fromEnvironment('LICENSE_KEY');

  static bool get testMode => licenseApi.isEmpty;

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
