import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../services/home_recorder.dart';
import '../services/recorder.dart';
import '../services/reminders.dart';
import '../services/xtream_api.dart';
import '../state/app_state.dart';
import 'navigation.dart';
import 'widgets/channel_logo.dart';

/// Construit l'entree jouable d'un programme passe (rattrapage Xtream).
Channel? catchupChannel(AppState app, Channel c, Programme p,
    {String? serverStart}) {
  final s = app.active;
  if (s == null || s.kind != SourceKind.xtream || !c.hasArchive) return null;
  final offset = app.account?.serverOffsetMs ??
      DateTime.now().timeZoneOffset.inMilliseconds;
  final start = serverStart ?? XtreamApi.serverTime(p.start, offset);
  final url = XtreamApi(s).catchupUrl(c, start, p.duration);
  return Channel(
    id: 'cu_${c.id}_${p.start}',
    name: p.title.isEmpty ? c.name : p.title,
    url: url,
    logo: c.logo,
    group: c.name,
    type: ContentType.movie,
  );
}

/// Le programme est-il encore disponible en rattrapage ?
bool inArchive(Channel c, Programme p, int now) =>
    c.hasArchive &&
    p.start <= now &&
    p.start > now - c.archiveDays * 86400000;

/// Fiche d'une emission : description, regarder, rappel, enregistrer.
Future<void> showProgrammeSheet(
  BuildContext context,
  Channel channel,
  Programme p, {
  String? serverStart,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _ProgrammeSheet(
        channel: channel, programme: p, serverStart: serverStart, host: context),
  );
}

class _ProgrammeSheet extends StatelessWidget {
  final Channel channel;
  final Programme programme;
  final String? serverStart;

  /// Contexte de l'ecran d'origine (pour naviguer apres fermeture).
  final BuildContext host;

  const _ProgrammeSheet({
    required this.channel,
    required this.programme,
    required this.serverStart,
    required this.host,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final reminders = context.watch<ReminderService>();
    final recorder = context.watch<RecordingService>();
    final theme = Theme.of(context);
    final p = programme;
    final c = channel;
    final now = DateTime.now().millisecondsSinceEpoch;
    final source = app.active;
    final sourceId = source?.id ?? '';
    final live = p.isLive(now);
    final past = p.isPast(now);
    final future = !live && !past;
    final xtream = source?.kind == SourceKind.xtream;
    final archive = xtream && inArchive(c, p, now);
    final hasRem = reminders.has(sourceId, c, p);
    final home = context.watch<HomeClient>();
    // Ecran relie a un enregistreur maison : les enregistrements de direct
    // partent la-bas (il enregistre meme si cet ecran est eteint).
    final remote = home.paired && !context.read<HomeServer>().enabled;
    final scheduled = remote
        ? home.isScheduled(sourceId, c, p)
        : recorder.isScheduled(sourceId, c, p);
    final queue = app.visibleItems(ContentType.live).toList();

    void close() => Navigator.pop(context);

    Future<void> watchLive() async {
      close();
      await playFullscreen(host, c, queue);
    }

    Future<void> watchCatchup() async {
      final cu = catchupChannel(app, c, p, serverStart: serverStart);
      if (cu == null) return;
      close();
      await playFullscreen(host, cu, [cu]);
    }

    Future<void> toggleRecord() async {
      if (source == null) return;
      if (scheduled && remote) {
        for (final r in home.covering(sourceId, c, p).toList()) {
          await home.stop(r);
        }
        if (host.mounted) toast(host, tr('rec.cancelled'));
      } else if (scheduled) {
        for (final r in recorder.items) {
          if (r.channel.id == c.id &&
              r.kind == RecKind.live &&
              !r.finished &&
              r.start <= p.start &&
              r.stop >= p.stop - 60000) {
            recorder.stopRecording(r);
          }
        }
        toast(host, tr('rec.cancelled'));
      } else {
        final mode = await askRepeat(context, c, p);
        if (mode == null || !host.mounted) return;
        if (remote) {
          final ok = mode == RecRepeat.once
              ? await home.schedule(source, c, p)
              : await home.addRule(source, c, p, mode, app.epg);
          if (host.mounted) {
            toast(host,
                ok ? tr('home.sent', [home.name]) : tr('home.sendFailed', [home.name]));
          }
        } else if (mode == RecRepeat.once) {
          recorder.scheduleProgramme(source, c, p);
          toast(host, live ? tr('rec.started') : tr('rec.scheduled'));
        } else {
          recorder.addRule(source, c, p, mode);
          toast(host, tr('rec.seriesAdded'));
        }
      }
    }

    void download() {
      final cu = catchupChannel(app, c, p, serverStart: serverStart);
      if (cu == null || source == null) return;
      recorder.download(source, c, cu.url,
          p.title.isEmpty ? c.name : p.title);
      close();
      toast(host, tr('rec.downloadStarted'));
    }

    final minutes = p.duration.inMinutes;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChannelLogo(url: c.logo, name: c.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                if (live)
                  _Badge(text: tr('epg.live'), color: Colors.redAccent),
                if (past && archive)
                  _Badge(text: tr('catchup.badge'), color: Colors.teal),
              ],
            ),
            const SizedBox(height: 14),
            Text(p.title.isEmpty ? tr('epg.noTitle') : p.title,
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              '${dayLabel(DateTime.fromMillisecondsSinceEpoch(p.start))}  '
              '${hm(p.start)} – ${hm(p.stop)}  ·  ${tr('common.minutes', [minutes])}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (live) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: p.progress(now), minHeight: 4),
            ],
            if (p.desc.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(p.desc, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (live)
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: watchLive,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(tr('common.watch')),
                  ),
                if (live && archive)
                  OutlinedButton.icon(
                    onPressed: watchCatchup,
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(tr('catchup.fromStart')),
                  ),
                if (past && archive) ...[
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: watchCatchup,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(tr('catchup.watch')),
                  ),
                  OutlinedButton.icon(
                    onPressed: download,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(tr('rec.download')),
                  ),
                ],
                if (future)
                  FilledButton.tonalIcon(
                    autofocus: true,
                    onPressed: () async {
                      final added = await reminders.toggle(sourceId, c, p);
                      if (host.mounted) {
                        toast(host,
                            added ? tr('rem.added', [hm(p.start)]) : tr('rem.removed'));
                      }
                    },
                    icon: Icon(hasRem
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_active_outlined),
                    label: Text(hasRem ? tr('rem.remove') : tr('rem.add')),
                  ),
                if (!past)
                  OutlinedButton.icon(
                    onPressed: toggleRecord,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: scheduled ? null : Colors.redAccent),
                    icon: Icon(scheduled
                        ? Icons.cancel_outlined
                        : Icons.fiber_manual_record),
                    label: Text(scheduled
                        ? tr('rec.cancel')
                        : (live ? tr('rec.recordRest') : tr('rec.record'))),
                  ),
                if (past && !archive)
                  Text(tr('catchup.unavailable'),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            if (!past && (app.account?.maxConnections ?? 0) == 1) ...[
              const SizedBox(height: 12),
              Text(tr('rec.oneConnection'),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

/// Choix de la duree d'un enregistrement immediat.
Future<void> recordNowDialog(BuildContext context, Channel c) async {
  final app = context.read<AppState>();
  final recorder = context.read<RecordingService>();
  final source = app.active;
  if (source == null) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  final cur = app.epg.nowNext(c, now).$1;
  final choices = <(String, Duration, String?)>[
    if (cur != null)
      (
        tr('rec.untilEnd', [cur.title, hm(cur.stop)]),
        Duration(milliseconds: cur.stop - now + recorder.settings.recPadAfter * 60000),
        cur.title,
      ),
    (tr('common.minutes', [30]), const Duration(minutes: 30), null),
    (tr('common.hours', [1]), const Duration(hours: 1), null),
    (tr('common.hours', [2]), const Duration(hours: 2), null),
    (tr('common.hours', [4]), const Duration(hours: 4), null),
  ];
  final pick = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('rec.nowTitle', [c.name])),
      children: [
        for (final (i, ch) in choices.indexed)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(ch.$1),
            ),
          ),
        if ((app.account?.maxConnections ?? 0) == 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: SizedBox(
              width: 360,
              child: Text(tr('rec.oneConnection'),
                  style: Theme.of(ctx).textTheme.bodySmall),
            ),
          ),
      ],
    ),
  );
  if (pick == null || !context.mounted) return;
  final ch = choices[pick];
  final home = context.read<HomeClient>();
  if (home.paired && !context.read<HomeServer>().enabled) {
    final ok = await home.recordNow(source, c, ch.$2, title: ch.$3);
    if (context.mounted) {
      toast(context,
          ok ? tr('home.sent', [home.name]) : tr('home.sendFailed', [home.name]));
    }
    return;
  }
  recorder.recordNow(source, c, ch.$2, title: ch.$3);
  if (context.mounted) toast(context, tr('rec.started'));
}

/// Demande la frequence : une fois, chaque diffusion ou chaque semaine.
Future<RecRepeat?> askRepeat(BuildContext context, Channel c, Programme p) {
  final d = DateTime.fromMillisecondsSinceEpoch(p.start);
  final title = p.title.isEmpty ? c.name : p.title;
  Widget option(BuildContext ctx, RecRepeat m, IconData icon, String t, String sub,
          {bool autofocus = false}) =>
      ListTile(
        autofocus: autofocus,
        leading: Icon(icon, color: m == RecRepeat.once ? null : Colors.redAccent),
        title: Text(t),
        subtitle: Text(sub),
        onTap: () => Navigator.pop(ctx, m),
      );
  return showDialog<RecRepeat>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
      title: Text(tr('rec.repeatQ')),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(ctx, RecRepeat.once, Icons.looks_one_outlined,
                tr('rec.once'), tr('rec.onceSub', [dayTime(p.start)]),
                autofocus: true),
            option(ctx, RecRepeat.everyAiring, Icons.repeat_rounded,
                tr('rec.every'), tr('rec.everySub', [title, c.name])),
            option(ctx, RecRepeat.weekly, Icons.event_repeat_rounded,
                tr('rec.weekly'),
                tr('rec.weeklySub', [weekdayLong(d.weekday), hm(p.start), c.name])),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('common.cancel'))),
      ],
    ),
  );
}
