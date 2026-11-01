import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../services/recorder.dart';
import '../services/xtream_api.dart';
import '../state/app_state.dart';
import 'navigation.dart';
import 'programme_sheet.dart';
import 'widgets/channel_logo.dart';

/// Rattrapage d'une chaine Xtream : les emissions des derniers jours,
/// a regarder ou a telecharger.
class CatchupScreen extends StatefulWidget {
  final Channel channel;
  const CatchupScreen({super.key, required this.channel});

  @override
  State<CatchupScreen> createState() => _CatchupScreenState();
}

class _CatchupScreenState extends State<CatchupScreen> {
  late Future<List<CatchupItem>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final s = context.read<AppState>().active!;
    _future = XtreamApi(s).channelGuide(widget.channel);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ChannelLogo(url: c.logo, name: c.name, width: 36, height: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, overflow: TextOverflow.ellipsis),
                  Text(tr('catchup.days', [c.archiveDays]),
                      style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<CatchupItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          final items = (snap.data ?? const <CatchupItem>[])
              .where((e) =>
                  e.programme.start <= now &&
                  (e.hasArchive || inArchive(c, e.programme, now)))
              .toList()
              .reversed
              .toList();
          if (snap.hasError || items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('catchup.empty')),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(_load),
                    child: Text(tr('common.retry')),
                  ),
                ],
              ),
            );
          }
          String? lastDay;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final e = items[i];
              final p = e.programme;
              final day = dayLabel(DateTime.fromMillisecondsSinceEpoch(p.start));
              final showDay = day != lastDay;
              lastDay = day;
              final live = p.isLive(now);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDay)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(day,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: theme.colorScheme.primary)),
                    ),
                  ListTile(
                    leading: SizedBox(
                      width: 52,
                      child: Text(hm(p.start),
                          style: theme.textTheme.labelLarge),
                    ),
                    title: Text(p.title.isEmpty ? tr('epg.noTitle') : p.title),
                    subtitle: p.desc.isEmpty
                        ? Text(tr('common.minutes', [p.duration.inMinutes]))
                        : Text(p.desc,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (live)
                          Text(tr('epg.live'),
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w700)),
                        if (!live)
                          IconButton(
                            tooltip: tr('rec.download'),
                            icon: const Icon(Icons.download_rounded),
                            onPressed: () {
                              final app = context.read<AppState>();
                              final cu = catchupChannel(app, c, p,
                                  serverStart: e.serverStart);
                              if (cu == null || app.active == null) return;
                              context.read<RecordingService>().download(
                                  app.active!, c, cu.url,
                                  p.title.isEmpty ? c.name : p.title);
                              toast(context, tr('rec.downloadStarted'));
                            },
                          ),
                      ],
                    ),
                    onTap: () {
                      final app = context.read<AppState>();
                      final cu = catchupChannel(app, c, p,
                          serverStart: e.serverStart);
                      if (cu != null) playFullscreen(context, cu, [cu]);
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
