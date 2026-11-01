import 'dart:convert';

import '../models/models.dart';
import '../l10n/i18n.dart';
import 'net.dart';

/// Client minimal de l'API Xtream Codes (player_api.php).
class XtreamApi {
  final Source source;
  XtreamApi(this.source);

  String get _base => source.server;
  String get _u => Uri.encodeComponent(source.username);
  String get _p => Uri.encodeComponent(source.password);

  String _api([String action = '', String extra = '']) =>
      '$_base/player_api.php?username=$_u&password=$_p'
      '${action.isEmpty ? '' : '&action=$action'}$extra';

  String get epgUrl => '$_base/xmltv.php?username=$_u&password=$_p';

  Future<dynamic> _get(String url) async =>
      jsonDecode(await fetchText(url, userAgent: source.userAgent));

  /// Verifie les identifiants. Leve une exception si invalides.
  Future<void> authenticate() async {
    final data = await _get(_api());
    final info = data is Map ? data['user_info'] : null;
    if (info is! Map || '${info['auth']}' != '1') {
      throw Exception(tr('err.badLogin'));
    }
  }

  /// Charge tout le catalogue (live, films, series) en parallele.
  /// Concu pour etre appele dans un isolate.
  Future<Catalog> loadCatalog() async {
    final results = await Future.wait([
      _get(_api('get_live_categories')),
      _get(_api('get_live_streams')),
      _get(_api('get_vod_categories')).catchError((_) => []),
      _get(_api('get_vod_streams')).catchError((_) => []),
      _get(_api('get_series_categories')).catchError((_) => []),
      _get(_api('get_series')).catchError((_) => []),
    ]);

    Map<String, String> cats(dynamic list) => {
          if (list is List)
            for (final c in list)
              if (c is Map) '${c['category_id']}': '${c['category_name']}',
        };

    final liveCats = cats(results[0]);
    final vodCats = cats(results[2]);
    final seriesCats = cats(results[4]);

    final all = <Channel>[];

    for (final s in _list(results[1])) {
      final id = '${s['stream_id']}';
      all.add(Channel(
        id: 'live_$id',
        name: _str(s['name']),
        url: '$_base/live/$_u/$_p/$id.ts',
        logo: _str(s['stream_icon']),
        group: liveCats['${s['category_id']}'] ?? '',
        epgId: _str(s['epg_channel_id']),
        type: ContentType.live,
        archiveDays: '${s['tv_archive']}' == '1'
            ? (int.tryParse('${s['tv_archive_duration']}') ?? 0)
            : 0,
      ));
    }
    for (final s in _list(results[3])) {
      final id = '${s['stream_id']}';
      final ext = _str(s['container_extension'], 'mp4');
      all.add(Channel(
        id: 'vod_$id',
        name: _str(s['name']),
        url: '$_base/movie/$_u/$_p/$id.$ext',
        logo: _str(s['stream_icon']),
        group: vodCats['${s['category_id']}'] ?? '',
        type: ContentType.movie,
      ));
    }
    for (final s in _list(results[5])) {
      final id = '${s['series_id']}';
      all.add(Channel(
        id: 'series_$id',
        name: _str(s['name']),
        url: '',
        logo: _str(s['cover']),
        group: seriesCats['${s['category_id']}'] ?? '',
        type: ContentType.series,
        seriesId: id,
      ));
    }
    return Catalog.fromChannels(
      all,
      epgUrl: source.epgUrl.isNotEmpty ? source.epgUrl : epgUrl,
    );
  }

  /// Informations du compte (expiration, connexions, fuseau du serveur).
  Future<XtreamAccount> account() async {
    final data = await _get(_api());
    final u = data is Map && data['user_info'] is Map ? data['user_info'] as Map : {};
    final srv =
        data is Map && data['server_info'] is Map ? data['server_info'] as Map : {};
    final exp = int.tryParse('${u['exp_date']}');
    // Decalage horaire du serveur : heure locale du serveur - heure UTC.
    var offset = 0;
    final ts = int.tryParse('${srv['timestamp_now']}');
    final local = '${srv['time_now'] ?? ''}';
    if (ts != null && local.length >= 19) {
      final asUtc = DateTime.tryParse('${local.replaceFirst(' ', 'T')}Z');
      if (asUtc != null) {
        offset = asUtc.millisecondsSinceEpoch - ts * 1000;
        // Arrondi au quart d'heure.
        offset = (offset / 900000).round() * 900000;
      }
    }
    return XtreamAccount(
      status: _str(u['status']),
      expires: exp == null || exp == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      maxConnections: int.tryParse('${u['max_connections']}') ?? 0,
      activeConnections: int.tryParse('${u['active_cons']}') ?? 0,
      serverOffsetMs: offset,
    );
  }

  /// Guide complet d'une chaine, y compris le passe disponible en rattrapage.
  Future<List<CatchupItem>> channelGuide(Channel c) async {
    final data =
        await _get(_api('get_simple_data_table', '&stream_id=${c.streamId}'));
    final list = data is Map ? data['epg_listings'] : null;
    final out = <CatchupItem>[];
    for (final e in _list(list)) {
      final start = int.tryParse('${e['start_timestamp']}');
      final stop = int.tryParse('${e['stop_timestamp']}');
      if (start == null || stop == null) continue;
      out.add(CatchupItem(
        programme: Programme(start * 1000, stop * 1000,
            _b64(e['title']), _b64(e['description'])),
        serverStart: _str(e['start']),
        hasArchive: '${e['has_archive']}' == '1',
      ));
    }
    out.sort((a, b) => a.programme.start.compareTo(b.programme.start));
    return out;
  }

  /// URL de rattrapage d'un programme passe.
  /// [serverStart] est l'heure de debut dans le fuseau du serveur
  /// ("2026-11-01 20:00:00").
  String catchupUrl(Channel c, String serverStart, Duration duration) {
    final d = serverStart.trim();
    final date = d.length >= 16
        ? '${d.substring(0, 10)}:${d.substring(11, 13)}-${d.substring(14, 16)}'
        : d;
    final minutes = (duration.inSeconds / 60).ceil();
    return '$_base/timeshift/$_u/$_p/$minutes/$date/${c.streamId}.ts';
  }

  /// Heure de debut au format serveur a partir d'un instant UTC.
  static String serverTime(int utcMs, int offsetMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(utcMs + offsetMs, isUtc: true);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:00';
  }

  static String _b64(dynamic v) {
    final s = _str(v);
    if (s.isEmpty) return s;
    try {
      return utf8.decode(base64.decode(base64.normalize(s)),
          allowMalformed: true);
    } catch (_) {
      return s;
    }
  }

  /// Episodes d'une serie, groupes par saison.
  Future<Map<String, List<Channel>>> seriesEpisodes(Channel series) async {
    final data = await _get(
        _api('get_series_info', '&series_id=${series.seriesId}'));
    final out = <String, List<Channel>>{};
    final eps = data is Map ? data['episodes'] : null;
    if (eps is Map) {
      final seasons = eps.keys.map((k) => '$k').toList()
        ..sort((a, b) =>
            (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      for (final season in seasons) {
        out[season] = [
          for (final e in _list(eps[season]))
            Channel(
              id: 'ep_${e['id']}',
              name: _episodeName(e),
              url: '$_base/series/$_u/$_p/${e['id']}.'
                  '${_str(e['container_extension'], 'mp4')}',
              logo: _str((e['info'] is Map ? e['info']['movie_image'] : null),
                  series.logo),
              group: series.name,
              type: ContentType.movie,
            ),
        ];
      }
    } else if (eps is List) {
      // Certains serveurs renvoient une liste de saisons.
      for (var i = 0; i < eps.length; i++) {
        out['${i + 1}'] = [
          for (final e in _list(eps[i]))
            Channel(
              id: 'ep_${e['id']}',
              name: _episodeName(e),
              url: '$_base/series/$_u/$_p/${e['id']}.'
                  '${_str(e['container_extension'], 'mp4')}',
              logo: series.logo,
              group: series.name,
              type: ContentType.movie,
            ),
        ];
      }
    }
    return out;
  }

  static String _episodeName(Map e) {
    final n = e['episode_num'];
    final t = _str(e['title']);
    return n == null ? t : 'E$n · $t';
  }

  static Iterable<Map> _list(dynamic v) =>
      v is List ? v.whereType<Map>() : const <Map>[];

  static String _str(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    final s = '$v'.trim();
    return s.isEmpty || s == 'null' ? fallback : s;
  }
}

class XtreamAccount {
  final String status;
  final DateTime? expires;
  final int maxConnections;
  final int activeConnections;
  final int serverOffsetMs;

  const XtreamAccount({
    required this.status,
    required this.expires,
    required this.maxConnections,
    required this.activeConnections,
    required this.serverOffsetMs,
  });
}

/// Programme du guide d'une chaine Xtream, avec infos de rattrapage.
class CatchupItem {
  final Programme programme;
  final String serverStart;
  final bool hasArchive;
  const CatchupItem({
    required this.programme,
    required this.serverStart,
    required this.hasArchive,
  });
}
