/// Modeles de donnees de StreamFlow.
library;

enum ContentType { live, movie, series }

enum SourceKind { m3u, xtream }

/// Une entree jouable (chaine live, film, serie ou episode).
class Channel {
  final String id;
  final String name;
  final String url;
  final String logo;
  final String group;
  final String epgId;
  final ContentType type;

  /// Identifiant de serie Xtream (uniquement pour [ContentType.series]).
  final String seriesId;

  /// En-tetes HTTP specifiques (User-Agent, Referer) issus de #EXTVLCOPT.
  final Map<String, String> headers;

  /// Nom en minuscules, pre-calcule pour une recherche rapide.
  final String searchKey;

  Channel({
    required this.id,
    required this.name,
    required this.url,
    this.logo = '',
    this.group = '',
    this.epgId = '',
    this.type = ContentType.live,
    this.seriesId = '',
    this.headers = const {},
  }) : searchKey = _normalize(name);

  static String _normalize(String s) => s.toLowerCase();

  Map<String, dynamic> toJson() => {
        'i': id,
        'n': name,
        'u': url,
        if (logo.isNotEmpty) 'l': logo,
        if (group.isNotEmpty) 'g': group,
        if (epgId.isNotEmpty) 'e': epgId,
        't': type.index,
        if (seriesId.isNotEmpty) 's': seriesId,
        if (headers.isNotEmpty) 'h': headers,
      };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        id: j['i'] as String,
        name: j['n'] as String,
        url: j['u'] as String,
        logo: (j['l'] as String?) ?? '',
        group: (j['g'] as String?) ?? '',
        epgId: (j['e'] as String?) ?? '',
        type: ContentType.values[j['t'] as int],
        seriesId: (j['s'] as String?) ?? '',
        headers: j['h'] == null
            ? const {}
            : Map<String, String>.from(j['h'] as Map),
      );
}

/// Une source de contenu configuree par l'utilisateur.
class Source {
  final String id;
  final String name;
  final SourceKind kind;

  /// URL de la playlist M3U ou URL du serveur Xtream.
  final String url;
  final String username;
  final String password;

  /// URL XMLTV optionnelle (sinon detectee automatiquement).
  final String epgUrl;

  /// User-Agent optionnel (certains fournisseurs l'exigent).
  final String userAgent;

  const Source({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    this.username = '',
    this.password = '',
    this.epgUrl = '',
    this.userAgent = '',
  });

  /// URL du serveur Xtream normalisee (sans slash final).
  String get server {
    var s = url.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    return s;
  }

  Source copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    String? epgUrl,
    String? userAgent,
  }) =>
      Source(
        id: id,
        name: name ?? this.name,
        kind: kind,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        epgUrl: epgUrl ?? this.epgUrl,
        userAgent: userAgent ?? this.userAgent,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.index,
        'url': url,
        'username': username,
        'password': password,
        'epgUrl': epgUrl,
        'userAgent': userAgent,
      };

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: SourceKind.values[j['kind'] as int],
        url: j['url'] as String,
        username: (j['username'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
        epgUrl: (j['epgUrl'] as String?) ?? '',
        userAgent: (j['userAgent'] as String?) ?? '',
      );
}

/// Catalogue complet d'une source, deja groupe par type et categorie.
/// Construit dans un isolate pour ne jamais bloquer l'interface.
class Catalog {
  final List<Channel> live;
  final List<Channel> movies;
  final List<Channel> series;

  /// Categories dans l'ordre d'apparition, par type.
  final Map<ContentType, List<String>> groups;

  /// URL EPG detectee (attribut url-tvg du M3U ou xmltv.php Xtream).
  final String epgUrl;

  const Catalog({
    required this.live,
    required this.movies,
    required this.series,
    required this.groups,
    this.epgUrl = '',
  });

  static const empty = Catalog(
    live: [],
    movies: [],
    series: [],
    groups: {},
  );

  bool get isEmpty => live.isEmpty && movies.isEmpty && series.isEmpty;

  List<Channel> of(ContentType t) => switch (t) {
        ContentType.live => live,
        ContentType.movie => movies,
        ContentType.series => series,
      };

  factory Catalog.fromChannels(List<Channel> all, {String epgUrl = ''}) {
    final live = <Channel>[];
    final movies = <Channel>[];
    final series = <Channel>[];
    final groups = <ContentType, List<String>>{
      for (final t in ContentType.values) t: <String>[],
    };
    final seen = <ContentType, Set<String>>{
      for (final t in ContentType.values) t: <String>{},
    };
    for (final c in all) {
      switch (c.type) {
        case ContentType.live:
          live.add(c);
        case ContentType.movie:
          movies.add(c);
        case ContentType.series:
          series.add(c);
      }
      final g = c.group.isEmpty ? 'Sans categorie' : c.group;
      if (seen[c.type]!.add(g)) groups[c.type]!.add(g);
    }
    return Catalog(
      live: live,
      movies: movies,
      series: series,
      groups: groups,
      epgUrl: epgUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'epg': epgUrl,
        'items': [
          for (final c in live) c.toJson(),
          for (final c in movies) c.toJson(),
          for (final c in series) c.toJson(),
        ],
      };

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog.fromChannels(
        [
          for (final e in j['items'] as List)
            Channel.fromJson(e as Map<String, dynamic>),
        ],
        epgUrl: (j['epg'] as String?) ?? '',
      );
}

/// Un programme du guide TV.
class Programme {
  final int start; // epoch ms
  final int stop; // epoch ms
  final String title;
  final String desc;

  const Programme(this.start, this.stop, this.title, this.desc);

  double progress(int nowMs) {
    if (stop <= start) return 0;
    return ((nowMs - start) / (stop - start)).clamp(0.0, 1.0);
  }

  List<dynamic> toJson() => [start, stop, title, desc];

  factory Programme.fromJson(List<dynamic> j) =>
      Programme(j[0] as int, j[1] as int, j[2] as String, j[3] as String);
}

/// Guide TV indexe par identifiant de chaine.
class EpgData {
  /// tvg-id -> programmes tries par heure de debut.
  final Map<String, List<Programme>> programmes;

  /// nom de chaine normalise -> tvg-id (pour les M3U sans tvg-id).
  final Map<String, String> nameIndex;

  const EpgData(this.programmes, this.nameIndex);

  static const empty = EpgData({}, {});

  bool get isEmpty => programmes.isEmpty;

  static String normalizeName(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  List<Programme>? forChannel(Channel c) {
    if (c.epgId.isNotEmpty) {
      final p = programmes[c.epgId];
      if (p != null) return p;
    }
    final id = nameIndex[normalizeName(c.name)];
    return id == null ? null : programmes[id];
  }

  /// Renvoie (programme en cours, programme suivant) via recherche binaire.
  (Programme?, Programme?) nowNext(Channel c, [int? nowMs]) {
    final list = forChannel(c);
    if (list == null || list.isEmpty) return (null, null);
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    var lo = 0, hi = list.length - 1, idx = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].start <= now) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (idx == -1) return (null, list.first);
    final cur = list[idx];
    final next = idx + 1 < list.length ? list[idx + 1] : null;
    return (cur.stop > now ? cur : null, next);
  }

  Map<String, dynamic> toJson() => {
        'p': {
          for (final e in programmes.entries)
            e.key: [for (final p in e.value) p.toJson()],
        },
        'n': nameIndex,
      };

  factory EpgData.fromJson(Map<String, dynamic> j) => EpgData(
        {
          for (final e in (j['p'] as Map).entries)
            e.key as String: [
              for (final p in e.value as List) Programme.fromJson(p as List),
            ],
        },
        Map<String, String>.from(j['n'] as Map),
      );
}
