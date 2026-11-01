import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Recupere les donnees de l'ancienne version (nommee StreamFlow) :
/// sources, favoris, reglages, enregistrements prevus...
/// Ne fait rien si Canalix a deja ses propres donnees.
Future<void> migrateFromStreamFlow() async {
  try {
    final dir = await getApplicationSupportDirectory();
    if (File('${dir.path}${Platform.pathSeparator}shared_preferences.json')
        .existsSync()) {
      return;
    }
    Directory? old;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) old = Directory('$appData\\com.streamflow\\streamflow');
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) old = Directory('$home/.local/share/com.streamflow.streamflow');
    }
    if (old == null || !old.existsSync()) return;
    await dir.create(recursive: true);
    await for (final e in old.list(recursive: true)) {
      final rel = e.path.substring(old.path.length + 1);
      final target = '${dir.path}${Platform.pathSeparator}$rel';
      if (e is Directory) {
        await Directory(target).create(recursive: true);
      } else if (e is File) {
        await File(target).parent.create(recursive: true);
        await e.copy(target);
      }
    }
  } catch (_) {
    // Migration facultative.
  }
}
