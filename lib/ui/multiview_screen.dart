import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../player/player_engine.dart';
import '../services/net.dart';
import '../state/app_state.dart';
import 'navigation.dart';
import 'subscription_screen.dart';
import 'widgets/channel_logo.dart';

Future<void> openMultiView(BuildContext context, {Channel? initial}) async {
  await context.read<PlayerEngine>().stop();
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MultiViewScreen(initial: initial)));
}

class _Slot {
  final Player player;
  final VideoController video;
  Channel? channel;

  _Slot._(this.player, this.video);

  factory _Slot() {
    final p = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    return _Slot._(p, VideoController(p));
  }
}

/// Multi-ecran : jusqu'a 4 chaines en meme temps. Le son vient de la
/// fenetre selectionnee (cadre bleu).
class MultiViewScreen extends StatefulWidget {
  final Channel? initial;
  const MultiViewScreen({super.key, this.initial});

  @override
  State<MultiViewScreen> createState() => _MultiViewScreenState();
}

class _MultiViewScreenState extends State<MultiViewScreen> {
  final List<_Slot> _slots = [];
  int _audio = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _add(widget.initial!);
  }

  @override
  void dispose() {
    for (final s in _slots) {
      s.player.dispose();
    }
    super.dispose();
  }

  Future<void> _add(Channel c) async {
    if (_slots.length >= 4) return;
    final s = _Slot()..channel = c;
    setState(() => _slots.add(s));
    final ua = context.read<AppState>().active?.userAgent ?? '';
    await s.player.open(Media(c.url, httpHeaders: {
      'User-Agent': ua.isEmpty ? defaultUserAgent : ua,
      ...c.headers,
    }));
    _applyAudio();
  }

  void _applyAudio() {
    for (var i = 0; i < _slots.length; i++) {
      _slots[i].player.setVolume(i == _audio ? 100 : 0);
    }
  }

  void _remove(int i) {
    final s = _slots.removeAt(i);
    s.player.dispose();
    if (_audio >= _slots.length) _audio = 0;
    _applyAudio();
    setState(() {});
  }

  Future<void> _pick() async {
    if (!await ensureLicensed(context) || !mounted) return;
    final app = context.read<AppState>();
    final all = app.visibleItems(ContentType.live).toList();
    final fav = all.where(app.isFavorite).toList();
    final c = await showDialog<Channel>(
      context: context,
      builder: (_) => _ChannelPicker(channels: [...fav, ...all.where((c) => !app.isFavorite(c))]),
    );
    if (c != null) await _add(c);
  }

  void _fullscreen(int i) {
    final c = _slots[i].channel;
    if (c == null) return;
    final app = context.read<AppState>();
    final queue = app.visibleItems(ContentType.live).toList();
    final nav = Navigator.of(context);
    final engine = context.read<PlayerEngine>();
    nav.pop();
    engine.play(c, queue: queue);
    nav.push(playerRoute(stopOnExit: true));
  }

  @override
  Widget build(BuildContext context) {
    final n = _slots.length;
    final cells = <Widget>[
      for (var i = 0; i < n; i++) _tile(i),
      if (n < 4) _addTile(),
    ];
    final cols = cells.length <= 1 ? 1 : 2;
    final rows = (cells.length / cols).ceil();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(tr('multi.title')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(tr('multi.hint'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < cols; c++)
                    Expanded(
                      child: r * cols + c < cells.length
                          ? Padding(
                              padding: const EdgeInsets.all(2),
                              child: cells[r * cols + c],
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(int i) {
    final s = _slots[i];
    final active = i == _audio;
    return GestureDetector(
      onTap: () {
        setState(() => _audio = i);
        _applyAudio();
      },
      onDoubleTap: () => _fullscreen(i),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? Theme.of(context).colorScheme.primary : Colors.white12,
            width: active ? 3 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: s.video, controls: NoVideoControls),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(active ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(s.channel?.name ?? '',
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('player.fullscreen'),
                    color: Colors.white,
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: () => _fullscreen(i),
                  ),
                  IconButton(
                    tooltip: tr('common.close'),
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _remove(i),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addTile() => Material(
        color: Colors.white10,
        child: InkWell(
          autofocus: _slots.isEmpty,
          onTap: _pick,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, size: 48, color: Colors.white70),
                const SizedBox(height: 8),
                Text(tr('multi.add'),
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      );
}

class _ChannelPicker extends StatefulWidget {
  final List<Channel> channels;
  const _ChannelPicker({required this.channels});

  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<_ChannelPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final words = _q.toLowerCase().split(RegExp(r'\s+'));
    final list = _q.isEmpty
        ? widget.channels
        : widget.channels
            .where((c) => words.every(c.searchKey.contains))
            .toList();
    return AlertDialog(
      title: Text(tr('multi.pick')),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('common.search'),
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemExtent: 60,
                itemBuilder: (_, i) => ListTile(
                  leading: ChannelLogo(url: list[i].logo, name: list[i].name),
                  title: Text(list[i].name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, list[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
      ],
    );
  }
}
