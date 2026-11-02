import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../player/player_engine.dart';
import '../services/recorder.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../services/cast.dart';
import 'cast_ui.dart';
import 'catchup_screen.dart';
import 'programme_sheet.dart';
import 'widgets/channel_logo.dart';
import 'widgets/connection_banner.dart';

const _pip = MethodChannel('streamflow/pip');

/// Lecteur plein ecran avec interface superposee.
///
/// Raccourcis : Haut/Bas ou PageUp/PageDown = zapping, Gauche/Droite = -10s/+10s
/// (aussi dans le direct grace a la pause du direct), Espace = pause,
/// F = plein ecran, M = muet, I = infos du flux, L = retour au direct,
/// chiffres = aller a une chaine, Echap = retour.
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
  bool _info = false;
  Timer? _hide;

  // Verrou d'ecran : plus aucun geste ne change la lecture.
  bool _locked = false;
  bool _lockHint = false;
  Timer? _lockTimer;

  // Nom du format affiche brievement au centre.
  String? _toast;
  Timer? _toastTimer;
  String? _lastId;

  // Saisie d'un numero de chaine a la telecommande.
  String _digits = '';
  Timer? _digitTimer;

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
      // Pendant une diffusion Chromecast, le zapping suit sur la tele.
      final cast = CastSession.instance;
      final c = engine.current;
      if (cast.active && cast.device != null && c != null) {
        engine.player.pause();
        cast.play(cast.device!, c);
      }
    }
    if (engine.current == null && mounted) {
      // Fin de la minuterie de mise en veille.
      Navigator.of(context).maybePop();
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 5), () {
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

  void _flash(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _cycleFit() {
    final s = context.read<Settings>();
    final next = VideoFit.values[(s.videoFit.index + 1) % VideoFit.values.length];
    s.update((x) => x.videoFit = next);
    _flash(fitLabel(next));
    _scheduleHide();
  }

  void _lock() {
    setState(() {
      _locked = true;
      _overlay = false;
      _info = false;
    });
    _showLockHint();
  }

  void _unlock() {
    _lockTimer?.cancel();
    setState(() {
      _locked = false;
      _lockHint = false;
    });
    _showOverlay();
  }

  void _showLockHint() {
    _lockTimer?.cancel();
    setState(() => _lockHint = true);
    _lockTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _lockHint = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _lockTimer?.cancel();
    _toastTimer?.cancel();
    _digitTimer?.cancel();
    engine.removeListener(_onEngine);
    if (_mobile || _desktopFullscreen) defaultExitNativeFullscreen();
    if (widget.stopOnExit) engine.stop();
    _focus.dispose();
    super.dispose();
  }

  bool get _isLive => engine.current?.type == ContentType.live;

  bool get _canSeekLive => context.read<Settings>().timeshift;

  Future<void> _seek(int seconds) async {
    if (_isLive && !_canSeekLive) return;
    await engine.seekBy(seconds);
    _showOverlay();
  }

  void _digit(int d) {
    _digitTimer?.cancel();
    setState(() => _digits = '$_digits$d');
    _digitTimer = Timer(const Duration(milliseconds: 1500), () {
      final n = int.tryParse(_digits);
      setState(() => _digits = '');
      final q = engine.queue;
      if (n != null && n >= 1 && n <= q.length) engine.play(q[n - 1]);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_locked) {
      _showLockHint();
      return KeyEventResult.handled;
    }
    final k = e.logicalKey;
    final digit = _digitOf(k);
    if (digit != null && _isLive) {
      _digit(digit);
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.pageUp ||
        k == LogicalKeyboardKey.channelUp) {
      engine.previous();
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.channelDown) {
      engine.next();
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.mediaRewind) {
      _seek(-10);
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaFastForward) {
      _seek(10);
    } else if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      engine.player.playOrPause();
      _showOverlay();
    } else if (k == LogicalKeyboardKey.keyF) {
      _toggleDesktopFullscreen();
    } else if (k == LogicalKeyboardKey.keyI || k == LogicalKeyboardKey.info) {
      setState(() => _info = !_info);
    } else if (k == LogicalKeyboardKey.keyL) {
      engine.goLive();
      _showOverlay();
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

  static int? _digitOf(LogicalKeyboardKey k) {
    const keys = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    const pad = [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
    ];
    final i = keys.indexOf(k);
    if (i != -1) return i;
    final j = pad.indexOf(k);
    return j == -1 ? null : j;
  }

  Future<void> _enterPip() async {
    // iPhone : le mini-lecteur passe par le lecteur Apple (PiP natif).
    if (Platform.isIOS) {
      final c = engine.current;
      if (c == null) return;
      await engine.player.pause();
      if (!mounted) return;
      await AirPlay.play(c, userAgent: context.read<AppState>().active?.userAgent ?? '');
      return;
    }
    try {
      final w = engine.player.state.width ?? 16;
      final h = engine.player.state.height ?? 9;
      await _pip.invokeMethod('enter', {'w': w, 'h': h});
      setState(() => _overlay = false);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Fenetre minuscule (image dans l'image) : video seule.
    final tiny = MediaQuery.sizeOf(context).width < 400 &&
        MediaQuery.sizeOf(context).height < 400;
    final fit = context.select<Settings, VideoFit>((s) => s.videoFit);
    return PopScope(
      // Ecran verrouille : le bouton retour ne quitte pas la lecture.
      canPop: !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _locked) _showLockHint();
      },
      child: Scaffold(
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
            onTap: _locked ? _showLockHint : _toggleOverlay,
            onDoubleTap: _locked ? null : _toggleDesktopFullscreen,
            onVerticalDragEnd: _locked
                ? null
                : (d) {
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
                    filterQuality: FilterQuality.medium,
                    fit: switch (fit) {
                      VideoFit.zoom => BoxFit.cover,
                      VideoFit.stretch => BoxFit.fill,
                      _ => BoxFit.contain,
                    },
                    aspectRatio: switch (fit) {
                      VideoFit.r169 => 16 / 9,
                      VideoFit.r43 => 4 / 3,
                      _ => null,
                    },
                  ),
                ),
                if (!tiny) const Center(child: _BufferingIndicator()),
                if (_digits.isNotEmpty)
                  Positioned(
                    top: 40,
                    right: 40,
                    child: Text(_digits,
                        style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [Shadow(blurRadius: 12)])),
                  ),
                if (!tiny)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(child: Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: CastBanner(),
                    )),
                  ),
                if (_info && !tiny)
                  Positioned(
                    top: 70,
                    right: 16,
                    child: _InfoPanel(onClose: () => setState(() => _info = false)),
                  ),
                if (!tiny)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(child: Padding(
                      padding: EdgeInsets.only(top: 90),
                      child: ConnectionLimitBanner(),
                    )),
                  ),
                if (_toast != null && !tiny)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                      child: Text(_toast!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (_locked && !tiny)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: AnimatedOpacity(
                          opacity: _lockHint ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: IgnorePointer(
                            ignoring: !_lockHint,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 22, vertical: 14)),
                              onPressed: _unlock,
                              icon: const Icon(Icons.lock_open_rounded),
                              label: Text(tr('player.unlock')),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!tiny && !_locked)
                  AnimatedOpacity(
                    opacity: _overlay ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_overlay,
                      child: _Overlay(
                        onUserAction: _scheduleHide,
                        onFullscreen: _mobile ? null : _toggleDesktopFullscreen,
                        fullscreen: _desktopFullscreen,
                        onInfo: () => setState(() => _info = !_info),
                        onPip: Platform.isAndroid || Platform.isIOS ? _enterPip : null,
                        onSeek: _seek,
                        canSeekLive: _canSeekLive,
                        onFit: _cycleFit,
                        onLock: _mobile ? _lock : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Nom affiche d'un format d'image.
String fitLabel(VideoFit f) => switch (f) {
      VideoFit.fit => tr('fit.fit'),
      VideoFit.zoom => tr('fit.zoom'),
      VideoFit.stretch => tr('fit.stretch'),
      VideoFit.r169 => '16:9',
      VideoFit.r43 => '4:3',
    };

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text(
                  tr('player.reconnecting', [engine.retries]),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
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

/// Panneau "Infos du flux" (touche I).
class _InfoPanel extends StatefulWidget {
  final VoidCallback onClose;
  const _InfoPanel({required this.onClose});

  @override
  State<_InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<_InfoPanel> {
  Timer? _t;
  StreamInfo? _info;

  @override
  void initState() {
    super.initState();
    _refresh();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final i = await context.read<PlayerEngine>().streamInfo();
    if (mounted) setState(() => _info = i);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _info?.values ?? const {};
    final rows = [
      ('info.res', v['res']),
      ('info.vcodec', v['vcodec']),
      ('info.fps', v['fps']),
      ('info.vbr', v['vbr']),
      ('info.acodec', v['acodec']),
      ('info.abr', v['abr']),
      ('info.hwdec', v['hwdec'] == 'no' ? tr('info.software') : v['hwdec']),
      ('info.drops', v['drops']),
      ('info.cache', v['cache']),
      ('info.speed', v['speed']),
    ];
    const label = TextStyle(color: Colors.white60, fontSize: 13);
    const value = TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontFeatures: [FontFeature.tabularFigures()]);
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr('info.title'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                color: Colors.white70,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: widget.onClose,
              ),
            ],
          ),
          for (final (k, val) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 130, child: Text(tr(k), style: label)),
                  Expanded(child: Text(val ?? '-', style: value)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  final VoidCallback onUserAction;
  final VoidCallback? onFullscreen;
  final bool fullscreen;
  final VoidCallback onInfo;
  final VoidCallback? onPip;
  final Future<void> Function(int) onSeek;
  final bool canSeekLive;
  final VoidCallback onFit;
  final VoidCallback? onLock;

  const _Overlay({
    required this.onFit,
    required this.onLock,
    required this.onUserAction,
    required this.onFullscreen,
    required this.fullscreen,
    required this.onInfo,
    required this.onPip,
    required this.onSeek,
    required this.canSeekLive,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PlayerEngine>();
    final app = context.watch<AppState>();
    final recorder = context.watch<RecordingService>();
    final c = engine.current;
    final theme = Theme.of(context);
    if (c == null) return const SizedBox.shrink();
    final live = c.type == ContentType.live;
    final rec = live ? recorder.recordingFor(c) : null;
    final sleep = engine.sleepAt;

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
                if (rec != null)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('● REC',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                if (sleep != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.bedtime_rounded,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 4),
                        Text(hm(sleep.millisecondsSinceEpoch),
                            style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: tr('player.tracks'),
                  icon: const Icon(Icons.subtitles_outlined),
                  color: Colors.white,
                  onPressed: () {
                    onUserAction();
                    showTracks(context, engine.player);
                  },
                ),
                IconButton(
                  tooltip: tr('info.title'),
                  icon: const Icon(Icons.info_outline_rounded),
                  color: Colors.white,
                  onPressed: onInfo,
                ),
                IconButton(
                  tooltip: app.isFavorite(c) ? tr('fav.remove') : tr('fav.add'),
                  icon: Icon(app.isFavorite(c)
                      ? Icons.star_rounded
                      : Icons.star_border_rounded),
                  color: app.isFavorite(c) ? Colors.amber : Colors.white,
                  onPressed: () {
                    onUserAction();
                    app.toggleFavorite(c);
                  },
                ),
                if (!Platform.isLinux)
                  IconButton(
                    tooltip: tr('cast.title'),
                    icon: const Icon(Icons.cast_rounded),
                    color: Colors.white,
                    onPressed: () {
                      onUserAction();
                      showCastDialog(context);
                    },
                  ),
                IconButton(
                  tooltip: tr('fit.title'),
                  icon: const Icon(Icons.aspect_ratio_rounded),
                  color: Colors.white,
                  onPressed: onFit,
                ),
                if (onLock != null)
                  IconButton(
                    tooltip: tr('player.lock'),
                    icon: const Icon(Icons.lock_outline_rounded),
                    color: Colors.white,
                    onPressed: onLock,
                  ),
                if (onPip != null)
                  IconButton(
                    tooltip: tr('player.pip'),
                    icon: const Icon(Icons.picture_in_picture_alt_rounded),
                    color: Colors.white,
                    onPressed: onPip,
                  ),
                IconButton(
                  tooltip: tr('player.options'),
                  icon: const Icon(Icons.tune_rounded),
                  color: Colors.white,
                  onPressed: () {
                    onUserAction();
                    _showOptions(context);
                  },
                ),
                if (onFullscreen != null)
                  IconButton(
                    tooltip: tr('player.fullscreenKey'),
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
                          tooltip: tr('player.previous'),
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: () {
                            onUserAction();
                            engine.previous();
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (!live || canSeekLive) ...[
                        IconButton.filledTonal(
                          tooltip: tr('player.back10'),
                          icon: const Icon(Icons.replay_10_rounded),
                          onPressed: () {
                            onUserAction();
                            onSeek(-10);
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      _PlayPause(onUserAction: onUserAction),
                      if (!live || canSeekLive) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: tr('player.fwd10'),
                          icon: const Icon(Icons.forward_10_rounded),
                          onPressed: () {
                            onUserAction();
                            onSeek(10);
                          },
                        ),
                      ],
                      if (engine.queue.length > 1) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: tr('player.next'),
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
                  if (live && canSeekLive) ...[
                    const SizedBox(height: 8),
                    const _LiveBar(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showOptions(BuildContext context) {
    final engine = context.read<PlayerEngine>();
    final settings = context.read<Settings>();
    final app = context.read<AppState>();
    final recorder = context.read<RecordingService>();
    final c = engine.current;
    if (c == null) return;
    final live = c.type == ContentType.live;
    final rec = live ? recorder.recordingFor(c) : null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cur = live ? app.epg.nowNext(c, now).$1 : null;
    final xtream = app.active?.kind == SourceKind.xtream;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.high_quality_rounded),
                title: Text(tr('settings.quality')),
                subtitle: Text(_qualityLabel(settings.quality)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final q = await showDialog<StreamQuality>(
                    context: context,
                    builder: (d) => SimpleDialog(
                      title: Text(tr('settings.quality')),
                      children: [
                        for (final q in StreamQuality.values)
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(d, q),
                            child: Row(children: [
                              Icon(q == settings.quality
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded),
                              const SizedBox(width: 12),
                              Text(_qualityLabel(q)),
                            ]),
                          ),
                      ],
                    ),
                  );
                  if (q == null) return;
                  settings.update((s) => s.quality = q);
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                  engine.reload();
                },
              ),
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: Text(tr('player.tracks')),
                onTap: () {
                  Navigator.pop(ctx);
                  showTracks(context, engine.player);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text(tr('sleep.title')),
                subtitle: engine.sleepAt == null
                    ? null
                    : Text(tr('sleep.at', [hm(engine.sleepAt!.millisecondsSinceEpoch)])),
                onTap: () async {
                  Navigator.pop(ctx);
                  final m = await showDialog<int>(
                    context: context,
                    builder: (d) => SimpleDialog(
                      title: Text(tr('sleep.title')),
                      children: [
                        for (final m in [15, 30, 45, 60, 90, 120])
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(d, m),
                            child: Text(tr('common.minutes', [m])),
                          ),
                        if (cur != null)
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(
                                d, ((cur.stop - now) / 60000).ceil()),
                            child: Text(tr('sleep.endOf', [cur.title])),
                          ),
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(d, 0),
                          child: Text(tr('sleep.off')),
                        ),
                      ],
                    ),
                  );
                  if (m == null) return;
                  engine.setSleepTimer(m == 0 ? null : Duration(minutes: m));
                },
              ),
              if (live && rec == null)
                ListTile(
                  leading: const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
                  title: Text(tr('rec.now')),
                  onTap: () {
                    Navigator.pop(ctx);
                    recordNowDialog(context, c);
                  },
                ),
              if (rec != null)
                ListTile(
                  leading: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                  title: Text(tr('rec.stop')),
                  onTap: () {
                    Navigator.pop(ctx);
                    recorder.stopRecording(rec);
                  },
                ),
              if (live && cur != null)
                ListTile(
                  leading: const Icon(Icons.event_note_rounded),
                  title: Text(cur.title),
                  subtitle: Text(tr('player.programmeInfo')),
                  onTap: () {
                    Navigator.pop(ctx);
                    showProgrammeSheet(context, c, cur);
                  },
                ),
              if (live && c.hasArchive && xtream)
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(tr('catchup.title')),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CatchupScreen(channel: c)));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _qualityLabel(StreamQuality q) => switch (q) {
      StreamQuality.best => tr('quality.best'),
      StreamQuality.fhd => tr('quality.fhd'),
      StreamQuality.hd => tr('quality.hd'),
      StreamQuality.low => tr('quality.low'),
    };

/// Pistes video (qualites), audio et sous-titres.
void showTracks(BuildContext context, Player player) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final tracks = player.state.tracks;
      final track = player.state.track;
      String label(dynamic t) {
        if (t.id == 'auto') return tr('tracks.auto');
        if (t.id == 'no') return tr('tracks.off');
        final parts = <String>[
          if (t is VideoTrack && t.w != null) '${t.w}×${t.h}',
          if (t is VideoTrack && t.bitrate != null && t.bitrate! > 0)
            '${(t.bitrate! / 1e6).toStringAsFixed(1)} Mb/s',
          if (t.title != null && (t.title as String).isNotEmpty) t.title as String,
          if (t.language != null && (t.language as String).isNotEmpty)
            t.language as String,
        ];
        return parts.isEmpty ? tr('tracks.track', [t.id]) : parts.join(' · ');
      }

      final videos = tracks.video.where((t) => t.id != 'no').toList();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (videos.length > 2) ...[
                ListTile(title: Text(tr('tracks.video'))),
                for (final t in videos)
                  ListTile(
                    leading: Icon(t.id == track.video.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded),
                    title: Text(label(t)),
                    onTap: () {
                      player.setVideoTrack(t);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
              ListTile(title: Text(tr('tracks.audio'))),
              for (final t in tracks.audio)
                ListTile(
                  leading: Icon(t.id == track.audio.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded),
                  title: Text(label(t)),
                  onTap: () {
                    player.setAudioTrack(t);
                    Navigator.pop(ctx);
                  },
                ),
              ListTile(title: Text(tr('tracks.subtitles'))),
              for (final t in tracks.subtitle)
                ListTile(
                  leading: Icon(t.id == track.subtitle.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded),
                  title: Text(label(t)),
                  onTap: () {
                    player.setSubtitleTrack(t);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Barre de la pause du direct : retard sur le direct et bouton "Direct".
class _LiveBar extends StatefulWidget {
  const _LiveBar();

  @override
  State<_LiveBar> createState() => _LiveBarState();
}

class _LiveBarState extends State<_LiveBar> {
  Timer? _t;
  LiveCache _c = LiveCache.none;

  @override
  void initState() {
    super.initState();
    _refresh();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final c = await context.read<PlayerEngine>().liveCache();
    if (mounted) setState(() => _c = c);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.read<PlayerEngine>();
    final behind = _c.behind;
    final atLive = behind < 4;
    final total = _c.back + behind;
    final value = total <= 0 ? 1.0 : (_c.back / total).clamp(0.0, 1.0);
    return Row(
      children: [
        Text(
          atLive
              ? tr('player.live')
              : '-${formatDuration(Duration(seconds: behind.round()))}',
          style: TextStyle(
              color: atLive ? Colors.redAccent : Colors.white,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: Colors.white24,
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: atLive ? null : engine.goLive,
          icon: const Icon(Icons.skip_next_rounded),
          label: Text(tr('player.goLive')),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
      ],
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
              Text('${hm(cur.start)}  ${cur.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
              Text(tr('player.next2', [hm(next.start), next.title]),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ],
          ],
        );
      },
    );
  }
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
        tooltip: tr('player.playPause'),
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
            Text(formatDuration(Duration(milliseconds: value.round())),
                style: white),
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
            Text(formatDuration(dur), style: white),
          ],
        );
      },
    );
  }
}
