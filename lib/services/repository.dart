import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'epg_parser.dart';
import 'm3u_parser.dart';
import 'net.dart';
import 'xtream_api.dart';

/// Charge les catalogues et guides TV.
///
/// Tout le travail lourd (reseau, decodage JSON, parsing M3U/XMLTV) est fait
/// dans des isolates separes : l'interface reste a 60/120 fps meme pendant
/// le chargement d'une playlist de 100 000 entrees.
/// Les resultats sont mis en cache disque pour un demarrage instantane.
class Repository {
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/cache');
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> _file(String name) async =>
      File('${(await _cacheDir()).path}/$name');

  // ---------------------------------------------------------------- Catalog

  Future<Catalog> fetchCatalog(Source source) async {
    final catalog = await Isolate.run(() => _fetchCatalogIsolate(source));
    _writeCache('catalog_${source.id}.json', () => catalog.toJson());
    return catalog;
  }

  static Future<Catalog> _fetchCatalogIsolate(Source s) async {
    switch (s.kind) {
      case SourceKind.m3u:
        final text = await fetchText(s.url, userAgent: s.userAgent);
        final c = parseM3u(text);
        if (s.epgUrl.isEmpty) return c;
        return Catalog(
          live: c.live,
          movies: c.movies,
          series: c.series,
          groups: c.groups,
          epgUrl: s.epgUrl,
        );
      case SourceKind.xtream:
        return XtreamApi(s).loadCatalog();
    }
  }

  /// Renvoie le catalogue en cache et son age, ou null.
  Future<(Catalog, Duration)?> cachedCatalog(Source source) async {
    final f = await _file('catalog_${source.id}.json');
    if (!await f.exists()) return null;
    final age = DateTime.now().difference(await f.lastModified());
    final path = f.path;
    try {
      final c = await Isolate.run(() async =>
          Catalog.fromJson(jsonDecode(await File(path).readAsString())));
      return (c, age);
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------- EPG

  Future<EpgData> fetchEpg(
    String url, {
    String userAgent = '',
    Map<String, int> archiveHours = const {},
    Set<String>? wantedIds,
    Set<String>? wantedNames,
  }) async {
    final epg = await Isolate.run(() async {
      final xml = await fetchText(url, userAgent: userAgent);
      return parseXmltv(xml,
          archiveHours: archiveHours,
          wantedIds: wantedIds,
          wantedNames: wantedNames);
    });
    _writeCache('epg_${_key(url)}.json', () => epg.toJson());
    return epg;
  }

  Future<(EpgData, Duration)?> cachedEpg(String url) async {
    final f = await _file('epg_${_key(url)}.json');
    if (!await f.exists()) return null;
    final age = DateTime.now().difference(await f.lastModified());
    final path = f.path;
    try {
      final e = await Isolate.run(() async =>
          EpgData.fromJson(jsonDecode(await File(path).readAsString())));
      return (e, age);
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------- Helpers

  /// Dossier de travail de l'application (sauvegardes, cache du direct).
  Future<Directory> appDir() async => getApplicationSupportDirectory();

  Future<void> deleteCache(Source source) async {
    final f = await _file('catalog_${source.id}.json');
    if (await f.exists()) await f.delete();
  }

  /// Ecrit le cache en arriere-plan (encodage JSON dans un isolate).
  void _writeCache(String name, Object Function() toJson) async {
    try {
      final f = await _file(name);
      final data = toJson();
      final path = f.path;
      await Isolate.run(() async {
        final tmp = File('$path.tmp');
        await tmp.writeAsString(jsonEncode(data), flush: true);
        await tmp.rename(path);
      });
    } catch (_) {
      // Le cache est optionnel.
    }
  }

  static String _key(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }
}
