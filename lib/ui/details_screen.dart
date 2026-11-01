import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../services/recorder.dart';
import '../services/xtream_api.dart';
import '../state/app_state.dart';
import 'navigation.dart';
import 'widgets/channel_logo.dart';

/// Cache memoire des fiches deja chargees (ouverture instantanee).
final _cache = <String, MediaInfo>{};

/// Fiche d'un film : affiche, resume, note, acteurs, reprise.
class MovieScreen extends StatefulWidget {
  final Channel movie;
  final List<Channel> queue;
  const MovieScreen({super.key, required this.movie, this.queue = const []});

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  MediaInfo? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _info = _cache[widget.movie.id];
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>().active;
    if (s == null || s.kind != SourceKind.xtream || widget.movie.streamId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final info = await XtreamApi(s).vodInfo(widget.movie);
      _cache[widget.movie.id] = info;
      if (mounted) setState(() => _info = info);
    } catch (_) {
      // Fiche indisponible : on affiche quand meme le titre et les boutons.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final m = widget.movie;
    final info = _info ?? MediaInfo(poster: m.logo);
    final progress = app.progressOf(m);
    final resumable = progress != null && progress.resumable;
    final queue = widget.queue.isEmpty ? [m] : widget.queue;

    final actions = <Widget>[
      FilledButton.icon(
        autofocus: true,
        onPressed: () async {
          if (resumable) {
            await playFullscreen(context, m, queue, askResume: false,
                startAt: Duration(milliseconds: progress.posMs));
          } else {
            await playFullscreen(context, m, queue, askResume: false);
          }
        },
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(resumable
            ? tr('resume.resumeAt',
                [formatDuration(Duration(milliseconds: progress.posMs))])
            : tr('common.watch')),
      ),
      if (resumable)
        OutlinedButton.icon(
          onPressed: () => playFullscreen(context, m, queue, askResume: false),
          icon: const Icon(Icons.replay_rounded),
          label: Text(tr('resume.restart')),
        ),
      IconButton.outlined(
        tooltip: app.isFavorite(m) ? tr('fav.remove') : tr('fav.add'),
        onPressed: () => app.toggleFavorite(m),
        icon: Icon(
            app.isFavorite(m) ? Icons.star_rounded : Icons.star_border_rounded,
            color: app.isFavorite(m) ? Colors.amber : null),
      ),
      IconButton.outlined(
        tooltip: tr('rec.download'),
        onPressed: () {
          final s = app.active;
          if (s == null) return;
          context.read<RecordingService>().download(s, m, m.url, m.name);
          toast(context, tr('rec.downloadStarted'));
        },
        icon: const Icon(Icons.download_rounded),
      ),
      if (info.trailer.isNotEmpty)
        IconButton.outlined(
          tooltip: tr('details.trailer'),
          onPressed: () => launchUrl(Uri.parse(info.trailer),
              mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.smart_display_outlined),
        ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: DetailsHeader(
              title: m.name,
              info: info,
              loading: _loading,
              actions: actions,
              progress: progress?.fraction,
            ),
          ),
          SliverToBoxAdapter(child: DetailsBody(info: info)),
        ],
      ),
    );
  }
}

/// En-tete commun des fiches : image de fond, affiche, titre, infos, boutons.
class DetailsHeader extends StatelessWidget {
  final String title;
  final MediaInfo info;
  final bool loading;
  final List<Widget> actions;
  final double? progress;

  const DetailsHeader({
    super.key,
    required this.title,
    required this.info,
    required this.actions,
    this.loading = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = isWide(context);
    final posterW = wide ? 180.0 : 110.0;
    final meta = [
      if (info.year.isNotEmpty) info.year,
      if (info.duration != null) _dur(info.duration!),
      if (info.genre.isNotEmpty) info.genre,
    ].join('  ·  ');
    final bg = info.backdrop.isNotEmpty ? info.backdrop : info.poster;

    return Stack(
      children: [
        if (bg.isNotEmpty)
          Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: Image.network(bg,
                  fit: BoxFit.cover,
                  cacheWidth: 900,
                  errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.scaffoldBackgroundColor.withValues(alpha: 0.3),
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackButton(),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          ChannelLogo(
                            url: info.poster,
                            name: title,
                            width: posterW,
                            height: posterW * 1.5,
                            fit: BoxFit.cover,
                            radius: 12,
                          ),
                          if (progress != null && progress! > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                  value: progress, minHeight: 4),
                            ),
                        ],
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: (wide
                                        ? theme.textTheme.headlineMedium
                                        : theme.textTheme.titleLarge)
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            if (meta.isNotEmpty)
                              Text(meta,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant)),
                            if (info.rating > 0) ...[
                              const SizedBox(height: 8),
                              _Rating(info.rating),
                            ],
                            if (loading) ...[
                              const SizedBox(height: 12),
                              const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            ],
                            const SizedBox(height: 18),
                            Wrap(spacing: 10, runSpacing: 10, children: actions),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _dur(Duration d) =>
      d.inHours > 0 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';
}

/// Resume, realisation et distribution.
class DetailsBody extends StatelessWidget {
  final MediaInfo info;
  const DetailsBody({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.plot.isNotEmpty) ...[
              Text(info.plot, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
            ],
            if (info.director.isNotEmpty) ...[
              Text(tr('details.director'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(info.director, style: muted),
              const SizedBox(height: 12),
            ],
            if (info.cast.isNotEmpty) ...[
              Text(tr('details.cast'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(info.cast, style: muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _Rating extends StatelessWidget {
  final double rating;
  const _Rating(this.rating);

  @override
  Widget build(BuildContext context) {
    // Les fournisseurs donnent la note sur 10 (parfois sur 5).
    final on10 = rating > 5 ? rating : rating * 2;
    final stars = on10 / 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            stars >= i
                ? Icons.star_rounded
                : (stars >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_border_rounded),
            size: 20,
            color: Colors.amber,
          ),
        const SizedBox(width: 6),
        Text(on10.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const Text(' / 10'),
      ],
    );
  }
}
