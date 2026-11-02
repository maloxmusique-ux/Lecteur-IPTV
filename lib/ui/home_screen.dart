import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../player/player_engine.dart';
import '../services/recorder.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import 'catchup_screen.dart';
import 'guide_screen.dart';
import 'multiview_screen.dart';
import 'navigation.dart';
import 'programme_sheet.dart';
import 'recordings_screen.dart';
import 'settings_screen.dart';
import 'sources_screen.dart';
import 'subscription_screen.dart';
import 'widgets/channel_logo.dart';
import 'widgets/channel_tile.dart';
import 'widgets/pin_dialog.dart';

export 'navigation.dart' show openItem, kWideBreakpoint;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Onglets de l'accueil.
enum HomeTab { live, guide, movies, series, mylist, recordings, sources, settings, more }

class _HomeScreenState extends State<HomeScreen> {
  // Statique : l'onglet reste le meme apres un changement de langue.
  static HomeTab _tab = HomeTab.live;

  static (IconData, IconData, String) _dest(HomeTab t) => switch (t) {
        HomeTab.live => (Icons.live_tv_outlined, Icons.live_tv_rounded, tr('tab.live')),
        HomeTab.guide => (Icons.calendar_view_week_outlined, Icons.calendar_view_week_rounded, tr('tab.guide')),
        HomeTab.movies => (Icons.movie_outlined, Icons.movie_rounded, tr('tab.movies')),
        HomeTab.series => (Icons.video_library_outlined, Icons.video_library_rounded, tr('tab.series')),
        HomeTab.mylist => (Icons.star_border_rounded, Icons.star_rounded, tr('tab.mylist')),
        HomeTab.recordings => (Icons.fiber_manual_record_outlined, Icons.fiber_manual_record, tr('tab.recordings')),
        HomeTab.sources => (Icons.settings_input_antenna_outlined, Icons.settings_input_antenna, tr('tab.sources')),
        HomeTab.settings => (Icons.settings_outlined, Icons.settings_rounded, tr('tab.settings')),
        HomeTab.more => (Icons.menu_rounded, Icons.menu_open_rounded, tr('tab.more')),
      };

  static const _wideTabs = [
    HomeTab.live,
    HomeTab.guide,
    HomeTab.movies,
    HomeTab.series,
    HomeTab.mylist,
    HomeTab.recordings,
    HomeTab.sources,
    HomeTab.settings,
  ];

  static const _mobileTabs = [
    HomeTab.live,
    HomeTab.guide,
    HomeTab.movies,
    HomeTab.series,
    HomeTab.more,
  ];

  Widget _view(HomeTab t) => switch (t) {
        HomeTab.live => const BrowseView(type: ContentType.live, key: PageStorageKey('live')),
        HomeTab.guide => const GuideView(),
        HomeTab.movies => const BrowseView(type: ContentType.movie, key: PageStorageKey('movie')),
        HomeTab.series => const BrowseView(type: ContentType.series, key: PageStorageKey('series')),
        HomeTab.mylist => const MyListView(),
        HomeTab.recordings => const RecordingsView(),
        HomeTab.sources => const SourcesView(),
        HomeTab.settings => const SettingsView(),
        HomeTab.more => const _MoreView(),
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final recording = context.select<RecordingService, int>((r) => r.activeCount);
    final wide = isWide(context);

    if (app.sources.isEmpty) {
      return const SourcesView(standalone: true);
    }

    final tabs = wide ? _wideTabs : _mobileTabs;
    if (!tabs.contains(_tab)) _tab = wide ? HomeTab.mylist : HomeTab.more;
    final index = tabs.indexOf(_tab);

    final body = Column(
      children: [
        const SafeArea(bottom: false, child: TrialBanner()),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: IndexedStack(
              index: index,
              children: [for (final t in tabs) _view(t)],
            ),
          ),
        ),
      ],
    );

    Widget icon(HomeTab t, bool selected) {
      final d = _dest(t);
      final i = Icon(selected ? d.$2 : d.$1);
      if (t == HomeTab.recordings && recording > 0) {
        return Badge(label: Text('$recording'), child: i);
      }
      return i;
    }

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: index,
                      labelType: NavigationRailLabelType.all,
                      minWidth: 76,
                      onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Image.asset('assets/icon/icon.png',
                            width: 40, height: 40, cacheWidth: 120),
                      ),
                      trailing: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: IconButton(
                          tooltip: tr('multi.title'),
                          icon: const Icon(Icons.grid_view_rounded),
                          onPressed: () => openMultiView(context),
                        ),
                      ),
                      destinations: [
                        for (final t in tabs)
                          NavigationRailDestination(
                            icon: icon(t, false),
                            selectedIcon: icon(t, true),
                            label: Text(_dest(t).$3),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: icon(t == HomeTab.more && recording > 0 ? HomeTab.recordings : t, false),
              selectedIcon: icon(t, true),
              label: _dest(t).$3,
            ),
        ],
      ),
    );
  }
}

/// Menu "Plus" sur mobile.
class _MoreView extends StatelessWidget {
  const _MoreView();

  @override
  Widget build(BuildContext context) {
    final rec = context.select<RecordingService, int>((r) => r.activeCount);
    void push(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: Text(tr('tab.more'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.star_rounded),
            title: Text(tr('tab.mylist')),
            onTap: () => push(const MyListView(standalone: true)),
          ),
          ListTile(
            leading: const Icon(Icons.fiber_manual_record),
            title: Text(tr('tab.recordings')),
            trailing: rec > 0 ? Badge(label: Text('$rec')) : null,
            onTap: () => push(const RecordingsView()),
          ),
          ListTile(
            leading: const Icon(Icons.grid_view_rounded),
            title: Text(tr('multi.title')),
            onTap: () => openMultiView(context),
          ),
          ListTile(
            leading: const Icon(Icons.settings_input_antenna),
            title: Text(tr('tab.sources')),
            onTap: () => push(const SourcesView()),
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: Text(tr('tab.settings')),
            onTap: () => push(const SettingsView()),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- BrowseView

class BrowseView extends StatefulWidget {
  final ContentType type;
  const BrowseView({super.key, required this.type});

  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  String? _group; // null = tout
  String _query = '';
  Timer? _debounce;
  final _search = TextEditingController();

  // Memoisation du filtrage : recalcule uniquement si une entree change.
  Object? _memoKey;
  List<Channel> _memo = const [];

  List<Channel> _filtered(AppState app) {
    final key = (app.catalog, _group, _query, app.unlocked, app.hiddenGroups,
        app.lockedGroups, app.profileId, app.parentalOn);
    if (key == _memoKey) return _memo;
    Iterable<Channel> items;
    final g = _group;
    if (g != null) {
      items = app.catalog
          .of(widget.type)
          .where((c) => c.groupKey == g && app.canSee(c));
    } else {
      items = app.visibleItems(widget.type);
      // Sans filtre, on respecte l'ordre des categories choisi.
      if (app.groupOrder[widget.type.index]?.isNotEmpty == true) {
        final rank = {
          for (final (i, g) in app.groupsFor(widget.type).indexed) g: i,
        };
        final list = items.toList();
        final idx = {for (final (i, c) in list.indexed) c.id: i};
        list.sort((a, b) {
          final r = (rank[a.groupKey] ?? 1 << 30)
              .compareTo(rank[b.groupKey] ?? 1 << 30);
          return r != 0 ? r : idx[a.id]!.compareTo(idx[b.id]!);
        });
        items = list;
      }
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final words = q.split(RegExp(r'\s+'));
      items = items.where((c) => words.every(c.searchKey.contains));
    }
    _memoKey = key;
    return _memo = items.toList(growable: false);
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _query = v);
    });
  }

  Future<void> _selectGroup(AppState app, String? g) async {
    if (g != null && app.isLockedGroup(widget.type, g) && !app.unlocked) {
      if (!await askUnlock(context)) return;
    }
    if (mounted) setState(() => _group = g);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String get _title => switch (widget.type) {
        ContentType.live => tr('browse.live'),
        ContentType.movie => tr('tab.movies'),
        ContentType.series => tr('tab.series'),
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = isWide(context);
    final groups = app.groupsFor(widget.type);
    if (_group != null && !groups.contains(_group)) _group = null;

    if (app.catalog.isEmpty) {
      return _StatusView(app: app);
    }

    final items = _filtered(app);
    final live = widget.type == ContentType.live;
    final list = live
        ? _LiveList(items: items, inlinePreview: !wide)
        : _PosterGrid(items: items);

    final header = _Header(
      title: _title,
      count: items.length,
      controller: _search,
      onChanged: _onSearch,
      loading: app.loading || app.epgLoading,
      onRefresh: app.refresh,
    );

    if (wide) {
      return Row(
        children: [
          SizedBox(
            width: 240,
            child: _GroupList(
              type: widget.type,
              groups: groups,
              selected: _group,
              onSelect: (g) => _selectGroup(app, g),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 5,
            child: Column(children: [header, Expanded(child: list)]),
          ),
          if (widget.type == ContentType.live) ...[
            const VerticalDivider(width: 1),
            const Expanded(flex: 6, child: _PreviewPanel()),
          ],
        ],
      );
    }

    // Telephone : apercu en haut (si une chaine est choisie), puis
    // recherche, categories et liste, toujours visibles.
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (live) const _MobilePreview(),
          // Apercu affiche : on garde la place pour la liste.
          if (live && context.select<PlayerEngine, bool>((e) => e.current?.type == ContentType.live))
            _Header(
              compact: true,
              title: _title,
              count: items.length,
              controller: _search,
              onChanged: _onSearch,
              loading: app.loading || app.epgLoading,
              onRefresh: app.refresh,
            )
          else
            header,
          _GroupChips(
            type: widget.type,
            groups: groups,
            selected: _group,
            onSelect: (g) => _selectGroup(app, g),
          ),
          const SizedBox(height: 4),
          Expanded(child: list),
        ],
      ),
    );
  }
}

/// Categories sur telephone : bouton "toutes les categories" (liste avec
/// recherche, pratique quand il y a des dizaines de pays) + puces.
class _GroupChips extends StatelessWidget {
  final ContentType type;
  final List<String> groups;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _GroupChips({
    required this.type,
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  Future<void> _openSheet(BuildContext context) async {
    final g = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _GroupSheet(type: type, groups: groups, selected: selected),
    );
    if (g != null) onSelect(g == '' ? null : g);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: groups.length + 2,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                avatar: Icon(Icons.list_rounded, size: 18, color: scheme.primary),
                label: Text(selected == null
                    ? tr('browse.categories')
                    : AppState.groupLabel(selected!)),
                onPressed: () => _openSheet(context),
              ),
            );
          }
          final g = i == 1 ? null : groups[i - 2];
          final locked = g != null && app.isLockedGroup(type, g) && !app.unlocked;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              avatar: locked ? const Icon(Icons.lock_rounded, size: 16) : null,
              label: Text(g == null ? tr('common.all') : AppState.groupLabel(g)),
              selected: selected == g,
              onSelected: (_) => onSelect(g),
            ),
          );
        },
      ),
    );
  }
}

class _GroupSheet extends StatefulWidget {
  final ContentType type;
  final List<String> groups;
  final String? selected;
  const _GroupSheet({required this.type, required this.groups, required this.selected});

  @override
  State<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends State<_GroupSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final q = _q.toLowerCase();
    final list = [
      null,
      ...widget.groups.where((g) => AppState.groupLabel(g).toLowerCase().contains(q)),
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: tr('browse.searchCategory'),
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final g = list[i];
                if (g == null && q.isNotEmpty) return const SizedBox.shrink();
                final sel = widget.selected == g;
                final locked = g != null && app.isLockedGroup(widget.type, g) && !app.unlocked;
                final n = g == null ? null : app.catalog.countIn(widget.type, g);
                return ListTile(
                  selected: sel,
                  selectedTileColor: scheme.secondaryContainer,
                  leading: Icon(g == null ? Icons.apps_rounded : Icons.folder_outlined),
                  title: Text(g == null ? tr('browse.allGroups') : AppState.groupLabel(g)),
                  trailing: locked
                      ? const Icon(Icons.lock_rounded, size: 18)
                      : (n == null ? null : Text('$n')),
                  onTap: () => Navigator.pop(context, g ?? ''),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Apercu video sur telephone : la chaine joue en haut, la liste reste
/// visible pour zapper. Toucher la video = plein ecran.
class _MobilePreview extends StatelessWidget {
  const _MobilePreview();

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PlayerEngine>();
    final app = context.watch<AppState>();
    final c = engine.current;
    if (c == null || c.type != ContentType.live) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final now = app.epg.isEmpty ? null : app.epg.nowNext(c).$1;
    return Material(
      color: Colors.black,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: GestureDetector(
              onTap: () => openItem(context, c, engine.queue, inlinePreview: true),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: Video(controller: engine.video, controls: NoVideoControls),
                  ),
                  if (engine.lastError != null)
                    Center(
                      child: Text(tr('player.reconnecting', [engine.retries]),
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: IconButton.filledTonal(
                      tooltip: tr('player.fullscreen'),
                      icon: const Icon(Icons.fullscreen_rounded),
                      onPressed: () =>
                          openItem(context, c, engine.queue, inlinePreview: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                ChannelLogo(url: c.logo, name: c.name, width: 36, height: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(now?.title ?? tr('preview.tapFull'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('common.more'),
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => showChannelMenu(context, c, engine.queue),
                ),
                IconButton(
                  tooltip: tr('preview.close'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: engine.stop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final int count;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool loading;
  final Future<void> Function() onRefresh;
  final bool compact;

  const _Header({
    this.compact = false,
    required this.title,
    required this.count,
    required this.controller,
    required this.onChanged,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 8 : 12, compact ? 16 : 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) Row(
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(width: 8),
              Text('$count',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(
                  tooltip: tr('common.refresh'),
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          if (!compact) const SizedBox(height: 8),
          TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: tr('common.search'),
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: ValueListenableBuilder(
                valueListenable: controller,
                builder: (_, v, _) => v.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  final ContentType type;
  final List<String> groups;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _GroupList({
    required this.type,
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groups.length + 1,
      itemExtent: 44,
      itemBuilder: (_, i) {
        final g = i == 0 ? null : groups[i - 1];
        final sel = selected == g;
        final locked =
            g != null && app.isLockedGroup(type, g) && !app.unlocked;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Material(
            color: sel ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelect(g),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g == null ? tr('browse.allGroups') : AppState.groupLabel(g),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          color: sel ? scheme.onSecondaryContainer : null,
                        ),
                      ),
                    ),
                    if (locked)
                      Icon(Icons.lock_rounded,
                          size: 16, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LiveList extends StatelessWidget {
  final List<Channel> items;
  final bool inlinePreview;
  const _LiveList({required this.items, this.inlinePreview = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final currentId =
        context.select<PlayerEngine, String?>((e) => e.current?.id);
    final recorder = context.watch<RecordingService>();
    if (items.isEmpty) return Center(child: Text(tr('common.noResults')));
    return ValueListenableBuilder<int>(
      valueListenable: app.minuteTick,
      builder: (context, _, _) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        return Scrollbar(
          child: ListView.builder(
            itemCount: items.length,
            itemExtent: kChannelTileHeight,
            addAutomaticKeepAlives: false,
            itemBuilder: (context, i) {
              final c = items[i];
              return ChannelTile(
                channel: c,
                number: i + 1,
                nowMs: nowMs,
                now: app.epg.isEmpty ? null : app.epg.nowNext(c, nowMs).$1,
                selected: c.id == currentId,
                favorite: app.isFavorite(c),
                recording: recorder.recordingFor(c) != null,
                onFavorite: () => app.toggleFavorite(c),
                onTap: () =>
                    openItem(context, c, items, inlinePreview: inlinePreview),
                onLongPress: () => showChannelMenu(context, c, items),
              );
            },
          ),
        );
      },
    );
  }
}

/// Menu d'une chaine (appui long ou clic droit).
Future<void> showChannelMenu(
    BuildContext context, Channel c, List<Channel> queue) async {
  final app = context.read<AppState>();
  final recorder = context.read<RecordingService>();
  final source = app.active;
  if (source == null) return;
  final rec = recorder.recordingFor(c);
  final now = DateTime.now().millisecondsSinceEpoch;
  final cur = app.epg.nowNext(c, now).$1;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: ChannelLogo(url: c.logo, name: c.name),
            title: Text(c.name, style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: cur == null ? null : Text(cur.title),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(app.isFavorite(c) ? Icons.star_rounded : Icons.star_border_rounded),
            title: Text(app.isFavorite(c) ? tr('fav.remove') : tr('fav.add')),
            onTap: () {
              Navigator.pop(ctx);
              app.toggleFavorite(c);
            },
          ),
          if (c.hasArchive && source.kind == SourceKind.xtream)
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(tr('catchup.title')),
              subtitle: Text(tr('catchup.days', [c.archiveDays])),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CatchupScreen(channel: c)));
              },
            ),
          if (rec != null)
            ListTile(
              leading: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
              title: Text(tr('rec.stop')),
              onTap: () {
                Navigator.pop(ctx);
                recorder.stopRecording(rec);
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
              title: Text(tr('rec.now')),
              onTap: () {
                Navigator.pop(ctx);
                recordNowDialog(context, c);
              },
            ),
          ListTile(
            leading: const Icon(Icons.grid_view_rounded),
            title: Text(tr('multi.add')),
            onTap: () {
              Navigator.pop(ctx);
              openMultiView(context, initial: c);
            },
          ),
        ],
      ),
    ),
  );
}

class _PosterGrid extends StatelessWidget {
  final List<Channel> items;
  const _PosterGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (items.isEmpty) return Center(child: Text(tr('common.noResults')));
    return Scrollbar(
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170,
          childAspectRatio: 0.58,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        addAutomaticKeepAlives: false,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final c = items[i];
          return PosterCard(
            item: c,
            favorite: app.isFavorite(c),
            progress: app.progressOf(c)?.fraction,
            onTap: () => openItem(context, c, items),
            onLongPress: () => showVodMenu(context, c),
          );
        },
      ),
    );
  }
}

/// Menu d'un film ou d'une serie.
Future<void> showVodMenu(BuildContext context, Channel c) async {
  final app = context.read<AppState>();
  final source = app.active;
  if (source == null) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(c.name, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(app.isFavorite(c) ? Icons.star_rounded : Icons.star_border_rounded),
            title: Text(app.isFavorite(c) ? tr('fav.remove') : tr('fav.add')),
            onTap: () {
              Navigator.pop(ctx);
              app.toggleFavorite(c);
            },
          ),
          if (c.type == ContentType.movie && c.url.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text(tr('rec.download')),
              subtitle: Text(tr('rec.downloadHint')),
              onTap: () {
                Navigator.pop(ctx);
                context.read<RecordingService>().download(source, c, c.url, c.name);
                toast(context, tr('rec.downloadStarted'));
              },
            ),
          if (app.progressOf(c) != null)
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: Text(tr('resume.clear')),
              onTap: () {
                Navigator.pop(ctx);
                app.clearProgress(c);
              },
            ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------- Preview panel

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel();

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PlayerEngine>();
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final c = engine.current;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: Colors.black,
                child: c == null
                    ? Center(
                        child: Text(
                          tr('preview.select'),
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: Colors.white54),
                        ),
                      )
                    : GestureDetector(
                        onDoubleTap: () => openItem(context, c, engine.queue),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RepaintBoundary(
                              child: Video(
                                controller: engine.video,
                                controls: NoVideoControls,
                              ),
                            ),
                            if (engine.lastError != null)
                              Center(
                                child: Text(
                                  tr('player.reconnecting', [engine.retries]),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: IconButton.filledTonal(
                                tooltip: tr('player.fullscreen'),
                                icon: const Icon(Icons.fullscreen_rounded),
                                onPressed: () =>
                                    openItem(context, c, engine.queue),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (c != null) ...[
            Row(
              children: [
                ChannelLogo(url: c.logo, name: c.name, width: 52, height: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                if (c.hasArchive && app.active?.kind == SourceKind.xtream)
                  IconButton(
                    tooltip: tr('catchup.title'),
                    icon: const Icon(Icons.history_rounded),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => CatchupScreen(channel: c))),
                  ),
                IconButton(
                  tooltip: tr('common.more'),
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => showChannelMenu(context, c, engine.queue),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _ProgrammeList(channel: c, app: app)),
          ],
        ],
      ),
    );
  }
}

class _ProgrammeList extends StatelessWidget {
  final Channel channel;
  final AppState app;
  const _ProgrammeList({required this.channel, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reminders = context.watch<ReminderService>();
    final recorder = context.watch<RecordingService>();
    final sourceId = app.active?.id ?? '';
    return ValueListenableBuilder<int>(
      valueListenable: app.minuteTick,
      builder: (context, _, _) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final all = app.epg.forChannel(channel) ?? const <Programme>[];
        final upcoming = all.where((p) => p.stop > now).take(40).toList();
        if (upcoming.isEmpty) {
          return Text(
            app.epgLoading ? tr('epg.loading') : tr('epg.none'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
        }
        String? lastDay;
        return ListView.builder(
          itemCount: upcoming.length,
          itemBuilder: (_, i) {
            final p = upcoming[i];
            final live = p.start <= now;
            final day = dayLabel(DateTime.fromMillisecondsSinceEpoch(p.start));
            final showDay = day != lastDay;
            lastDay = day;
            final hasRem = reminders.has(sourceId, channel, p);
            final hasRec = recorder.isScheduled(sourceId, channel, p);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDay && i > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                    child: Text(day,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => showProgrammeSheet(context, channel, p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(hm(p.start),
                              style: theme.textTheme.labelLarge?.copyWith(
                                  color: live ? theme.colorScheme.primary : null)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.title,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight:
                                          live ? FontWeight.w700 : FontWeight.w400)),
                              if (live) ...[
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                    value: p.progress(now), minHeight: 3),
                              ],
                              if (live && p.desc.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(p.desc,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ],
                          ),
                        ),
                        if (hasRem)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.notifications_active_rounded,
                                size: 18, color: Colors.amber),
                          ),
                        if (hasRec)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.fiber_manual_record,
                                size: 16, color: Colors.redAccent),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
            );
          },
        );
      },
    );
  }
}

// ------------------------------------------------------------- Ma liste

/// Continuer a regarder, favoris, rappels et vus recemment.
class MyListView extends StatelessWidget {
  final bool standalone;
  const MyListView({super.key, this.standalone = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final reminders = context.watch<ReminderService>();
    final live = app.favoriteChannels(ContentType.live);
    final vod = [
      ...app.favoriteChannels(ContentType.movie),
      ...app.favoriteChannels(ContentType.series),
    ];
    final cont = app.continueWatching();
    final recent = app.recentChannels();
    final rems = reminders.items;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final theme = Theme.of(context);

    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(t, style: theme.textTheme.titleMedium),
        );

    final empty = live.isEmpty &&
        vod.isEmpty &&
        recent.isEmpty &&
        cont.isEmpty &&
        rems.isEmpty;

    final content = empty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr('mylist.empty'), textAlign: TextAlign.center),
            ),
          )
        : CustomScrollView(
            slivers: [
              if (cont.isNotEmpty) ...[
                SliverToBoxAdapter(child: title(tr('mylist.continue'))),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 250,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: cont.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final w = cont[i];
                        return SizedBox(
                          width: 145,
                          child: PosterCard(
                            item: w.item,
                            progress: w.fraction,
                            subtitle: tr('mylist.left', [
                              formatDuration(Duration(
                                  milliseconds: (w.durMs - w.posMs).clamp(0, 1 << 40)))
                            ]),
                            onTap: () => playFullscreen(context, w.item,
                                [for (final x in cont) x.item]),
                            onLongPress: () => app.clearProgress(w.item),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (live.isNotEmpty) ...[
                SliverToBoxAdapter(child: title(tr('mylist.favChannels'))),
                SliverFixedExtentList(
                  itemExtent: kChannelTileHeight,
                  delegate: SliverChildBuilderDelegate(
                    childCount: live.length,
                    (context, i) => ChannelTile(
                      channel: live[i],
                      number: i + 1,
                      nowMs: nowMs,
                      now: app.epg.nowNext(live[i], nowMs).$1,
                      favorite: true,
                      onFavorite: () => app.toggleFavorite(live[i]),
                      onTap: () => openItem(context, live[i], live),
                      onLongPress: () => showChannelMenu(context, live[i], live),
                    ),
                  ),
                ),
              ],
              if (rems.isNotEmpty) ...[
                SliverToBoxAdapter(child: title(tr('mylist.reminders'))),
                SliverList.builder(
                  itemCount: rems.length,
                  itemBuilder: (context, i) {
                    final r = rems[i];
                    return ListTile(
                      leading: ChannelLogo(url: r.logo, name: r.channelName),
                      title: Text(r.title),
                      subtitle: Text('${r.channelName} · ${dayTime(r.start)}'),
                      trailing: IconButton(
                        tooltip: tr('rem.remove'),
                        icon: const Icon(Icons.notifications_off_outlined),
                        onPressed: () => reminders.remove(r),
                      ),
                    );
                  },
                ),
              ],
              if (vod.isNotEmpty) ...[
                SliverToBoxAdapter(child: title(tr('mylist.favVod'))),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 170,
                      childAspectRatio: 0.58,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: vod.length,
                    itemBuilder: (context, i) => PosterCard(
                      item: vod[i],
                      favorite: true,
                      progress: app.progressOf(vod[i])?.fraction,
                      onTap: () => openItem(context, vod[i], vod),
                      onLongPress: () => showVodMenu(context, vod[i]),
                    ),
                  ),
                ),
              ],
              if (recent.isNotEmpty) ...[
                SliverToBoxAdapter(child: title(tr('mylist.recent'))),
                SliverFixedExtentList(
                  itemExtent: kChannelTileHeight,
                  delegate: SliverChildBuilderDelegate(
                    childCount: recent.length,
                    (context, i) => ChannelTile(
                      channel: recent[i],
                      nowMs: nowMs,
                      favorite: app.isFavorite(recent[i]),
                      onTap: () => openItem(context, recent[i], recent),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('tab.mylist')),
        automaticallyImplyLeading: standalone,
      ),
      body: content,
    );
  }
}

// ------------------------------------------------------------ StatusView

class _StatusView extends StatelessWidget {
  final AppState app;
  const _StatusView({required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (app.active == null) {
      return Center(child: Text(tr('status.addSource')));
    }
    if (app.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(tr('status.loading', [app.active!.name])),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(app.error ?? tr('status.empty'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: app.refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr('common.retry')),
            ),
          ],
        ),
      ),
    );
  }
}
