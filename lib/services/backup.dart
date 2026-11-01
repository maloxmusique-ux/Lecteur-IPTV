import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Sauvegarde et restauration de toutes les donnees de l'application :
/// sources, reglages, profils, favoris, reprise, rappels, enregistrements.
class Backup {
  Backup._();

  static const _magic = 'StreamFlow-backup';

  static Future<Uint8List> export() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final k in prefs.getKeys()) {
      final v = prefs.get(k);
      if (v is bool) {
        data[k] = {'b': v};
      } else if (v is int) {
        data[k] = {'i': v};
      } else if (v is double) {
        data[k] = {'d': v};
      } else if (v is String) {
        data[k] = {'s': v};
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
    if (j['format'] != _magic) throw const FormatException('format');
    final data = j['prefs'] as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    for (final e in data.entries) {
      final v = e.value as Map<String, dynamic>;
      if (v.containsKey('b')) await prefs.setBool(e.key, v['b'] as bool);
      if (v.containsKey('i')) await prefs.setInt(e.key, v['i'] as int);
      if (v.containsKey('d')) {
        await prefs.setDouble(e.key, (v['d'] as num).toDouble());
      }
      if (v.containsKey('s')) await prefs.setString(e.key, v['s'] as String);
      if (v.containsKey('l')) {
        await prefs.setStringList(e.key, List<String>.from(v['l'] as List));
      }
    }
  }

  static String fileName() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'StreamFlow-sauvegarde-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }
}
