import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../models/profile.dart';
import '../services/repository.dart';
import '../services/xtream_api.dart';
import 'settings.dart';

/// Mots-cles des categories verrouillees automatiquement (contenu adulte).
final kAdultPattern = RegExp(
    r'adult|xxx|porn|\+ ?18|18 ?\+|erotic|érotique|for adults|pour adultes',
    caseSensitive: false);

/// Etat global : sources, catalogue, EPG, profils, favoris, reprise,
/// controle parental et organisation des categories.
class AppState extends ChangeNotifier {
  final Settings settings;
  AppState(this.settings);

  final Repository repo = Repository();
  late SharedPreferences _prefs;

  List<Source> sources = [];
  Source? active;

  Catalog catalog = Catalog.empty;
  EpgData epg = EpgData.empty;

  /// Infos du compte Xtream actif (expiration, connexions, fuseau).
  XtreamAccount? account;

  bool loading = false;
  bool epgLoading = false;
  String? error;

  bool legalAccepted = false;

  // Profils.
  List<Profile> profiles = const [Profile(id: Profile.mainId, name: '')];
  String profileId = Profile.mainId;

  /// Vrai tant qu'aucun profil n'a ete choisi au demarrage (si plusieurs).
  bool profileChosen = true;

  Profile get profile => profiles.firstWhere((p) => p.id == profileId,
      orElse: () => profiles.first);

  Set<String> favorites = {};
  List<String> recents = [];
  Map<String, WatchProgress> progress = {};

  // Categories : cle "type|groupe".
  Set<String> hiddenGroups = {};
  Set<String> lockedGroups = {};
  Map<int, List<String>> groupOrder = {};

  /// Controle parental deverrouille pour la session.
  bool unlocked = false;

  /// Rafraichissement auto si le cache est plus vieux que ca.
  static const catalogMaxAge = Duration(hours: 12);
  static const epgMaxAge = Duration(hours: 6);

  Timer? _clock;

  /// Incremente regulierement pour rafraichir les barres EPG.
  final ValueNotifier<int> minuteTick = ValueNotifier(0);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    legalAccepted = _prefs.getBool('legal_v1') ?? false;
    _loadSourcesAndProfiles();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      minuteTick.value++;
    });
    if (active != null) unawaited(_loadActive());
  }

  void _loadSourcesAndProfiles() {
    final raw = _prefs.getString('sources');
    sources = raw == null
        ? []
        : [
            for (final e in jsonDecode(raw) as List)
              Source.fromJson(e as Map<String, dynamic>),
          ];
    final activeId = _prefs.getString('active');
    active = sources.isEmpty
        ? null
        : sources.firstWhere((s) => s.id == activeId,
            orElse: () => sources.first);

    final rawP = _prefs.getString('profiles');
    if (rawP != null) {
      profiles = [
        for (final e in jsonDecode(rawP) as List)
          Profile.fromJson(e as Map<String, dynamic>),
      ];
    }
    if (profiles.isEmpty) {
      profiles = const [Profile(id: Profile.mainId, name: '')];
    }
    profileId = _prefs.getString('profile_active') ?? Profile.mainId;
    if (!profiles.any((p) => p.id == profileId)) profileId = profiles.first.id;
    profileChosen = profiles.length < 2;
  }

  /// Recharge tout depuis le stockage (apres restauration d'une sauvegarde).
  Future<void> reloadAll() async {
    await _prefs.reload();
    legalAccepted = _prefs.getBool('legal_v1') ?? legalAccepted;
    _loadSourcesAndProfiles();
    profileChosen = true;
    catalog = Catalog.empty;
    epg = EpgData.empty;
    notifyListeners();
    if (active != null) await _loadActive();
  }

  Future<void> acceptLegal() async {
    legalAccepted = true;
    await _prefs.setBool('legal_v1', true);
    notifyListeners();
  }

  // --------------------------------------------------------------- Profils

  String profileName(Profile p) =>
      p.name.isEmpty && p.id == Profile.mainId ? tr('profile.main') : p.name;

  Future<void> _saveProfiles() => _prefs.setString(
      'profiles', jsonEncode([for (final p in profiles) p.toJson()]));

  Future<void> selectProfile(Profile p) async {
    profileId = p.id;
    profileChosen = true;
    unlocked = false;
    await _prefs.setString('profile_active', p.id);
    if (active != null) _loadPrefsFor(active!);
    notifyListeners();
  }

  Future<void> saveProfile(Profile p) async {
    final exists = profiles.any((e) => e.id == p.id);
    profiles = exists
        ? [for (final e in profiles) e.id == p.id ? p : e]
        : [...profiles, p];
    await _saveProfiles();
    notifyListeners();
  }

  Future<void> deleteProfile(Profile p) async {
    if (p.id == Profile.mainId) return;
    profiles = profiles.where((e) => e.id != p.id).toList();
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith('${p.id}_')) await _prefs.remove(k);
    }
    await _saveProfiles();
    if (profileId == p.id) await selectProfile(profiles.first);
    notifyListeners();
  }

  /// Cle de stockage propre au profil (le profil principal garde les
  /// anciennes cles pour rester compatible).
  String _pk(String base) =>
      profileId == Profile.mainId ? base : '${profileId}_$base';

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
      account = null;
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
    account = null;
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
    if (s.kind == SourceKind.xtream) unawaited(_loadAccount(s));

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

  Future<void> _loadAccount(Source s) async {
    try {
      final a = await XtreamApi(s).account();
      if (active?.id == s.id) {
        account = a;
        notifyListeners();
      }
    } catch (_) {
      // Informatif seulement.
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
      final archive = <String, int>{
        for (final c in catalog.live)
          if (c.hasArchive && c.epgId.isNotEmpty) c.epgId: c.archiveDays * 24,
      };
      final e = await repo.fetchEpg(url,
          userAgent: s.userAgent, archiveHours: archive);
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
      return tr('err.unreachable');
    }
    if (s.contains('TimeoutException')) return tr('err.timeout');
    if (s.contains('HTTP 401') || s.contains('HTTP 403')) {
      return tr('err.denied');
    }
    return s.replaceFirst('Exception: ', '');
  }

  /// Trouve une chaine du catalogue par identifiant.
  Channel? channelById(String id) {
    for (final c in catalog.live) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ------------------------------------------------------ Favoris / recents

  void _loadPrefsFor(Source s) {
    favorites = (_prefs.getStringList(_pk('fav_${s.id}')) ?? []).toSet();
    recents = _prefs.getStringList(_pk('rec_${s.id}')) ?? [];
    progress = {};
    final raw = _prefs.getString(_pk('prog_${s.id}'));
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        progress = {
          for (final e in m.entries)
            e.key: WatchProgress.fromJson(e.value as Map<String, dynamic>),
        };
      } catch (_) {}
    }
    final rawG = _prefs.getString('groups_${s.id}');
    hiddenGroups = {};
    lockedGroups = {};
    groupOrder = {};
    if (rawG != null) {
      try {
        final g = jsonDecode(rawG) as Map<String, dynamic>;
        hiddenGroups = Set<String>.from(g['hidden'] as List? ?? const []);
        lockedGroups = Set<String>.from(g['locked'] as List? ?? const []);
        groupOrder = {
          for (final e in (g['order'] as Map? ?? const {}).entries)
            int.parse('${e.key}'): List<String>.from(e.value as List),
        };
      } catch (_) {}
    }
  }

  bool isFavorite(Channel c) => favorites.contains(c.id);

  void toggleFavorite(Channel c) {
    final s = active;
    if (s == null) return;
    favorites = {...favorites};
    if (!favorites.remove(c.id)) favorites.add(c.id);
    _prefs.setStringList(_pk('fav_${s.id}'), favorites.toList());
    notifyListeners();
  }

  void markWatched(Channel c) {
    final s = active;
    if (s == null || c.type == ContentType.series) return;
    recents = [c.id, ...recents.where((e) => e != c.id)].take(40).toList();
    _prefs.setStringList(_pk('rec_${s.id}'), recents);
  }

  List<Channel> favoriteChannels(ContentType t) => catalog
      .of(t)
      .where((c) => favorites.contains(c.id) && canSee(c))
      .toList();

  List<Channel> recentChannels() {
    final all = {
      for (final c in [...catalog.live, ...catalog.movies]) c.id: c,
    };
    return [
      for (final id in recents)
        if (all[id] != null && canSee(all[id]!)) all[id]!,
    ];
  }

  // ---------------------------------------------------------------- Reprise

  WatchProgress? progressOf(Channel c) => progress[c.id];

  void saveProgress(Channel c, Duration pos, Duration dur) {
    final s = active;
    if (s == null || c.type == ContentType.live) return;
    if (pos.inSeconds < 5) return;
    progress = {
      ...progress,
      c.id: WatchProgress(c, pos.inMilliseconds, dur.inMilliseconds,
          DateTime.now().millisecondsSinceEpoch),
    };
    // On garde les 200 plus recents.
    if (progress.length > 200) {
      final sorted = progress.values.toList()
        ..sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
      progress = {for (final p in sorted.take(200)) p.item.id: p};
    }
    _prefs.setString(_pk('prog_${s.id}'),
        jsonEncode({for (final e in progress.entries) e.key: e.value.toJson()}));
    notifyListeners();
  }

  void clearProgress(Channel c) {
    final s = active;
    if (s == null || !progress.containsKey(c.id)) return;
    progress = {...progress}..remove(c.id);
    _prefs.setString(_pk('prog_${s.id}'),
        jsonEncode({for (final e in progress.entries) e.key: e.value.toJson()}));
    notifyListeners();
  }

  /// Films et episodes commences, du plus recent au plus ancien.
  List<WatchProgress> continueWatching() {
    final list = progress.values
        .where((p) => p.resumable && canSee(p.item))
        .toList()
      ..sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
    return list.take(30).toList();
  }

  // ------------------------------------------------------------- Parental

  bool get parentalOn => settings.parentalPin.isNotEmpty;

  bool checkPin(String pin) => pin == settings.parentalPin;

  void unlock() {
    unlocked = true;
    notifyListeners();
  }

  void lock() {
    unlocked = false;
    notifyListeners();
  }

  static String groupKey(ContentType t, String g) => '${t.index}|$g';

  bool isLockedGroup(ContentType t, String g) {
    if (!parentalOn) return false;
    if (lockedGroups.contains(groupKey(t, g))) return true;
    return settings.lockAdult && kAdultPattern.hasMatch(g);
  }

  /// Le contenu est-il visible sans code ?
  bool canSee(Channel c) {
    if (!isLockedGroup(c.type, c.groupKey)) return true;
    return unlocked && !profile.kids;
  }

  bool isHiddenGroup(ContentType t, String g) =>
      hiddenGroups.contains(groupKey(t, g));

  /// Categories dans l'ordre choisi, sans les categories masquees
  /// (ni verrouillees pour un profil enfant).
  List<String> groupsFor(ContentType t, {bool includeHidden = false}) {
    final base = catalog.groups[t] ?? const <String>[];
    final order = groupOrder[t.index];
    List<String> sorted;
    if (order == null || order.isEmpty) {
      sorted = base;
    } else {
      final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
      sorted = [...base]..sort((a, b) =>
          (rank[a] ?? 1 << 30).compareTo(rank[b] ?? 1 << 30));
    }
    return [
      for (final g in sorted)
        if (includeHidden ||
            (!isHiddenGroup(t, g) &&
                !(profile.kids && isLockedGroup(t, g))))
          g,
    ];
  }

  /// Entrees visibles d'un type (hors categories masquees ou verrouillees).
  Iterable<Channel> visibleItems(ContentType t) => catalog.of(t).where((c) =>
      !isHiddenGroup(t, c.groupKey) && canSee(c));

  Future<void> saveGroupPrefs({
    Set<String>? hidden,
    Set<String>? locked,
    Map<int, List<String>>? order,
  }) async {
    final s = active;
    if (s == null) return;
    if (hidden != null) hiddenGroups = hidden;
    if (locked != null) lockedGroups = locked;
    if (order != null) groupOrder = order;
    await _prefs.setString(
        'groups_${s.id}',
        jsonEncode({
          'hidden': hiddenGroups.toList(),
          'locked': lockedGroups.toList(),
          'order': {
            for (final e in groupOrder.entries) '${e.key}': e.value,
          },
        }));
    notifyListeners();
  }

  /// Nom affiche d'une categorie.
  static String groupLabel(String g) => g == kNoGroup ? tr('group.none') : g;

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }
}
