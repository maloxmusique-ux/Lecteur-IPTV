import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../services/recorder.dart';
import '../state/app_state.dart';
import 'navigation.dart';
import 'sources_screen.dart' show showSourceEditor;
import 'widgets/channel_logo.dart';

/// Ce que l'accueil peut ouvrir.
enum LauncherTarget {
  live,
  guide,
  movies,
  series,
  mylist,
  recordings,
  multi,
  sources,
  settings,
  reload,
}

/// Accueil : on choisit d'abord ce qu'on veut (TV, guide, films...).
class LauncherView extends StatelessWidget {
  final ValueChanged<LauncherTarget> onOpen;
  const LauncherView({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rec = context.select<RecordingService, int>((r) => r.activeCount);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1100 ? 4 : (width >= 700 ? 3 : 2);
    final recent = app.recentChannels().take(8).toList();

    String count(ContentType t) {
      final n = app.catalog.of(t).length;
      return n == 0 ? '' : tr('launch.count.${t.name}', [n]);
    }

    final big = <_Tile>[
      _Tile(
        LauncherTarget.live,
        Icons.live_tv_rounded,
        tr('browse.live'),
        count(ContentType.live),
        const [Color(0xFF3D7BFF), Color(0xFF6A4BFF)],
      ),
      _Tile(
        LauncherTarget.guide,
        Icons.calendar_view_week_rounded,
        tr('tab.guide'),
        tr('launch.guideSub'),
        const [Color(0xFF0FA3B1), Color(0xFF1E6FD9)],
      ),
      _Tile(
        LauncherTarget.movies,
        Icons.movie_rounded,
        tr('tab.movies'),
        count(ContentType.movie),
        const [Color(0xFFE2526B), Color(0xFF9B3BD6)],
      ),
      _Tile(
        LauncherTarget.series,
        Icons.video_library_rounded,
        tr('tab.series'),
        count(ContentType.series),
        const [Color(0xFFF08A24), Color(0xFFD9467A)],
      ),
    ];
    final small = <_Tile>[
      _Tile(
        LauncherTarget.mylist,
        Icons.star_rounded,
        tr('tab.mylist'),
        '',
        const [],
      ),
      _Tile(
        LauncherTarget.recordings,
        Icons.fiber_manual_record,
        tr('tab.recordings'),
        rec > 0 ? tr('launch.recNow', [rec]) : '',
        const [],
      ),
      _Tile(
        LauncherTarget.multi,
        Icons.grid_view_rounded,
        tr('multi.title'),
        '',
        const [],
      ),
      _Tile(
        LauncherTarget.sources,
        Icons.settings_input_antenna,
        tr('tab.sources'),
        '',
        const [],
      ),
      _Tile(
        LauncherTarget.settings,
        Icons.settings_rounded,
        tr('tab.settings'),
        '',
        const [],
      ),
      _Tile(
        LauncherTarget.reload,
        Icons.restart_alt_rounded,
        tr('reload.title'),
        '',
        const [],
      ),
    ];

    return Stack(
      children: [
        _body(context, app, theme, cols, recent, big, small),
        // Ajouter une liste de lecture : le « + » que tout le monde connait.
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'launcher_add',
            tooltip: tr('src.addTitle'),
            onPressed: () => showSourceEditor(context),
            child: const Icon(Icons.add_rounded, size: 30),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, AppState app, ThemeData theme, int cols,
      List<Channel> recent, List<_Tile> big, List<_Tile> small) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Image.asset(
                    'assets/icon/icon.png',
                    width: 36,
                    height: 36,
                    cacheWidth: 108,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Canalix',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (app.loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverGrid.count(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: cols == 2 ? 1.15 : 1.5,
              children: [
                for (final (i, t) in big.indexed)
                  _BigTile(
                    tile: t,
                    autofocus: i == 0,
                    onTap: () => onOpen(t.target),
                  ),
              ],
            ),
          ),
          if (recent.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  tr('launch.resume'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 112,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: recent.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final c = recent[i];
                    return SizedBox(
                      width: 150,
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => openItem(
                            context,
                            c,
                            c.type == ContentType.live
                                ? app.visibleItems(ContentType.live).toList()
                                : [c],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ChannelLogo(
                                  url: c.logo,
                                  name: c.name,
                                  width: 64,
                                  height: 44,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  c.name,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            sliver: SliverGrid.count(
              crossAxisCount: cols == 2 ? 3 : 6,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: cols == 2 ? 1.05 : 1.9,
              children: [
                for (final t in small)
                  _SmallTile(tile: t, onTap: () => onOpen(t.target)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  final LauncherTarget target;
  final IconData icon;
  final String title;
  final String sub;
  final List<Color> colors;
  const _Tile(this.target, this.icon, this.title, this.sub, this.colors);
}

class _BigTile extends StatelessWidget {
  final _Tile tile;
  final bool autofocus;
  final VoidCallback onTap;
  const _BigTile({
    required this.tile,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: tile.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          autofocus: autofocus,
          onTap: onTap,
          focusColor: Colors.white24,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tile.icon, size: 40, color: Colors.white),
                const Spacer(),
                Text(
                  tile.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (tile.sub.isNotEmpty)
                  Text(
                    tile.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallTile extends StatelessWidget {
  final _Tile tile;
  final VoidCallback onTap;
  const _SmallTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rec = tile.target == LauncherTarget.recordings && tile.sub.isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tile.icon,
                size: 28,
                color: rec ? Colors.redAccent : theme.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                tile.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              if (tile.sub.isNotEmpty)
                Text(
                  tile.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.redAccent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
