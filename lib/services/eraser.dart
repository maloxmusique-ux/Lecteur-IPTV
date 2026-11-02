import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_recorder.dart';
import 'recorder.dart';

/// Efface tout ce que Canalix garde sur cet appareil (bouton « Supprimer
/// mes donnees »). Le serveur est efface avant, par LicenseService.
class DataEraser {
  DataEraser._();

  static Future<void> eraseLocal({
    required RecordingService recorder,
    required HomeServer homeServer,
    required bool recordings,
  }) async {
    // Plus d'enregistreur maison, plus de reveil programme.
    try {
      await homeServer.setEnabled(false);
    } catch (_) {}
    for (final rule in [...recorder.rules]) {
      recorder.removeRule(rule);
    }
    for (final r in [...recorder.items]) {
      await recorder.delete(r, deleteFile: recordings);
    }
    if (recordings) {
      // Dossier par defaut vide : on le retire aussi.
      try {
        final d = await recorder.folder();
        if (await d.exists() && d.listSync().isEmpty) await d.delete();
      } catch (_) {}
    }
    // Laisse le temps aux taches systeme (alarme, tache Windows) d'etre retirees.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    await _wipeStorage();
    // L'app tourne encore avec ses donnees en memoire : si quelque chose
    // est reecrit d'ici sa fermeture, ce sera efface au prochain lancement.
    try {
      final f = await _marker();
      await f.create(recursive: true);
    } catch (_) {}
  }

  static Future<File> _marker() async => File(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}erase_pending');

  /// Au demarrage, avant tout le reste : finit une suppression demandee.
  static Future<void> finishPending() async {
    try {
      final f = await _marker();
      if (!await f.exists()) return;
      await _wipeStorage();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<void> _wipeStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    try {
      await const FlutterSecureStorage().deleteAll();
    } catch (_) {}
    for (final get in [
      getApplicationSupportDirectory,
      getApplicationCacheDirectory,
    ]) {
      try {
        await _empty(await get());
      } catch (_) {}
    }
    // Dossier temporaire : propre a l'app sur telephone et Mac (bac a
    // sable). Sur Windows et Linux il est partage : on ne retire que le notre.
    try {
      final tmp = await getTemporaryDirectory();
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        await _empty(tmp);
      } else {
        final ts = Directory('${tmp.path}${Platform.pathSeparator}streamflow_timeshift');
        if (await ts.exists()) await ts.delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<void> _empty(Directory d) async {
    if (!await d.exists()) return;
    await for (final e in d.list(followLinks: false)) {
      try {
        await e.delete(recursive: true);
      } catch (_) {}
    }
  }
}
