import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../services/recorder.dart';
import 'navigation.dart';
import 'widgets/channel_logo.dart';

/// Enregistrements : en cours, prevus et termines.
class RecordingsView extends StatelessWidget {
  const RecordingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingService>();
    final theme = Theme.of(context);
    final active = rec.items.where((r) => r.active).toList();
    final scheduled =
        rec.items.where((r) => r.status == RecStatus.scheduled).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final done = rec.items.where((r) => r.finished).toList();

    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(t, style: theme.textTheme.titleMedium),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('tab.recordings')),
        actions: [
          FutureBuilder<Directory>(
            future: rec.folder(),
            builder: (context, snap) => IconButton(
              tooltip: tr('rec.folder'),
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: snap.data == null
                  ? null
                  : () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(tr('rec.folder')),
                          content: SelectableText(snap.data!.path),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(tr('common.ok')),
                            ),
                          ],
                        ),
                      ),
            ),
          ),
        ],
      ),
      body: rec.items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record_outlined,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(tr('rec.empty'), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(tr('rec.keepOpen'),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                if (active.isNotEmpty) ...[
                  title(tr('rec.inProgress')),
                  for (final r in active) _RecTile(r),
                ],
                if (scheduled.isNotEmpty) ...[
                  title(tr('rec.planned')),
                  for (final r in scheduled) _RecTile(r),
                ],
                if (done.isNotEmpty) ...[
                  title(tr('rec.finished')),
                  for (final r in done) _RecTile(r),
                ],
              ],
            ),
    );
  }
}

class _RecTile extends StatelessWidget {
  final Recording r;
  const _RecTile(this.r);

  @override
  Widget build(BuildContext context) {
    final rec = context.read<RecordingService>();
    final theme = Theme.of(context);
    final status = switch (r.status) {
      RecStatus.scheduled => tr('rec.st.scheduled', [dayTime(r.start)]),
      RecStatus.recording => r.kind == RecKind.live
          ? tr('rec.st.recording', [hm(r.stop), formatBytes(r.bytes)])
          : tr('rec.st.downloading', [formatBytes(r.bytes)]),
      RecStatus.done => '${dayTime(r.start)} · ${formatBytes(r.bytes)}',
      RecStatus.failed => tr('rec.st.failed'),
      RecStatus.cancelled => tr('rec.st.cancelled'),
    };
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          ChannelLogo(url: r.channel.logo, name: r.channel.name),
          if (r.active)
            const Positioned(
              right: -4,
              top: -4,
              child: Icon(Icons.fiber_manual_record,
                  size: 14, color: Colors.redAccent),
            ),
        ],
      ),
      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              r.title == r.channel.name ? status : '${r.channel.name} · $status',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: r.status == RecStatus.failed
                      ? theme.colorScheme.error
                      : null)),
          if (r.active) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: r.progress, minHeight: 3),
          ],
        ],
      ),
      onTap: r.path.isNotEmpty && (r.status == RecStatus.done || r.active)
          ? () => playFullscreen(context, r.playable, [r.playable])
          : null,
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'stop') rec.stopRecording(r);
          if (v == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(tr('rec.deleteQ')),
                content: Text(r.title),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(tr('common.cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(tr('common.delete'))),
                ],
              ),
            );
            if (ok == true) await rec.delete(r);
          }
          if (v == 'path' && context.mounted) {
            showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(r.title),
                content: SelectableText(r.path),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(tr('common.ok'))),
                ],
              ),
            );
          }
        },
        itemBuilder: (_) => [
          if (r.active || r.status == RecStatus.scheduled)
            PopupMenuItem(
                value: 'stop',
                child: Text(r.active ? tr('rec.stop') : tr('rec.cancel'))),
          if (r.path.isNotEmpty)
            PopupMenuItem(value: 'path', child: Text(tr('rec.showFile'))),
          PopupMenuItem(value: 'delete', child: Text(tr('common.delete'))),
        ],
      ),
    );
  }
}
