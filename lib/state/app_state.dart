import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/repository.dart';
import '../services/xtream_api.dart';

/// Etat global : sources, catalogue, EPG, favoris, historique.
class AppState extends ChangeNotifier {
  final Repository repo = Repository();
  late SharedPreferences _prefs;

  List<Source> sources = [];
  Source? active;

  Catalog catalog = Catalog.empty;
  EpgData epg = EpgData.empty;

  bool loading = false;
  bool epgLoading = false;
  String? error;

  bool legalAccepted = false;

  Set<String> favorites = {};
  List<String> recents = [];

  /// Rafraichissement auto si le cache est plus vieux que ca.
  static const catalogMaxAge = Duration(hours: 12);
  static const epgMaxAge = Duration(hours: 6);

  Timer? _clock;

  /// Incremente chaque minute pour rafraichir les barres EPG.
  final ValueNotifier<int> minuteTick = ValueNotifier(0);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    legalAccepted = _prefs.getBool('legal_v1') ?? false;
    final raw = _prefs.getString('sources');
    if (raw != null) {
      sources = [
        for (final e in jsonDecode(raw) as List)
          Source.fromJson(e as Map<String, dynamic>),
      ];
    }
    final activeId = _prefs.getString('active');
    if (sources.isNotEmpty) {
      active = sources.firstWhere((s) => s.id == activeId,
          orElse: () => sources.first);
    }
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      minuteTick.value++;
    });
    if (active != null) unawaited(_loadActive());
  }

  Future<void> acceptLegal() async {
    legalAccepted = true;
    await _prefs.setBool('legal_v1', true);
    notifyListeners();
  }

  // ---------------------------------------------------------------- Sources

  Future<void> addSource(Source s) async {
    if (s.kind == SourceKind.xtream) {
      await XtreamApi(s).authenticate();
    }
    sources = [...sources, s];
    await _saveSources();
    await selectSource(s);
  }

  Future<void> updateSource(Source s) async {
    sources = [for (final e in sources) e.id == s.id ? s : e];
    await _saveSources();
    if (active?.id == s.id) {
      active = s;
      await refresh();
    } else {
      notifyListeners();
    }
  }

  Future<void> removeSource(Source s) async {
    sources = sources.where((e) => e.id != s.id).toList();
    await repo.deleteCache(s);
    await _saveSources();
    if (active?.id == s.id) {
      active = sources.isEmpty ? null : sources.first;
      catalog = Catalog.empty;
      epg = EpgData.empty;
      if (active != null) {
        await _prefs.setString('active', active!.id);
        unawaited(_loadActive());
      }
    }
    notifyListeners();
  }

  Future<void> selectSource(Source s) async {
    active = s;
    catalog = Catalog.empty;
    epg = EpgData.empty;
    await _prefs.setString('active', s.id);
    notifyListeners();
    await _loadActive();
  }

  Future<void> _saveSources() => _prefs.setString(
      'sources', jsonEncode([for (final s in sources) s.toJson()]));

  // --------------------------------------------------------------- Loading

  /// Strategie "cache d'abord" : affiche immediatement le cache disque,
  /// puis rafraichit en arriere-plan s'il est perime.
  Future<void> _loadActive() async {
    final s = active;
    if (s == null) return;
    _loadPrefsFor(s);
    error = null;
    loading = true;
    notifyListeners();

    final cached = await repo.cachedCatalog(s);
    if (active?.id != s.id) return;
    if (cached != null) {
      catalog = cached.$1;
      loading = false;
      notifyListeners();
      unawaited(_loadEpg());
      if (cached.$2 > catalogMaxAge) unawaited(refresh(silent: true));
    } else {
      await refresh();
    }
  }

  Future<void> refresh({bool silent = false}) async {
    final s = active;
    if (s == null) return;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final c = await repo.fetchCatalog(s);
      if (active?.id != s.id) return;
      catalog = c;
      error = null;
      unawaited(_loadEpg(force: !silent));
    } catch (e) {
      if (!silent || catalog.isEmpty) error = _friendly(e);
    } finally {
      if (active?.id == s.id) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadEpg({bool force = false}) async {
    final s = active;
    final url = s?.epgUrl.isNotEmpty == true ? s!.epgUrl : catalog.epgUrl;
    if (s == null || url.isEmpty) return;
    if (!force) {
      final cached = await repo.cachedEpg(url);
      if (cached != null) {
        epg = cached.$1;
        notifyListeners();
        if (cached.$2 < epgMaxAge) return;
      }
    }
    epgLoading = true;
    notifyListeners();
    try {
      final e = await repo.fetchEpg(url, userAgent: s.userAgent);
      if (active?.id == s.id) epg = e;
    } catch (_) {
      // Le guide est facultatif.
    } finally {
      epgLoading = false;
      notifyListeners();
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('ClientException')) {
      return 'Impossible de joindre le serveur. Verifie l\'URL et ta connexion.';
    }
    if (s.contains('TimeoutException')) {
      return 'Le serveur met trop de temps a repondre.';
    }
    if (s.contains('HTTP 401') || s.contains('HTTP 403')) {
      return 'Acces refuse par le serveur (identifiants ou abonnement).';
    }
    return s.replaceFirst('Exception: ', '');
  }

  // ------------------------------------------------------ Favoris / recents

  void _loadPrefsFor(Source s) {
    favorites = (_prefs.getStringList('fav_${s.id}') ?? []).toSet();
    recents = _prefs.getStringList('rec_${s.id}') ?? [];
  }

  bool isFavorite(Channel c) => favorites.contains(c.id);

  void toggleFavorite(Channel c) {
    final s = active;
    if (s == null) return;
    favorites = {...favorites};
    if (!favorites.remove(c.id)) favorites.add(c.id);
    _prefs.setStringList('fav_${s.id}', favorites.toList());
    notifyListeners();
  }

  void markWatched(Channel c) {
    final s = active;
    if (s == null || c.type == ContentType.series) return;
    recents = [c.id, ...recents.where((e) => e != c.id)].take(40).toList();
    _prefs.setStringList('rec_${s.id}', recents);
  }

  List<Channel> favoriteChannels(ContentType t) =>
      catalog.of(t).where((c) => favorites.contains(c.id)).toList();

  List<Channel> recentChannels() {
    final all = {
      for (final c in [...catalog.live, ...catalog.movies]) c.id: c,
    };
    return [for (final id in recents) ?all[id]];
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }
}
