import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/models.dart';
import '../services/net.dart';

/// Moteur de lecture unique, partage par toute l'application.
///
/// Points cles pour la fluidite :
/// * Une seule instance libmpv reutilisee : changer de chaine ne recree
///   jamais le lecteur ni la surface video, d'ou un zapping quasi instantane.
/// * Decodage materiel (hwdec) active sur toutes les plateformes.
/// * Sondage du flux raccourci et cache reseau tuned pour l'IPTV live.
/// * Reconnexion automatique en cas de coupure du flux.
/// * Le meme [VideoController] sert a l'apercu et au plein ecran :
///   passer en plein ecran ne relance pas le flux.
class PlayerEngine extends ChangeNotifier {
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
  StreamSubscription<String>? _errSub;
  StreamSubscription<Duration>? _posSub;
  Timer? _retry;
  int _retries = 0;

  PlayerEngine() {
    final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    player = Player(
      configuration: PlayerConfiguration(
        // Cache demuxer plus large sur desktop pour absorber les micro-coupures.
        bufferSize: (mobile ? 48 : 128) * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    video = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _tune();
    _errSub = player.stream.error.listen(_onError);
    // Si la lecture avance, le flux est sain : on efface l'erreur.
    _posSub = player.stream.position.listen((pos) {
      if (lastError != null && pos > const Duration(seconds: 1)) {
        lastError = null;
        _retries = 0;
        _retry?.cancel();
        notifyListeners();
      }
    });
  }

  Future<void> _tune() async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    final opts = <String, String>{
      // Demarrage rapide : on n'attend pas de remplir le cache.
      'cache': 'yes',
      'cache-pause-initial': 'no',
      'cache-pause-wait': '1',
      'demuxer-readahead-secs': '20',
      'demuxer-max-back-bytes': '${16 * 1024 * 1024}',
      // Analyse du flux TS/HLS reduite (zapping plus rapide).
      'demuxer-lavf-analyzeduration': '1.5',
      'demuxer-lavf-probesize': '${1024 * 1024}',
      // Reseau robuste.
      'network-timeout': '15',
      'stream-lavf-o':
          'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
              'reconnect_delay_max=4',
      'hls-bitrate': 'max',
      // Rendu fluide.
      'video-sync': 'audio',
      'framedrop': 'vo',
      'deinterlace': 'auto',
      'keep-open': 'no',
    };
    for (final e in opts.entries) {
      try {
        await p.setProperty(e.key, e.value);
      } catch (_) {
        // Option non supportee par cette build de libmpv : on ignore.
      }
    }
  }

  void setUserAgent(String ua) => _userAgent = ua;

  /// Lance une entree. Si [queue] est fourni, active le zapping.
  Future<void> play(Channel c, {List<Channel>? queue}) async {
    if (queue != null) {
      _queue = queue;
      _index = queue.indexWhere((e) => e.id == c.id);
    }
    _current = c;
    lastError = null;
    _retries = 0;
    _retry?.cancel();
    notifyListeners();
    await _open(c);
  }

  Future<void> _open(Channel c) async {
    final headers = <String, String>{
      'User-Agent': _userAgent.isEmpty ? defaultUserAgent : _userAgent,
      ...c.headers,
    };
    await player.open(Media(c.url, httpHeaders: headers), play: true);
  }

  Future<void> next() => _step(1);
  Future<void> previous() => _step(-1);

  Future<void> _step(int d) async {
    if (_queue.isEmpty) return;
    _index = (_index + d) % _queue.length;
    if (_index < 0) _index += _queue.length;
    await play(_queue[_index]);
  }

  void _onError(String e) {
    // Les erreurs de peripherique audio ne signifient pas que le flux est mort.
    final lower = e.toLowerCase();
    if (lower.contains('audio') || lower.contains('ao/')) return;
    lastError = e;
    notifyListeners();
    // Pour le live, on retente automatiquement (flux qui tombe).
    final c = _current;
    if (c != null && c.type == ContentType.live && _retries < 3) {
      _retries++;
      _retry?.cancel();
      _retry = Timer(Duration(seconds: _retries * 2), () {
        if (_current?.id == c.id) _open(c);
      });
    }
  }

  Future<void> stop() async {
    _retry?.cancel();
    _current = null;
    notifyListeners();
    await player.stop();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _errSub?.cancel();
    _posSub?.cancel();
    player.dispose();
    super.dispose();
  }
}
