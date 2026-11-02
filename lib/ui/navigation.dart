import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../player/player_engine.dart';
import '../state/app_state.dart';
import 'details_screen.dart';
import 'player_screen.dart';
import 'series_screen.dart';
import 'subscription_screen.dart';
import 'widgets/pin_dialog.dart';

const double kWideBreakpoint = 900;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;

/// Ouvre une entree selon son type et la mise en page.
///
/// [inlinePreview] : l'ecran a un apercu video (liste des chaines sur
/// telephone) ; 1er toucher = apercu, 2e toucher = plein ecran.
Future<void> openItem(BuildContext context, Channel c, List<Channel> queue,
    {bool inlinePreview = false}) async {
  final engine = context.read<PlayerEngine>();
  final app = context.read<AppState>();
  final wide = isWide(context) || inlinePreview;

  if (!app.canSee(c)) {
    if (!await askUnlock(context)) return;
    if (!context.mounted) return;
  }

  if (c.type == ContentType.series && c.seriesId.isNotEmpty) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: c)));
    return;
  }

  // Films Xtream : fiche detaillee (affiche, resume, reprise).
  if (c.type == ContentType.movie &&
      c.id.startsWith('vod_') &&
      app.active?.kind == SourceKind.xtream) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MovieScreen(movie: c, queue: queue)));
    return;
  }

  if (c.type == ContentType.live && wide) {
    if (!await ensureLicensed(context) || !context.mounted) return;
    // Desktop/TV : 1er clic = apercu, 2e clic = plein ecran (sans recharger).
    if (engine.current?.id == c.id) {
      Navigator.of(context).push(playerRoute(stopOnExit: false));
    } else {
      engine.play(c, queue: queue);
      app.markWatched(c);
    }
    return;
  }

  await playFullscreen(context, c, queue);
}

/// Lance la lecture en plein ecran, avec proposition de reprise des films.
Future<void> playFullscreen(BuildContext context, Channel c,
    List<Channel> queue, {bool askResume = true, Duration? startAt}) async {
  if (!await ensureLicensed(context) || !context.mounted) return;
  final engine = context.read<PlayerEngine>();
  final app = context.read<AppState>();
  if (askResume && c.type != ContentType.live) {
    final p = app.progressOf(c);
    if (p != null && p.resumable) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(c.name),
          content: Text(tr('resume.question',
              [formatDuration(Duration(milliseconds: p.posMs))])),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('resume.restart')),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('resume.resume')),
            ),
          ],
        ),
      );
      if (choice == null) return;
      if (choice) startAt = Duration(milliseconds: p.posMs);
    }
  }
  if (!context.mounted) return;
  engine.play(c, queue: queue, startAt: startAt);
  app.markWatched(c);
  Navigator.of(context).push(playerRoute(stopOnExit: true));
}

Route<void> playerRoute({required bool stopOnExit}) => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (_, _, _) => PlayerScreen(stopOnExit: stopOnExit),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
}
