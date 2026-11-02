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
      body: rec.items.isEmpty && rec.rules.isEmpty
          ? Column(
              children: [
                const _StorageBar(),
                Expanded(
                  child: Center(
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
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const _StorageBar(),
                const _OnTimeHint(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                      tr(Platform.isAndroid
                          ? 'rec.keepOpenAndroid'
                          : Platform.isWindows
                              ? 'rec.keepOpenWindows'
                              : Platform.isIOS
                                  ? 'rec.keepOpenIos'
                                  : 'rec.keepOpen'),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                if (rec.rules.isNotEmpty) ...[
                  title(tr('rec.series')),
                  for (final r in rec.rules) _RuleTile(r),
                ],
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

/// Espace disque restant pour les enregistrements.
class _StorageBar extends StatefulWidget {
  const _StorageBar();

  @override
  State<_StorageBar> createState() => _StorageBarState();
}

class _StorageBarState extends State<_StorageBar> {
  ({int free, int total, int used})? _s;
  int _lastUsed = -1;
  DateTime _at = DateTime(2000);

  void _refresh(RecordingService rec) {
    final used = rec.items.fold<int>(0, (a, r) => a + r.bytes);
    // Pas plus d'une mesure toutes les 20 s pendant un enregistrement.
    if (used == _lastUsed ||
        DateTime.now().difference(_at) < const Duration(seconds: 20) &&
            _s != null) {
      return;
    }
    _lastUsed = used;
    _at = DateTime.now();
    rec.storage().then((v) {
      if (mounted) setState(() => _s = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingService>();
    _refresh(rec);
    final s = _s;
    final theme = Theme.of(context);
    if (s == null) return const SizedBox(height: 8);
    final known = s.total > 0;
    final usedRatio = known ? 1 - s.free / s.total : 0.0;
    final low = known && (s.free < (2 << 30) || s.free / s.total < 0.05);
    final color = low ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sd_storage_rounded, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    known
                        ? tr('rec.storageFree', [formatBytes(s.free)])
                        : tr('rec.storageUnknown'),
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
                if (known)
                  Text(tr('rec.storageOf', [formatBytes(s.total)]),
                      style: theme.textTheme.bodySmall),
              ],
            ),
            if (known) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: usedRatio.clamp(0.0, 1.0),
                  minHeight: 8,
                  color: color,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              tr('rec.storageUsed', [formatBytes(s.used)]) +
                  (known
                      ? ' · ${tr('rec.storageHours', [(s.free / (3 << 30)).floor()])}'
                      : ''),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (low) ...[
              const SizedBox(height: 6),
              Text(tr('rec.storageLow'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Android 12+ : proposer l'autorisation pour demarrer a l'heure exacte.
class _OnTimeHint extends StatefulWidget {
  const _OnTimeHint();

  @override
  State<_OnTimeHint> createState() => _OnTimeHintState();
}

class _OnTimeHintState extends State<_OnTimeHint> with WidgetsBindingObserver {
  bool _ok = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await context.read<RecordingService>().canStartOnTime();
    if (mounted && ok != _ok) setState(() => _ok = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_ok) return const SizedBox.shrink();
    final rec = context.read<RecordingService>();
    if (!rec.items.any((r) => r.status == RecStatus.scheduled) &&
        rec.rules.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.alarm_rounded),
        title: Text(tr('rec.exactTitle')),
        subtitle: Text(tr('rec.exactText')),
        trailing: FilledButton.tonal(
          onPressed: rec.askStartOnTime,
          child: Text(tr('rec.exactAllow')),
        ),
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
      title: Row(children: [
        if (r.ruleId.isNotEmpty) ...[
          Icon(Icons.repeat_rounded, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
        ],
        Flexible(
            child: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
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

class _RuleTile extends StatelessWidget {
  final RecRule rule;
  const _RuleTile(this.rule);

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingService>();
    final next = rec.items
        .where((r) => r.ruleId == rule.id && r.status == RecStatus.scheduled)
        .map((r) => r.start)
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    final when = rule.mode == RecRepeat.weekly
        ? tr('rec.seriesWeekly', [
            weekdayLong(rule.weekday),
            '${(rule.minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(rule.minuteOfDay % 60).toString().padLeft(2, '0')}',
            rule.channel.name,
          ])
        : tr('rec.seriesEvery', [rule.channel.name]);
    final nextText = next != null
        ? tr('rec.seriesNext', [dayTime(next)])
        : (rule.mode == RecRepeat.everyAiring ? tr('rec.seriesGuideHint') : '');
    return ListTile(
      leading: Stack(clipBehavior: Clip.none, children: [
        ChannelLogo(url: rule.channel.logo, name: rule.channel.name),
        const Positioned(
            right: -6,
            bottom: -6,
            child: Icon(Icons.repeat_rounded, size: 18, color: Colors.redAccent)),
      ]),
      title: Text(rule.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(nextText.isEmpty ? when : '$when\n$nextText'),
      isThreeLine: nextText.isNotEmpty,
      trailing: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text(tr('rec.seriesStop')),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(tr('rec.seriesStopQ')),
              content: Text('${rule.title}\n\n${tr('rec.seriesStopText')}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(tr('common.cancel'))),
                FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(tr('rec.seriesStop'))),
              ],
            ),
          );
          if (ok == true) rec.removeRule(rule);
        },
      ),
    );
  }
}
