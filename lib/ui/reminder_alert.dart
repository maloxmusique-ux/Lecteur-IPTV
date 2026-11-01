import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../player/player_engine.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import 'navigation.dart';
import 'widgets/channel_logo.dart';

/// Alerte affichee quand une emission rappelee va commencer.
/// Avec le changement automatique, la chaine s'ouvre apres 10 secondes.
Future<void> showReminderAlert(NavigatorState nav, Reminder r) async {
  final ctx = nav.overlay?.context ?? nav.context;
  final watch = await showDialog<bool>(
    context: ctx,
    builder: (_) => _ReminderDialog(reminder: r),
  );
  if (watch != true || !ctx.mounted) return;
  final app = ctx.read<AppState>();
  if (app.active?.id != r.sourceId) {
    final src = app.sources.where((s) => s.id == r.sourceId).firstOrNull;
    if (src == null) return;
    await app.selectSource(src);
  }
  final c = app.channelById(r.channelId);
  if (c == null || !ctx.mounted) return;
  final engine = ctx.read<PlayerEngine>();
  final queue = app.visibleItems(ContentType.live).toList();
  if (engine.current?.id != c.id) {
    engine.play(c, queue: queue);
    app.markWatched(c);
  }
  nav.push(playerRoute(stopOnExit: !isWide(ctx)));
}

class _ReminderDialog extends StatefulWidget {
  final Reminder reminder;
  const _ReminderDialog({required this.reminder});

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  Timer? _t;
  int _left = 10;
  late final bool _auto = context.read<Settings>().reminderAutoSwitch;

  @override
  void initState() {
    super.initState();
    if (_auto) {
      _t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _left--);
        if (_left <= 0) {
          _t?.cancel();
          Navigator.pop(context, true);
        }
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final started = DateTime.now().millisecondsSinceEpoch >= r.start;
    return AlertDialog(
      icon: const Icon(Icons.notifications_active_rounded, size: 36),
      title: Text(r.title, textAlign: TextAlign.center),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChannelLogo(url: r.logo, name: r.channelName),
          const SizedBox(width: 12),
          Flexible(
            child: Text(started
                ? tr('rem.startedOn', [r.channelName])
                : tr('rem.startsOn', [r.channelName, hm(r.start)])),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('common.ignore')),
        ),
        FilledButton.icon(
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_auto
              ? tr('rem.watchIn', [_left])
              : tr('common.watch')),
        ),
      ],
    );
  }
}
