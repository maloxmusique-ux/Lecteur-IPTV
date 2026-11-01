import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../player/player_engine.dart';
import '../services/xtream_api.dart';
import '../state/app_state.dart';
import 'player_screen.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.series.name)),
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
                  const Text('Aucun épisode disponible.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(_load),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }
          final seasons = snap.data!;
          return DefaultTabController(
            length: seasons.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final s in seasons.keys) Tab(text: s)],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final eps in seasons.values)
                        ListView.builder(
                          itemCount: eps.length,
                          itemExtent: 76,
                          itemBuilder: (context, i) {
                            final e = eps[i];
                            return ListTile(
                              leading: ChannelLogo(
                                url: e.logo,
                                name: e.name,
                                width: 96,
                                height: 54,
                                fit: BoxFit.cover,
                              ),
                              title: Text(e.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              onTap: () {
                                context.read<PlayerEngine>().play(e, queue: eps);
                                context.read<AppState>().markWatched(e);
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => const PlayerScreen()));
                              },
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
