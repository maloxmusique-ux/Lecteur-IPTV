import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'vault.dart';

/// Sauvegarde et restauration de toutes les donnees de l'application :
/// sources, reglages, profils, favoris, reprise, rappels, enregistrements.
class Backup {
  Backup._();

  static const _magic = 'Canalix-backup';

  /// Ancien format (avant le changement de nom), toujours accepte.
  static const _oldMagic = 'StreamFlow-backup';

  static Future<Uint8List> export() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final k in prefs.getKeys()) {
      // La licence est liee a l'appareil : jamais copiee ailleurs.
      if (k.startsWith('license_')) continue;
      final v = prefs.get(k);
      if (v is bool) {
        data[k] = {'b': v};
      } else if (v is int) {
        data[k] = {'i': v};
      } else if (v is double) {
        data[k] = {'d': v};
      } else if (v is String) {
        // Les identifiants sont dechiffres pour pouvoir etre restaures
        // sur un autre appareil (qui a une autre cle).
        data[k] = {'s': k == 'sources' ? Vault.decrypt(v) : v};
      } else if (v is List) {
        data[k] = {'l': v.map((e) => '$e').toList()};
      }
    }
    final json = const JsonEncoder.withIndent(' ').convert({
      'format': _magic,
      'version': 1,
      'date': DateTime.now().toIso8601String(),
      'prefs': data,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Restaure une sauvegarde. Leve une exception si le fichier est invalide.
  static Future<void> restore(Uint8List bytes) async {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['format'] != _magic && j['format'] != _oldMagic) throw const FormatException('format');
    final data = j['prefs'] as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().toList()) {
      if (!k.startsWith('license_')) await prefs.remove(k);
    }
    for (final e in data.entries) {
      if (e.key.startsWith('license_')) continue;
      final v = e.value as Map<String, dynamic>;
      if (v.containsKey('b')) await prefs.setBool(e.key, v['b'] as bool);
      if (v.containsKey('i')) await prefs.setInt(e.key, v['i'] as int);
      if (v.containsKey('d')) {
        await prefs.setDouble(e.key, (v['d'] as num).toDouble());
      }
      if (v.containsKey('s')) {
        final str = v['s'] as String;
        await prefs.setString(
            e.key, e.key == 'sources' && !Vault.isEncrypted(str) ? Vault.encrypt(str) : str);
      }
      if (v.containsKey('l')) {
        await prefs.setStringList(e.key, List<String>.from(v['l'] as List));
      }
    }
  }

  static String fileName() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Canalix-sauvegarde-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }
}
