import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../player/player_engine.dart';
import '../state/app_state.dart';
import 'widgets/channel_logo.dart';

/// Lecteur plein ecran avec interface superposee.
///
/// Raccourcis : Haut/Bas ou PageUp/PageDown = zapping, Gauche/Droite = -10s/+10s,
/// Espace = pause, F = plein ecran, M = muet, Echap = retour.
/// Mobile : glisser verticalement pour zapper, toucher pour l'interface.
class PlayerScreen extends StatefulWidget {
  /// Arrete la lecture en quittant (vrai sur mobile, faux si apercu).
  final bool stopOnExit;
  const PlayerScreen({super.key, this.stopOnExit = true});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final PlayerEngine engine = context.read<PlayerEngine>();
  final FocusNode _focus = FocusNode();
  bool _overlay = true;
  bool _desktopFullscreen = false;
  Timer? _hide;
  String? _lastId;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_mobile) defaultEnterNativeFullscreen();
    engine.addListener(_onEngine);
    _lastId = engine.current?.id;
    _scheduleHide();
  }

  void _onEngine() {
    final id = engine.current?.id;
    if (id != _lastId) {
      _lastId = id;
      _showOverlay(); // Affiche le bandeau d'info a chaque zapping.
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  void _showOverlay() {
    if (!mounted) return;
    setState(() => _overlay = true);
    _scheduleHide();
  }

  void _toggleOverlay() {
    setState(() => _overlay = !_overlay);
    if (_overlay) _scheduleHide();
  }

  Future<void> _toggleDesktopFullscreen() async {
    if (_mobile) return;
    _desktopFullscreen = !_desktopFullscreen;
    _desktopFullscreen
        ? await defaultEnterNativeFullscreen()
        : await defaultExitNativeFullscreen();
    setState(() {});
  }

  @override
  void dispose() {
    _hide?.cancel();
    engine.removeListener(_onEngine);
    if (_mobile || _desktopFullscreen) defaultExitNativeFullscreen();
    if (widget.stopOnExit) engine.stop();
    _focus.dispose();
    super.dispose();
  }

  bool get _isLive => engine.current?.type == ContentType.live;

  Future<void> _seek(int seconds) async {
    final p = engine.player;
    final pos = p.state.position + Duration(seconds: seconds);
    await p.seek(pos < Duration.zero ? Duration.zero : pos);
    _showOverlay();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.pageUp ||
        k == LogicalKeyboardKey.channelUp) {
      engine.previous();
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.channelDown) {
      engine.next();
    } else if (k == LogicalKeyboardKey.arrowLeft && !_isLive) {
      _seek(-10);
    } else if (k == LogicalKeyboardKey.arrowRight && !_isLive) {
      _seek(10);
    } else if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      engine.player.playOrPause();
      _showOverlay();
    } else if (k == LogicalKeyboardKey.keyF) {
      _toggleDesktopFullscreen();
    } else if (k == LogicalKeyboardKey.keyM) {
      final v = engine.player.state.volume;
      engine.player.setVolume(v > 0 ? 0 : 100);
      _showOverlay();
    } else if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter) {
      _toggleOverlay();
    } else if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack) {
      if (_desktopFullscreen) {
        _toggleDesktopFullscreen();
      } else {
        Navigator.of(context).maybePop();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: (_) {
            if (!_overlay) _showOverlay();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleOverlay,
            onDoubleTap: _toggleDesktopFullscreen,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -300) engine.next();
              if (v > 300) engine.previous();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // RepaintBoundary : la video ne force jamais le repaint de l'UI.
                RepaintBoundary(
                  child: Video(
                    controller: engine.video,
                    controls: NoVideoControls,
                    fill: Colors.black,
                    filterQuality: FilterQuality.low,
                  ),
                ),
                const Center(child: _BufferingIndicator()),
                AnimatedOpacity(
                  opacity: _overlay ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_overlay,
                    child: _Overlay(
                      onUserAction: _scheduleHide,
                      onFullscreen: _mobile ? null : _toggleDesktopFullscreen,
                      fullscreen: _desktopFullscreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BufferingIndicator extends StatelessWidget {
  const _BufferingIndicator();

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PlayerEngine>();
    return StreamBuilder<bool>(
      stream: engine.player.stream.buffering,
      initialData: engine.player.state.buffering,
      builder: (_, snap) {
        if (engine.lastError != null && engine.current != null) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Flux indisponible, nouvelle tentative...',
              style: TextStyle(color: Colors.white),
            ),
          );
        }
        return snap.data == true
            ? const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : const SizedBox.shrink();
      },
    );
  }
}

class _Overlay extends StatelessWidget {
  final VoidCallback onUserAction;
  final VoidCallback? onFullscreen;
  final bool fullscreen;

  const _Overlay({
    required this.onUserAction,
    required this.onFullscreen,
    required this.fullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PlayerEngine>();
    final app = context.watch<AppState>();
    final c = engine.current;
    final theme = Theme.of(context);
    if (c == null) return const SizedBox.shrink();
    final live = c.type == ContentType.live;

    return Stack(
      children: [
        // Degrades haut et bas.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xE6000000),
                ],
                stops: [0, 0.25, 0.55, 1],
              ),
            ),
          ),
        ),
        // Barre du haut.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Pistes audio et sous-titres',
                  icon: const Icon(Icons.subtitles_outlined),
                  color: Colors.white,
                  onPressed: () {
                    onUserAction();
                    _showTracks(context, engine.player);
                  },
                ),
                IconButton(
                  tooltip: 'Favori',
                  icon: Icon(app.isFavorite(c)
                      ? Icons.star_rounded
                      : Icons.star_border_rounded),
                  color: app.isFavorite(c) ? Colors.amber : Colors.white,
                  onPressed: () {
                    onUserAction();
                    app.toggleFavorite(c);
                  },
                ),
                if (onFullscreen != null)
                  IconButton(
                    tooltip: 'Plein ecran (F)',
                    icon: Icon(fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded),
                    color: Colors.white,
                    onPressed: onFullscreen,
                  ),
              ],
            ),
          ),
        ),
        // Bandeau du bas.
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ChannelLogo(
                          url: c.logo, name: c.name, width: 56, height: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                            if (live) _EpgLine(channel: c),
                          ],
                        ),
                      ),
                      if (engine.queue.length > 1) ...[
                        IconButton.filledTonal(
                          tooltip: 'Precedent',
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: () {
                            onUserAction();
                            engine.previous();
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      _PlayPause(onUserAction: onUserAction),
                      if (engine.queue.length > 1) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Suivant',
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: () {
                            onUserAction();
                            engine.next();
                          },
                        ),
                      ],
                    ],
                  ),
                  if (!live) ...[
                    const SizedBox(height: 8),
                    _SeekBar(onUserAction: onUserAction),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showTracks(BuildContext context, Player player) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final tracks = player.state.tracks;
        final track = player.state.track;
        String label(dynamic t) {
          final parts = [t.title, t.language]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toList();
          if (t.id == 'auto') return 'Automatique';
          if (t.id == 'no') return 'Desactive';
          return parts.isEmpty ? 'Piste ${t.id}' : parts.join(' · ');
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Audio')),
              for (final t in tracks.audio)
                ListTile(
                  leading: Icon(t.id == track.audio.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded),
                  title: Text(label(t)),
                  onTap: () {
                    player.setAudioTrack(t);
                    Navigator.pop(context);
                  },
                ),
              const ListTile(title: Text('Sous-titres')),
              for (final t in tracks.subtitle)
                ListTile(
                  leading: Icon(t.id == track.subtitle.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded),
                  title: Text(label(t)),
                  onTap: () {
                    player.setSubtitleTrack(t);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EpgLine extends StatelessWidget {
  final Channel channel;
  const _EpgLine({required this.channel});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ValueListenableBuilder<int>(
      valueListenable: app.minuteTick,
      builder: (context, _, _) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final (cur, next) = app.epg.nowNext(channel, nowMs);
        if (cur == null && next == null) return const SizedBox.shrink();
        final style = Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Colors.white70);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cur != null) ...[
              const SizedBox(height: 2),
              Text('${_hm(cur.start)}  ${cur.title}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              SizedBox(
                width: 260,
                child: LinearProgressIndicator(
                  value: cur.progress(nowMs),
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                ),
              ),
            ],
            if (next != null) ...[
              const SizedBox(height: 4),
              Text('Ensuite ${_hm(next.start)}  ${next.title}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ],
          ],
        );
      },
    );
  }
}

String _hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _PlayPause extends StatelessWidget {
  final VoidCallback onUserAction;
  const _PlayPause({required this.onUserAction});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerEngine>().player;
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (_, snap) => IconButton.filled(
        iconSize: 30,
        tooltip: 'Lecture / pause (Espace)',
        icon: Icon(snap.data == true
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded),
        onPressed: () {
          onUserAction();
          player.playOrPause();
        },
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  final VoidCallback onUserAction;
  const _SeekBar({required this.onUserAction});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerEngine>().player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snap) {
        final dur = player.state.duration;
        final pos = snap.data ?? Duration.zero;
        final max = dur.inMilliseconds.toDouble();
        final value = (_drag ?? pos.inMilliseconds.toDouble())
            .clamp(0.0, max <= 0 ? 1.0 : max);
        const white = TextStyle(color: Colors.white70);
        return Row(
          children: [
            Text(_fmt(Duration(milliseconds: value.round())), style: white),
            Expanded(
              child: Slider(
                value: value,
                max: max <= 0 ? 1 : max,
                onChanged: max <= 0
                    ? null
                    : (v) {
                        widget.onUserAction();
                        setState(() => _drag = v);
                      },
                onChangeEnd: (v) {
                  player.seek(Duration(milliseconds: v.round()));
                  setState(() => _drag = null);
                },
              ),
            ),
            Text(_fmt(dur), style: white),
          ],
        );
      },
    );
  }
}
