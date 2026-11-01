import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../services/proxy.dart';
import '../services/net.dart';
import '../state/settings.dart';

/// Etat de la pause du direct (timeshift).
class LiveCache {
  /// Secondes de retard sur le direct.
  final double behind;

  /// Secondes disponibles en arriere dans le cache.
  final double back;

  const LiveCache(this.behind, this.back);
  static const none = LiveCache(0, 0);
}

/// Informations techniques du flux en cours (panneau "Infos du flux").
class StreamInfo {
  final Map<String, String> values;
  const StreamInfo(this.values);
}

/// Moteur de lecture unique, partage par toute l'application.
///
/// Points cles pour la fluidite et la stabilite en HD :
/// * Une seule instance libmpv reutilisee : changer de chaine ne recree
///   jamais le lecteur ni la surface video, d'ou un zapping rapide.
/// * Decodage materiel avec repli automatique sur le decodage logiciel.
/// * Petit tampon de demarrage (reglable) pour eviter les saccades HD.
/// * Reconnexion illimitee des chaines en direct, avec delai croissant,
///   et relance automatique si le flux reste bloque.
/// * Pause du direct : le flux est garde sur disque (cache-on-disk).
class PlayerEngine extends ChangeNotifier {
  final Settings settings;
  late final Player player;
  late final VideoController video;

  Channel? _current;
  Channel? get current => _current;

  /// Liste de lecture courante (pour chaine suivante/precedente).
  List<Channel> _queue = const [];
  int _index = -1;
  List<Channel> get queue => _queue;
  int get index => _index;

  String _userAgent = '';
  String? lastError;

  /// Nombre de tentatives de reconnexion en cours (0 = aucune).
  int retries = 0;

  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _retry;
  Timer? _watchdog;
  Timer? _progressTimer;
  DateTime? _bufferingSince;
  Duration _lastPos = Duration.zero;

  /// Plus petite position vue depuis l'ouverture (debut du cache du direct).
  double? _minLivePos;

  /// Minuterie de mise en veille.
  Timer? _sleep;
  DateTime? sleepAt;

  /// Appele regulierement pour sauvegarder la position des films.
  void Function(Channel c, Duration pos, Duration dur)? onProgress;

  /// Applique les reglages qui ont change.
  late final VoidCallback _settingsListener = _tune;

  PlayerEngine(this.settings) {
    final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    player = Player(
      configuration: PlayerConfiguration(
        // Cache demuxer plus large sur desktop pour absorber les micro-coupures.
        bufferSize: (mobile ? 64 : 160) * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    video = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        hwdec: settings.hwdec ? null : 'no',
      ),
    );
    _tune();
    settings.addListener(_settingsListener);
    _subs.add(player.stream.error.listen(_onError));
    // Si la lecture avance, le flux est sain : on efface l'erreur.
    _subs.add(player.stream.position.listen((pos) {
      _lastPos = pos;
      if (lastError != null && pos > const Duration(seconds: 1)) {
        lastError = null;
        retries = 0;
        _retry?.cancel();
        notifyListeners();
      }
    }));
    _subs.add(player.stream.buffering.listen((b) {
      _bufferingSince = b ? DateTime.now() : null;
    }));
    // Fin d'un film : on enchaine l'element suivant (episodes).
    _subs.add(player.stream.completed.listen((done) {
      final c = _current;
      if (!done || c == null || c.type == ContentType.live) return;
      _reportProgress();
      if (_queue.length > 1 && _index < _queue.length - 1) next();
    }));
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkStall());
    _progressTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _reportProgress());
  }

  String? _defaultHwdec;
  String? _cacheDir;

  Future<void> _tune() async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    final s = settings;
    _defaultHwdec ??= await _get('hwdec');
    if (_cacheDir == null && settings.timeshift) {
      try {
        final d = Directory('${(await getTemporaryDirectory()).path}/'
            'streamflow_timeshift');
        await d.create(recursive: true);
        _cacheDir = d.path;
      } catch (_) {}
    }

    final (wait, readahead, timeout) = switch (s.bufferMode) {
      BufferMode.fast => ('0.5', 10, 15),
      BufferMode.balanced => ('1.2', 25, 20),
      BufferMode.stable => ('3', 60, 30),
    };
    // Pause du direct : jusqu'a N minutes gardees sur disque (~8 Mb/s HD).
    final tsBytes = math.min(s.timeshiftMinutes * 60 * 1024 * 1024, 4000 << 20);
    final timeshift = s.timeshift && _cacheDir != null;

    final opts = <String, String>{
      'cache': 'yes',
      'cache-pause-initial': s.bufferMode == BufferMode.fast ? 'no' : 'yes',
      'cache-pause-wait': wait,
      'cache-secs': '$readahead',
      'demuxer-readahead-secs': '$readahead',
      if (timeshift) ...{
        'cache-on-disk': 'yes',
        'demuxer-cache-dir': _cacheDir!,
        'demuxer-max-bytes': '$tsBytes',
        'demuxer-max-back-bytes': '$tsBytes',
      } else ...{
        'cache-on-disk': 'no',
        'demuxer-max-back-bytes': '${32 * 1024 * 1024}',
      },
      'demuxer-seekable-cache': 'yes',
      'force-seekable': 'yes',
      // Analyse du flux TS/HLS reduite (zapping plus rapide).
      'demuxer-lavf-analyzeduration': '2',
      'demuxer-lavf-probesize': '${2 * 1024 * 1024}',
      // Paquets corrompus ignores : evite les blocs verts en HD.
      'demuxer-lavf-o': 'fflags=+discardcorrupt',
      // Reseau robuste.
      'network-timeout': '$timeout',
      'stream-lavf-o':
          'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
              'reconnect_delay_max=5',
      'hls-bitrate': switch (s.quality) {
        StreamQuality.best => 'max',
        StreamQuality.fhd => '9000000',
        StreamQuality.hd => '4000000',
        StreamQuality.low => 'min',
      },
      // Decodage materiel, repli automatique sur le logiciel en cas d'echec.
      'hwdec': s.hwdec ? (_defaultHwdec ?? 'auto-safe') : 'no',
      // Rendu fluide.
      'video-sync': 'audio',
      'framedrop': 'vo',
      'deinterlace': 'auto',
      'keep-open': 'no',
      // VPN de l'utilisateur (relais local), vide = connexion directe.
      'http-proxy': ProxyBridge.mpvProxy,
      // Langues preferees.
      'alang': s.audioLangs,
      'slang': s.subLangs,
    };
    for (final e in opts.entries) {
      try {
        await p.setProperty(e.key, e.value);
      } catch (_) {
        // Option non supportee par cette build de libmpv : on ignore.
      }
    }
  }

  Future<String?> _get(String prop) async {
    final p = player.platform;
    if (p is! NativePlayer) return null;
    try {
      final v = await p.getProperty(prop);
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<double?> _num(String prop) async =>
      double.tryParse(await _get(prop) ?? '');

  void setUserAgent(String ua) => _userAgent = ua;

  /// Lance une entree. Si [queue] est fourni, active le zapping.
  /// [startAt] reprend un film a une position donnee.
  Future<void> play(Channel c, {List<Channel>? queue, Duration? startAt}) async {
    _reportProgress();
    if (queue != null) {
      _queue = queue;
      _index = queue.indexWhere((e) => e.id == c.id);
    }
    _current = c;
    lastError = null;
    retries = 0;
    _retry?.cancel();
    _minLivePos = null;
    _lastPos = Duration.zero;
    notifyListeners();
    await _open(c, startAt: startAt);
  }

  Future<void> _open(Channel c, {Duration? startAt}) async {
    final headers = <String, String>{
      'User-Agent': _userAgent.isEmpty ? defaultUserAgent : _userAgent,
      ...c.headers,
    };
    _bufferingSince = DateTime.now();
    await player.open(
      Media(c.url,
          httpHeaders: headers,
          start: (startAt == null || startAt == Duration.zero) ? null : startAt),
      play: true,
    );
  }

  /// Relance le flux en cours (apres changement de qualite par exemple).
  Future<void> reload() async {
    final c = _current;
    if (c == null) return;
    final pos = c.type == ContentType.live ? null : _lastPos;
    await _open(c, startAt: pos);
  }

  Future<void> next() => _step(1);
  Future<void> previous() => _step(-1);

  Future<void> _step(int d) async {
    if (_queue.isEmpty) return;
    _index = (_index + d) % _queue.length;
    if (_index < 0) _index += _queue.length;
    await play(_queue[_index]);
  }

  bool get isLive => _current?.type == ContentType.live;

  void _onError(String e) {
    // Les erreurs de peripherique audio ne signifient pas que le flux est mort.
    final lower = e.toLowerCase();
    if (lower.contains('audio') || lower.contains('ao/')) return;
    lastError = e;
    notifyListeners();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    final c = _current;
    if (c == null) return;
    // Direct : tentatives illimitees. Films : 4 tentatives.
    if (c.type != ContentType.live && retries >= 4) return;
    retries++;
    notifyListeners();
    _retry?.cancel();
    final delay = math.min(15, 1 << math.min(retries, 4));
    _retry = Timer(Duration(seconds: delay), () {
      if (_current?.id != c.id) return;
      _open(c, startAt: c.type == ContentType.live ? null : _lastPos);
    });
  }

  /// Relance un direct reste bloque en chargement trop longtemps.
  void _checkStall() {
    final since = _bufferingSince;
    final c = _current;
    if (since == null || c == null || !player.state.playing) return;
    final limit = Duration(
        seconds: settings.bufferMode == BufferMode.stable ? 25 : 15);
    if (DateTime.now().difference(since) > limit) {
      _bufferingSince = DateTime.now();
      lastError ??= 'stall';
      _scheduleRetry();
    }
  }

  void _reportProgress() {
    final c = _current;
    if (c == null || c.type == ContentType.live) return;
    final dur = player.state.duration;
    if (_lastPos > Duration.zero) onProgress?.call(c, _lastPos, dur);
  }

  // ----------------------------------------------------- Pause du direct

  /// Retard sur le direct et marge disponible en arriere.
  Future<LiveCache> liveCache() async {
    final pos = await _num('time-pos');
    final end = await _num('demuxer-cache-time');
    if (pos == null || end == null) return LiveCache.none;
    final min = _minLivePos;
    if (min == null || pos < min) _minLivePos = pos;
    final start = await _seekableStart() ?? _minLivePos ?? pos;
    return LiveCache(math.max(0, end - pos), math.max(0, pos - start));
  }

  Future<double?> _seekableStart() async {
    // "demuxer-cache-state" contient les plages consultables.
    final raw = await _get('demuxer-cache-state');
    if (raw == null) return null;
    final m = RegExp(r'"start"\s*:\s*([0-9.]+)').firstMatch(raw);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  /// Avance ou recule dans le direct (ou dans un film).
  Future<void> seekBy(int seconds) async {
    final p = player.platform;
    if (p is NativePlayer && isLive) {
      try {
        await p.command(['seek', '$seconds', 'relative']);
      } catch (_) {}
      return;
    }
    final pos = player.state.position + Duration(seconds: seconds);
    await player.seek(pos < Duration.zero ? Duration.zero : pos);
  }

  /// Revient au direct.
  Future<void> goLive() async {
    final p = player.platform;
    final end = await _num('demuxer-cache-time');
    if (p is! NativePlayer || end == null) return;
    try {
      await p.command(['seek', '${math.max(0, end - 1.5)}', 'absolute']);
      await player.play();
    } catch (_) {}
  }

  // ------------------------------------------------------- Infos du flux

  Future<StreamInfo> streamInfo() async {
    final s = player.state;
    final codec = (await _get('video-format'))?.toUpperCase() ??
        await _get('video-codec');
    final fps = await _num('estimated-vf-fps') ?? await _num('container-fps');
    final vbr = await _num('video-bitrate');
    final abr = await _num('audio-bitrate');
    final acodec = (await _get('audio-codec-name'))?.toUpperCase() ??
        s.track.audio.codec ??
        _audioCodec(s);
    final hw = await _get('hwdec-current');
    final drops = await _get('frame-drop-count');
    final ddrops = await _get('decoder-frame-drop-count');
    final cache = await _num('demuxer-cache-duration');
    final speed = await _num('cache-speed');
    String mbps(double? b) =>
        b == null ? '-' : '${(b / 1e6).toStringAsFixed(2)} Mb/s';
    return StreamInfo({
      'res': s.width == null ? '-' : '${s.width} × ${s.height}',
      'vcodec': codec ?? '-',
      'fps': fps == null ? '-' : fps.toStringAsFixed(2),
      'vbr': mbps(vbr),
      'acodec': acodec ?? '-',
      'abr': abr == null ? '-' : '${(abr / 1000).round()} kb/s',
      'hwdec': (hw == null || hw == 'no') ? 'no' : hw,
      'drops': '${drops ?? 0} / ${ddrops ?? 0}',
      'cache': cache == null ? '-' : '${cache.toStringAsFixed(1)} s',
      'speed': speed == null ? '-' : mbps(speed * 8),
    });
  }

  static String? _audioCodec(PlayerState s) {
    for (final t in s.tracks.audio) {
      if (t.codec != null && t.id != 'auto' && t.id != 'no') {
        return t.codec!.toUpperCase();
      }
    }
    return null;
  }

  // --------------------------------------------------- Mise en veille

  void setSleepTimer(Duration? d) {
    _sleep?.cancel();
    sleepAt = d == null ? null : DateTime.now().add(d);
    if (d != null) {
      _sleep = Timer(d, () {
        sleepAt = null;
        stop();
      });
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _reportProgress();
    _retry?.cancel();
    _current = null;
    retries = 0;
    lastError = null;
    notifyListeners();
    await player.stop();
  }

  @override
  void dispose() {
    settings.removeListener(_settingsListener);
    _retry?.cancel();
    _watchdog?.cancel();
    _progressTimer?.cancel();
    _sleep?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
