import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../services/recorder.dart';
import '../services/xtream_api.dart';
import '../state/app_state.dart';
import 'navigation.dart';
import 'widgets/channel_logo.dart';

/// Saisons et episodes d'une serie Xtream.
class SeriesScreen extends StatefulWidget {
  final Channel series;
  const SeriesScreen({super.key, required this.series});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  late Future<Map<String, List<Channel>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final source = context.read<AppState>().active!;
    _future = XtreamApi(source).seriesEpisodes(widget.series);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.series.name),
        actions: [
          IconButton(
            tooltip: app.isFavorite(widget.series) ? tr('fav.remove') : tr('fav.add'),
            icon: Icon(app.isFavorite(widget.series)
                ? Icons.star_rounded
                : Icons.star_border_rounded),
            color: app.isFavorite(widget.series) ? Colors.amber : null,
            onPressed: () => app.toggleFavorite(widget.series),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, List<Channel>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || (snap.data?.isEmpty ?? true)) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('series.none')),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(_load),
                    child: Text(tr('common.retry')),
                  ),
                ],
              ),
            );
          }
          final seasons = snap.data!;
          // Ouvre la saison du dernier episode commence.
          var initial = 0;
          var latest = 0;
          for (final (i, eps) in seasons.values.indexed) {
            for (final e in eps) {
              final p = app.progressOf(e);
              if (p != null && p.updatedMs > latest) {
                latest = p.updatedMs;
                initial = i;
              }
            }
          }
          return DefaultTabController(
            length: seasons.length,
            initialIndex: initial,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final s in seasons.keys)
                      Tab(text: tr('series.season', [s])),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final eps in seasons.values)
                        ListView.builder(
                          itemCount: eps.length,
                          itemExtent: 80,
                          itemBuilder: (context, i) {
                            final e = eps[i];
                            final p = app.progressOf(e);
                            return ListTile(
                              leading: SizedBox(
                                width: 96,
                                height: 54,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ChannelLogo(
                                      url: e.logo,
                                      name: e.name,
                                      width: 96,
                                      height: 54,
                                      fit: BoxFit.cover,
                                    ),
                                    if (p != null)
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: LinearProgressIndicator(
                                            value: p.fraction, minHeight: 3),
                                      ),
                                  ],
                                ),
                              ),
                              title: Text(e.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: p != null && !p.resumable && p.fraction >= 0.95
                                  ? Text(tr('series.watched'))
                                  : null,
                              trailing: IconButton(
                                tooltip: tr('rec.download'),
                                icon: const Icon(Icons.download_rounded),
                                onPressed: () {
                                  final s = app.active;
                                  if (s == null) return;
                                  context.read<RecordingService>().download(
                                      s, e, e.url,
                                      '${widget.series.name} - ${e.name}');
                                  toast(context, tr('rec.downloadStarted'));
                                },
                              ),
                              onTap: () => playFullscreen(context, e, eps),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
