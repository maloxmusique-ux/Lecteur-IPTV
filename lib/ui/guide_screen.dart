import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../services/recorder.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import 'navigation.dart';
import 'programme_sheet.dart';
import 'widgets/channel_logo.dart';

const _rowHeight = 64.0;
const _headerHeight = 34.0;
const _favKey = '\u0000fav';
const _allKey = '\u0000all';

/// Grille du guide TV : chaines a gauche, heures en haut, 8 jours
/// (hier + 7 jours a venir), recherche dans tous les programmes.
class GuideView extends StatefulWidget {
  const GuideView({super.key});

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView> {
  static String? _savedGroup;

  /// Debut de la grille (hier a minuit), en ms.
  late final int _rangeStart;
  late final int _rangeEnd;

  /// Minutes depuis [_rangeStart] au bord gauche de la grille.
  late final ValueNotifier<double> _offset;

  String? _group = _savedGroup;
  final _search = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _rangeStart = DateTime(now.year, now.month, now.day - 1).millisecondsSinceEpoch;
    _rangeEnd = DateTime(now.year, now.month, now.day + 8).millisecondsSinceEpoch;
    _offset = ValueNotifier(_minutesOf(now.millisecondsSinceEpoch) - 30);
  }

  @override
  void dispose() {
    _offset.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  double _minutesOf(int ms) => (ms - _rangeStart) / 60000;
  int _msOf(double minutes) => _rangeStart + (minutes * 60000).round();

  double get _maxOffset => (_rangeEnd - _rangeStart) / 60000 - 60;

  void _setOffset(double v) => _offset.value = v.clamp(0, _maxOffset);

  void _jumpNow() =>
      _setOffset(_minutesOf(DateTime.now().millisecondsSinceEpoch) - 30);

  void _jumpDay(DateTime day) {
    final now = DateTime.now();
    final target = DateTime(day.year, day.month, day.day, now.hour, 0);
    _setOffset(_minutesOf(target.millisecondsSinceEpoch) - 30);
  }

  List<Channel> _channels(AppState app) {
    final g = _group ?? (app.favorites.isEmpty ? _allKey : _favKey);
    final all = app.visibleItems(ContentType.live);
    if (g == _favKey) return all.where(app.isFavorite).toList();
    if (g == _allKey) return all.toList();
    return all.where((c) => c.groupKey == g).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final wide = isWide(context);
    final ppm = wide ? 4.5 : 3.4; // pixels par minute
    final channelWidth = wide ? 180.0 : 112.0;

    if (app.catalog.isEmpty) {
      return Center(
        child: app.loading
            ? const CircularProgressIndicator()
            : Text(tr('status.addSource')),
      );
    }

    final groups = app.groupsFor(ContentType.live);
    final channels = _channels(app);
    final currentGroup = _group ?? (app.favorites.isEmpty ? _allKey : _favKey);

    // Calcul par calendrier (et non par 24 h) : juste les jours de
    // changement d'heure.
    final first = DateTime.fromMillisecondsSinceEpoch(_rangeStart);
    final days = [
      for (var i = 0; i < 9; i++) DateTime(first.year, first.month, first.day + i),
    ];

    final groupMenu = _GroupMenu(
      value: currentGroup,
      groups: groups,
      hasFavorites: app.favorites.isNotEmpty,
      onChanged: (g) => setState(() => _group = _savedGroup = g),
    );
    final dayChips = ValueListenableBuilder<double>(
      valueListenable: _offset,
      builder: (context, off, _) {
        final centerMs = _msOf(off + 120);
        final center = DateTime.fromMillisecondsSinceEpoch(centerMs);
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final d in days)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(dayLabel(d)),
                  selected: d.year == center.year &&
                      d.month == center.month &&
                      d.day == center.day,
                  onSelected: (_) => _jumpDay(d),
                ),
              ),
          ],
        );
      },
    );
    final timeNav = [
      IconButton(
        tooltip: tr('guide.earlier'),
        onPressed: () => _setOffset(_offset.value - 120),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      TextButton(onPressed: _jumpNow, child: Text(tr('guide.now'))),
      IconButton(
        tooltip: tr('guide.later'),
        onPressed: () => _setOffset(_offset.value + 120),
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ];

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(tr('tab.guide'), style: theme.textTheme.titleLarge),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _search,
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        if (mounted) setState(() => _query = v.trim());
                      });
                    },
                    decoration: InputDecoration(
                      hintText: wide ? tr('guide.search') : tr('common.search'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
              ),
              if (app.epgLoading)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
          if (_query.isEmpty) ...[
            const SizedBox(height: 8),
            // Telephone : categories et heure sur une ligne, jours dessous.
            if (wide)
              SizedBox(
                height: 40,
                child: Row(children: [groupMenu, const SizedBox(width: 8), Expanded(child: dayChips), ...timeNav]),
              )
            else ...[
              SizedBox(
                height: 40,
                child: Row(children: [Flexible(child: groupMenu), const Spacer(), ...timeNav]),
              ),
              const SizedBox(height: 6),
              SizedBox(height: 40, child: dayChips),
            ],
          ],
        ],
      ),
    );

    if (_query.isNotEmpty) {
      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            header,
            Expanded(child: _SearchResults(query: _query)),
          ],
        ),
      );
    }

    if (channels.isEmpty) {
      return SafeArea(
        bottom: false,
        child: Column(children: [
          header,
          Expanded(child: Center(child: Text(tr('common.noResults')))),
        ]),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          header,
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final gridWidth = box.maxWidth - channelWidth;
              final viewMinutes = gridWidth / ppm;
              return Listener(
                // Molette horizontale (ou Maj + molette) : deplace le temps.
                onPointerSignal: (e) {
                  if (e is! PointerScrollEvent) return;
                  final shift = HardwareKeyboard.instance.isShiftPressed;
                  final dx = e.scrollDelta.dx != 0
                      ? e.scrollDelta.dx
                      : (shift ? e.scrollDelta.dy : 0.0);
                  if (dx != 0) _setOffset(_offset.value + dx / ppm);
                },
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) =>
                      _setOffset(_offset.value - d.delta.dx / ppm),
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          SizedBox(
                            height: _headerHeight,
                            child: Row(
                              children: [
                                SizedBox(width: channelWidth),
                                Expanded(
                                  child: _TimeHeader(
                                    offset: _offset,
                                    ppm: ppm,
                                    msOf: _msOf,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.builder(
                              itemCount: channels.length,
                              itemExtent: _rowHeight,
                              itemBuilder: (context, i) => _GuideRow(
                                channel: channels[i],
                                queue: channels,
                                channelWidth: channelWidth,
                                ppm: ppm,
                                viewMinutes: viewMinutes,
                                offset: _offset,
                                minutesOf: _minutesOf,
                                msOf: _msOf,
                                onReveal: (startMin, endMin) {
                                  final o = _offset.value;
                                  if (startMin < o) {
                                    _setOffset(startMin - 10);
                                  } else if (startMin > o + viewMinutes - 30) {
                                    _setOffset(math.min(startMin - 10,
                                        endMin - viewMinutes + 10));
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Ligne de l'heure actuelle.
                      Positioned.fill(
                        left: channelWidth,
                        child: IgnorePointer(
                          child: ValueListenableBuilder<int>(
                            valueListenable: app.minuteTick,
                            builder: (_, _, _) => ValueListenableBuilder<double>(
                              valueListenable: _offset,
                              builder: (_, off, _) {
                                final x = (_minutesOf(DateTime.now()
                                            .millisecondsSinceEpoch) -
                                        off) *
                                    ppm;
                                if (x < 0 || x > gridWidth) {
                                  return const SizedBox.shrink();
                                }
                                return Stack(children: [
                                  Positioned(
                                    left: x - 1,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                        width: 2, color: Colors.redAccent),
                                  ),
                                ]);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _GroupMenu extends StatelessWidget {
  final String value;
  final List<String> groups;
  final bool hasFavorites;
  final ValueChanged<String> onChanged;

  const _GroupMenu({
    required this.value,
    required this.groups,
    required this.hasFavorites,
    required this.onChanged,
  });

  String _label(String g) => g == _favKey
      ? tr('guide.favorites')
      : g == _allKey
          ? tr('browse.allChannels')
          : AppState.groupLabel(g);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tr('guide.category'),
      onSelected: onChanged,
      itemBuilder: (_) => [
        if (hasFavorites)
          PopupMenuItem(value: _favKey, child: Text(_label(_favKey))),
        PopupMenuItem(value: _allKey, child: Text(_label(_allKey))),
        const PopupMenuDivider(),
        for (final g in groups)
          PopupMenuItem(value: g, child: Text(_label(g))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(_label(value), overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}

class _TimeHeader extends StatelessWidget {
  final ValueNotifier<double> offset;
  final double ppm;
  final int Function(double) msOf;

  const _TimeHeader({
    required this.offset,
    required this.ppm,
    required this.msOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      return ClipRect(
        child: ValueListenableBuilder<double>(
          valueListenable: offset,
          builder: (_, off, _) {
            final view = box.maxWidth / ppm;
            // Premiere demi-heure visible.
            final startMs = msOf(off);
            final first = DateTime.fromMillisecondsSinceEpoch(startMs);
            var t = DateTime(first.year, first.month, first.day, first.hour,
                first.minute < 30 ? 0 : 30);
            final children = <Widget>[];
            while (true) {
              final m = (t.millisecondsSinceEpoch - startMs) / 60000;
              if (m > view) break;
              final label = t.hour == 0 && t.minute == 0
                  ? '${dayLabel(t)} ${hm(t.millisecondsSinceEpoch)}'
                  : hm(t.millisecondsSinceEpoch);
              children.add(Positioned(
                left: m * ppm,
                top: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(color: theme.dividerColor)),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(label, style: theme.textTheme.labelMedium),
                ),
              ));
              t = t.add(const Duration(minutes: 30));
            }
            return Stack(children: children);
          },
        ),
      );
    });
  }
}

class _GuideRow extends StatelessWidget {
  final Channel channel;
  final List<Channel> queue;
  final double channelWidth;
  final double ppm;
  final double viewMinutes;
  final ValueNotifier<double> offset;
  final double Function(int) minutesOf;
  final int Function(double) msOf;
  final void Function(double startMin, double endMin) onReveal;

  const _GuideRow({
    required this.channel,
    required this.queue,
    required this.channelWidth,
    required this.ppm,
    required this.viewMinutes,
    required this.offset,
    required this.minutesOf,
    required this.msOf,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final reminders = context.watch<ReminderService>();
    final recorder = context.watch<RecordingService>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = app.epg.forChannel(channel) ?? const <Programme>[];
    final sourceId = app.active?.id ?? '';

    return Row(
      children: [
        SizedBox(
          width: channelWidth,
          child: InkWell(
            onTap: () => playFullscreen(context, channel, queue),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor, width: 0.5),
                  right: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  ChannelLogo(
                      url: channel.logo, name: channel.name, width: 40, height: 40),
                  if (channelWidth > 130) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: ValueListenableBuilder<double>(
              valueListenable: offset,
              builder: (context, off, _) {
                final now = DateTime.now().millisecondsSinceEpoch;
                // Fenetre construite : un peu plus large que l'ecran pour
                // permettre la navigation a la telecommande.
                final fromMs = msOf(off - 180);
                final toMs = msOf(off + viewMinutes + 180);
                final cells = <Widget>[];
                if (list.isEmpty) {
                  cells.add(Positioned.fill(
                    child: _Cell(
                      title: app.epgLoading ? tr('epg.loading') : tr('epg.noInfo'),
                      subtitle: '',
                      color: scheme.surfaceContainer,
                      onTap: () => playFullscreen(context, channel, queue),
                    ),
                  ));
                } else {
                  var i = _firstIndex(list, fromMs);
                  for (; i < list.length && list[i].start < toMs; i++) {
                    final p = list[i];
                    final startMin = minutesOf(p.start);
                    final endMin = minutesOf(p.stop);
                    final left = (startMin - off) * ppm;
                    final width = math.max(2.0, (endMin - startMin) * ppm);
                    final live = p.isLive(now);
                    final past = p.isPast(now);
                    final archive = past && inArchive(channel, p, now);
                    cells.add(Positioned(
                      left: left,
                      width: width,
                      top: 0,
                      bottom: 0,
                      child: _Cell(
                        title: p.title,
                        subtitle: '${hm(p.start)} – ${hm(p.stop)}',
                        color: live
                            ? scheme.primaryContainer.withValues(alpha: 0.75)
                            : past
                                ? scheme.surfaceContainerLowest
                                : scheme.surfaceContainerHigh,
                        dim: past && !archive,
                        progress: live ? p.progress(now) : null,
                        reminder: reminders.has(sourceId, channel, p),
                        recording: recorder.isScheduled(sourceId, channel, p),
                        archive: archive,
                        onTap: () => showProgrammeSheet(context, channel, p),
                        onFocus: () => onReveal(startMin, endMin),
                      ),
                    ));
                  }
                }
                return Stack(clipBehavior: Clip.none, children: cells);
              },
            ),
          ),
        ),
      ],
    );
  }

  static int _firstIndex(List<Programme> list, int fromMs) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].stop <= fromMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

class _Cell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final bool dim;
  final double? progress;
  final bool reminder;
  final bool recording;
  final bool archive;
  final VoidCallback onTap;
  final VoidCallback? onFocus;

  const _Cell({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.dim = false,
    this.progress,
    this.reminder = false,
    this.recording = false,
    this.archive = false,
    this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = dim ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onFocusChange: (f) {
            if (f) onFocus?.call();
          },
          focusColor: theme.colorScheme.primary.withValues(alpha: 0.45),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        if (recording)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.fiber_manual_record,
                                size: 11, color: Colors.redAccent),
                          ),
                        if (reminder)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.notifications_active_rounded,
                                size: 13, color: Colors.amber),
                          ),
                        if (archive)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.history_rounded,
                                size: 13, color: Colors.tealAccent),
                          ),
                        Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600, color: fg)),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (progress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resultats de recherche dans le guide (programmes en cours et a venir,
/// et programmes passes disponibles en rattrapage).
class _SearchResults extends StatelessWidget {
  final String query;
  const _SearchResults({required this.query});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final now = DateTime.now().millisecondsSinceEpoch;
    final words = query.toLowerCase().split(RegExp(r'\s+'));
    final results = <(Channel, Programme)>[];
    for (final c in app.visibleItems(ContentType.live)) {
      final list = app.epg.forChannel(c);
      if (list == null) continue;
      for (final p in list) {
        if (p.stop <= now && !inArchive(c, p, now)) continue;
        final t = p.title.toLowerCase();
        if (words.every(t.contains)) results.add((c, p));
      }
      if (results.length > 2000) break;
    }
    results.sort((a, b) => a.$2.start.compareTo(b.$2.start));
    if (results.isEmpty) {
      return Center(
        child: Text(app.epg.isEmpty ? tr('epg.none') : tr('common.noResults')),
      );
    }
    final shown = results.take(400).toList();
    return ListView.builder(
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final (c, p) = shown[i];
        final live = p.isLive(now);
        final past = p.isPast(now);
        return ListTile(
          leading: ChannelLogo(url: c.logo, name: c.name),
          title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${c.name} · ${dayTime(p.start)}'),
          trailing: live
              ? Text(tr('epg.live'),
                  style: const TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.w700))
              : past
                  ? Icon(Icons.history_rounded, color: theme.colorScheme.primary)
                  : null,
          onTap: () => showProgrammeSheet(context, c, p),
        );
      },
    );
  }
}
