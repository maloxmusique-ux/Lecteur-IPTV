import 'dart:io';

import 'package:flutter/services.dart';

import '../player/player_engine.dart';
import '../state/settings.dart';

/// Mini-lecteur flottant (image dans l'image) sur Android : arme l'entree
/// automatique tant qu'une video joue, pour qu'elle continue dans une
/// petite fenetre deplacable quand on quitte l'app.
class PipController {
  PipController(this.engine, this.settings) {
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
