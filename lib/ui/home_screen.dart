import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../player/player_engine.dart';
import '../state/app_state.dart';
import 'player_screen.dart';
import 'series_screen.dart';
import 'sources_screen.dart';
import 'widgets/channel_logo.dart';
import 'widgets/channel_tile.dart';

const double kWideBreakpoint = 900;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _destinations = [
    (Icons.live_tv_outlined, Icons.live_tv_rounded, 'TV'),
    (Icons.movie_outlined, Icons.movie_rounded, 'Films'),
    (Icons.video_library_outlined, Icons.video_library_rounded, 'Séries'),
    (Icons.star_border_rounded, Icons.star_rounded, 'Favoris'),
    (Icons.settings_input_antenna_outlined, Icons.settings_input_antenna,
        'Sources'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    final noSource = app.sources.isEmpty;
    final tab = noSource ? 4 : _tab;

    final body = IndexedStack(
      index: tab,
      children: const [
        BrowseView(type: ContentType.live, key: PageStorageKey('live')),
        BrowseView(type: ContentType.movie, key: PageStorageKey('movie')),
        BrowseView(type: ContentType.series, key: PageStorageKey('series')),
        FavoritesView(),
        SourcesView(),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: tab,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _tab = i),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.play_circle_fill_rounded,
                    size: 36, color: Theme.of(context).colorScheme.primary),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.$1),
                    selectedIcon: Icon(d.$2),
                    label: Text(d.$3),
                  ),
              ],
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
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.$1),
              selectedIcon: Icon(d.$2),
              label: d.$3,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Actions

/// Ouvre une entree selon son type et la mise en page.
void openItem(BuildContext context, Channel c, List<Channel> queue) {
  final engine = context.read<PlayerEngine>();
  final app = context.read<AppState>();
  final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

  if (c.type == ContentType.series && c.seriesId.isNotEmpty) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SeriesScreen(series: c)));
    return;
  }

  if (c.type == ContentType.live && wide) {
    // Desktop/TV : 1er clic = apercu, 2e clic = plein ecran (sans recharger).
    if (engine.current?.id == c.id) {
      Navigator.of(context).push(_playerRoute(stopOnExit: false));
    } else {
      engine.play(c, queue: queue);
      app.markWatched(c);
    }
    return;
  }

  engine.play(c, queue: queue);
  app.markWatched(c);
  Navigator.of(context).push(_playerRoute(stopOnExit: true));
}

Route<void> _playerRoute({required bool stopOnExit}) => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (_, _, _) => PlayerScreen(stopOnExit: stopOnExit),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );

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
  Catalog? _memoCatalog;
  String? _memoGroup;
  String? _memoQuery;
  List<Channel> _memo = const [];

  List<Channel> _filtered(Catalog catalog) {
    if (identical(catalog, _memoCatalog) &&
        _group == _memoGroup &&
        _query == _memoQuery) {
      return _memo;
    }
    Iterable<Channel> items = catalog.of(widget.type);
    final g = _group;
    if (g != null) {
      items = items.where((c) => (c.group.isEmpty ? 'Sans catégorie' : c.group) == g);
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final words = q.split(RegExp(r'\s+'));
      items = items.where((c) => words.every(c.searchKey.contains));
    }
    _memoCatalog = catalog;
    _memoGroup = _group;
    _memoQuery = _query;
    return _memo = items.toList(growable: false);
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String get _title => switch (widget.type) {
        ContentType.live => 'TV en direct',
        ContentType.movie => 'Films',
        ContentType.series => 'Séries',
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    final groups = app.catalog.groups[widget.type] ?? const <String>[];
    if (_group != null && !groups.contains(_group)) _group = null;

    if (app.catalog.isEmpty) {
      return _StatusView(app: app);
    }

    final items = _filtered(app.catalog);
    final list = widget.type == ContentType.live
        ? _LiveList(items: items)
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
            width: 250,
            child: _GroupList(
              groups: groups,
              selected: _group,
              onSelect: (g) => setState(() => _group = g),
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

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          header,
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: groups.length + 1,
              itemBuilder: (_, i) {
                final g = i == 0 ? null : groups[i - 1];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(g ?? 'Tout'),
                    selected: _group == g,
                    onSelected: (_) => setState(() => _group = g),
                  ),
                );
              },
            ),
          ),
          Expanded(child: list),
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

  const _Header({
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
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  tooltip: 'Actualiser',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Rechercher',
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
  final List<String> groups;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _GroupList({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groups.length + 1,
      itemExtent: 44,
      itemBuilder: (_, i) {
        final g = i == 0 ? null : groups[i - 1];
        final sel = selected == g;
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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    g ?? 'Toutes les catégories',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                      color: sel ? scheme.onSecondaryContainer : null,
                    ),
                  ),
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
  const _LiveList({required this.items});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final currentId = context.select<PlayerEngine, String?>((e) => e.current?.id);
    if (items.isEmpty) return const Center(child: Text('Aucun résultat'));
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
                onFavorite: () => app.toggleFavorite(c),
                onTap: () => openItem(context, c, items),
              );
            },
          ),
        );
      },
    );
  }
}

class _PosterGrid extends StatelessWidget {
  final List<Channel> items;
  const _PosterGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (items.isEmpty) return const Center(child: Text('Aucun résultat'));
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
            onTap: () => openItem(context, c, items),
            onLongPress: () => app.toggleFavorite(c),
          );
        },
      ),
    );
  }
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
                          'Sélectionne une chaîne',
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
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: IconButton.filledTonal(
                                tooltip: 'Plein écran',
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
    return ValueListenableBuilder<int>(
      valueListenable: app.minuteTick,
      builder: (context, _, _) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final all = app.epg.forChannel(channel) ?? const <Programme>[];
        final upcoming = all.where((p) => p.stop > now).take(30).toList();
        if (upcoming.isEmpty) {
          return Text(
            app.epgLoading
                ? 'Chargement du guide TV...'
                : 'Pas de guide TV pour cette chaîne.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
        }
        return ListView.separated(
          itemCount: upcoming.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final p = upcoming[i];
            final live = p.start <= now;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(_hm(p.start),
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
                ],
              ),
            );
          },
        );
      },
    );
  }
}

String _hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// -------------------------------------------------------------- Favorites

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final live = app.favoriteChannels(ContentType.live);
    final vod = [
      ...app.favoriteChannels(ContentType.movie),
      ...app.favoriteChannels(ContentType.series),
    ];
    final recent = app.recentChannels();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final theme = Theme.of(context);

    if (live.isEmpty && vod.isEmpty && recent.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Ajoute des favoris avec l\'étoile (ou un appui long sur une '
            'affiche). Ils apparaîtront ici.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(t, style: theme.textTheme.titleMedium),
        );

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          if (live.isNotEmpty) ...[
            SliverToBoxAdapter(child: title('Chaînes favorites')),
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
                ),
              ),
            ),
          ],
          if (vod.isNotEmpty) ...[
            SliverToBoxAdapter(child: title('Films et séries')),
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
                  onTap: () => openItem(context, vod[i], vod),
                  onLongPress: () => app.toggleFavorite(vod[i]),
                ),
              ),
            ),
          ],
          if (recent.isNotEmpty) ...[
            SliverToBoxAdapter(child: title('Vus récemment')),
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
      ),
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
      return const Center(child: Text('Ajoute une source dans l\'onglet Sources.'));
    }
    if (app.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Chargement de ${app.active!.name}...'),
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
            Text(app.error ?? 'Cette source est vide.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: app.refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
