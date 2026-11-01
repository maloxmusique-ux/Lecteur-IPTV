import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../services/recorder.dart';
import '../services/xtream_api.dart';
import '../state/app_state.dart';
import 'details_screen.dart';
import 'navigation.dart';
import 'widgets/channel_logo.dart';

/// Fiche d'une serie Xtream : resume, saisons et episodes.
class SeriesScreen extends StatefulWidget {
  final Channel series;
  const SeriesScreen({super.key, required this.series});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  late Future<SeriesDetails> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final source = context.read<AppState>().active!;
    _future = XtreamApi(source).seriesDetails(widget.series);
  }

  /// Episode a reprendre : le dernier commence, sinon le premier.
  (Channel, Duration?)? _next(AppState app, SeriesDetails d) {
    Channel? best;
    var latest = 0;
    Duration? at;
    final all = [for (final l in d.seasons.values) ...l];
    for (var i = 0; i < all.length; i++) {
      final p = app.progressOf(all[i]);
      if (p == null || p.updatedMs <= latest) continue;
      latest = p.updatedMs;
      if (p.resumable) {
        best = all[i];
        at = Duration(milliseconds: p.posMs);
      } else {
        best = i + 1 < all.length ? all[i + 1] : all[i];
        at = null;
      }
    }
    if (best == null && all.isNotEmpty) best = all.first;
    return best == null ? null : (best, at);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = widget.series;
    return Scaffold(
      body: FutureBuilder<SeriesDetails>(
        future: _future,
        builder: (context, snap) {
          final d = snap.data;
          final info = d?.info ?? MediaInfo(poster: s.logo);
          final next = d == null ? null : _next(app, d);
          List<Channel> queueOf(Channel e) {
            for (final l in d?.seasons.values ?? const <List<Channel>>[]) {
              if (l.any((x) => x.id == e.id)) return l;
            }
            return [e];
          }

          final actions = <Widget>[
            if (next != null)
              FilledButton.icon(
                autofocus: true,
                onPressed: () => playFullscreen(
                    context, next.$1, queueOf(next.$1),
                    askResume: false, startAt: next.$2),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(next.$2 != null
                    ? tr('series.resumeEp', [next.$1.name])
                    : tr('series.playEp', [next.$1.name]),
                    overflow: TextOverflow.ellipsis),
              ),
            IconButton.outlined(
              tooltip: app.isFavorite(s) ? tr('fav.remove') : tr('fav.add'),
              onPressed: () => app.toggleFavorite(s),
              icon: Icon(
                  app.isFavorite(s) ? Icons.star_rounded : Icons.star_border_rounded,
                  color: app.isFavorite(s) ? Colors.amber : null),
            ),
            if (info.trailer.isNotEmpty)
              IconButton.outlined(
                tooltip: tr('details.trailer'),
                onPressed: () => launchUrl(Uri.parse(info.trailer),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.smart_display_outlined),
              ),
          ];

          final header = DetailsHeader(
            title: s.name,
            info: info,
            loading: snap.connectionState != ConnectionState.done,
            actions: actions,
          );

          if (snap.connectionState == ConnectionState.done &&
              (snap.hasError || d == null || d.seasons.isEmpty)) {
            return ListView(
              children: [
                header,
                const SizedBox(height: 24),
                Center(child: Text(tr('series.none'))),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton(
                    onPressed: () => setState(_load),
                    child: Text(tr('common.retry')),
                  ),
                ),
              ],
            );
          }
          if (d == null) {
            return ListView(children: [header]);
          }

          final seasons = d.seasons;
          final initial = next == null
              ? 0
              : seasons.values
                  .toList()
                  .indexWhere((l) => l.any((e) => e.id == next.$1.id))
                  .clamp(0, seasons.length - 1);
          return DefaultTabController(
            length: seasons.length,
            initialIndex: initial,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(child: header),
                SliverToBoxAdapter(child: DetailsBody(info: info)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeader(
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        for (final k in seasons.keys)
                          Tab(text: tr('series.season', [k])),
                      ],
                    ),
                    Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  for (final eps in seasons.values)
                    ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: eps.length,
                      itemBuilder: (context, i) =>
                          _EpisodeTile(e: eps[i], info: d.episodes[eps[i].id], queue: eps, series: s),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  final TabBar bar;
  final Color color;
  _TabsHeader(this.bar, this.color);

  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: color, child: bar);

  @override
  bool shouldRebuild(_TabsHeader old) => old.bar != bar;
}

class _EpisodeTile extends StatelessWidget {
  final Channel e;
  final MediaInfo? info;
  final List<Channel> queue;
  final Channel series;
  const _EpisodeTile({
    required this.e,
    required this.info,
    required this.queue,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final p = app.progressOf(e);
    final watched = p != null && !p.resumable && p.fraction >= 0.95;
    final dur = info?.duration;
    return InkWell(
      onTap: () => playFullscreen(context, e, queue),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              height: 79,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ChannelLogo(
                    url: e.logo,
                    name: series.name,
                    width: 140,
                    height: 79,
                    fit: BoxFit.cover,
                  ),
                  if (p != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                          value: p.fraction, minHeight: 3),
                    ),
                  if (watched)
                    const Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(Icons.check_circle_rounded,
                          color: Colors.greenAccent, size: 20),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                  if (dur != null)
                    Text(tr('common.minutes', [dur.inMinutes]),
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  if (info?.plot.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(info!.plot,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: tr('rec.download'),
              icon: const Icon(Icons.download_rounded),
              onPressed: () {
                final s = app.active;
                if (s == null) return;
                context
                    .read<RecordingService>()
                    .download(s, e, e.url, '${series.name} - ${e.name}');
                toast(context, tr('rec.downloadStarted'));
              },
            ),
          ],
        ),
      ),
    );
  }
}
