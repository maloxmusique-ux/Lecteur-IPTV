import 'dart:io';

import 'package:flutter/services.dart';

import '../models/models.dart';
import '../player/player_engine.dart';
import 'cast.dart' show castMediaFor;
import '../state/settings.dart';

/// Mini-lecteur flottant (image dans l'image) sur Android : arme l'entree
/// automatique tant qu'une video joue, pour qu'elle continue dans une
/// petite fenetre deplacable quand on quitte l'app.
class PipController {
  PipController(this.engine, this.settings) {
    if (Platform.isIOS) IosMiniPlayer.init(engine);
    if (!Platform.isAndroid) return;
    engine.addListener(_sync);
    settings.addListener(_sync);
    engine.player.stream.playing.listen((_) => _sync());
    engine.player.stream.width.listen((_) => _sync());
  }

  final PlayerEngine engine;
  final Settings settings;
  static const _ch = MethodChannel('streamflow/pip');
  String? _last;

  void _sync() {
    final st = engine.player.state;
    final on = settings.autoPip && engine.current != null && st.playing;
    final w = st.width ?? 16, h = st.height ?? 9;
    final key = '$on:$w:$h';
    if (key == _last) return;
    _last = key;
    _ch.invokeMethod('auto', {'enabled': on, 'w': w, 'h': h}).catchError((_) => null);
  }
}

/// iPhone : la fenetre flottante d'Apple n'accepte que son propre lecteur.
/// On lui passe la chaine, elle s'envole directement dans la petite
/// fenetre ; « revenir dans l'app » reprend la lecture dans Canalix.
class IosMiniPlayer {
  IosMiniPlayer._();
  static const _ch = MethodChannel('canalix/pip');
  static PlayerEngine? _engine;
  static Channel? _channel;

  static void init(PlayerEngine engine) {
    _engine = engine;
    _ch.setMethodCallHandler((call) async {
      final e = _engine, c = _channel;
      if (e == null || c == null) return;
      if (call.method == 'restore') {
        final pos = ((call.arguments as Map?)?['position'] as num?)?.toDouble() ?? 0;
        if (c.type == ContentType.live) {
          await e.play(c);
        } else {
          await e.play(c, startAt: Duration(milliseconds: (pos * 1000).round()));
        }
      }
    });
  }

  /// Lance la fenetre flottante. false = impossible (on garde Canalix).
  static Future<bool> start(Channel c,
      {String userAgent = '', Duration position = Duration.zero}) async {
    _channel = c;
    final (url, _, _) = castMediaFor(c);
    try {
      return await _ch.invokeMethod<bool>('start', {
            'url': url,
            'userAgent': userAgent,
            'position': c.type == ContentType.live ? 0.0 : position.inMilliseconds / 1000,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
