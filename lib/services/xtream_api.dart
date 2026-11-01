import 'dart:convert';

import '../models/models.dart';
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
      throw Exception('Identifiants Xtream invalides');
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
        out['Saison $season'] = [
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
        out['Saison ${i + 1}'] = [
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
