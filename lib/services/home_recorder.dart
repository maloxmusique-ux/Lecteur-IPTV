import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'recorder.dart';

/// Enregistreur maison : un appareil Canalix toujours allume a la maison
/// (boite Android TV, ordinateur, vieux telephone branche) enregistre pour
/// les autres ecrans (tele Samsung/LG, iPhone...), meme quand ils sont
/// eteints. Tout reste sur le reseau local de la personne.
const homePort = 8765;

/// Etat d'un enregistrement vu depuis un autre appareil (sans les adresses
/// de flux ni les mots de passe).
Map<String, dynamic> _publicRec(Recording r) => {
      'id': r.id,
      'title': r.title,
      'channel': r.channel.name,
      'chId': r.channel.id,
      'src': r.sourceId,
      'logo': r.channel.logo,
      'kind': r.kind.index,
      'start': r.start,
      'stop': r.stop,
      'ps': r.progStart,
      'status': r.status.name,
      'bytes': r.bytes,
      'rule': r.ruleId,
      'error': r.error,
      'ext': r.path.contains('.') ? r.path.split('.').last : 'ts',
    };

Map<String, dynamic> _publicRule(RecRule r) => {
      'id': r.id,
      'title': r.title,
      'channel': r.channel.name,
      'chId': r.channel.id,
      'src': r.sourceId,
      'mode': r.mode.name,
      'weekday': r.weekday,
      'minute': r.minuteOfDay,
    };

// ------------------------------------------------------------------ Serveur

/// Cote enregistreur : petit serveur HTTP sur le reseau local.
class HomeServer extends ChangeNotifier {
  final RecordingService recorder;
  HomeServer(this.recorder);

  late SharedPreferences _prefs;
  HttpServer? _server;
  bool enabled = false;
  String code = '';
  String name = '';
  String error = '';
  List<String> addresses = [];

  /// Protection contre les essais de code au hasard.
  int _fails = 0;
  DateTime _lockedUntil = DateTime(2000);

  static bool get supported =>
      !kIsWeb && !Platform.isIOS; // Apple coupe les apps en arriere-plan.

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    code = _prefs.getString('home_code') ?? '';
    if (code.isEmpty) {
      code = _newCode();
      await _prefs.setString('home_code', code);
    }
    name = _prefs.getString('home_name') ?? '';
    if (name.isEmpty) name = _defaultName();
    enabled = supported && (_prefs.getBool('home_on') ?? false);
    if (enabled) await _start();
  }

  static String _newCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  static String _defaultName() {
    try {
      final h = Platform.localHostname;
      if (h.isNotEmpty && h != 'localhost') return h.split('.').first;
    } catch (_) {}
    if (Platform.isAndroid) return 'Canalix Android';
    if (Platform.isWindows) return 'Canalix PC';
    if (Platform.isMacOS) return 'Canalix Mac';
    return 'Canalix';
  }

  Future<void> setEnabled(bool on) async {
    if (!supported) return;
    enabled = on;
    await _prefs.setBool('home_on', on);
    if (on) {
      await _start();
    } else {
      await _server?.close(force: true);
      _server = null;
    }
    recorder.setKeepAlive(on);
    notifyListeners();
  }

  Future<void> setName(String v) async {
    name = v.trim().isEmpty ? _defaultName() : v.trim();
    await _prefs.setString('home_name', name);
    notifyListeners();
  }

  Future<void> newCode() async {
    code = _newCode();
    await _prefs.setString('home_code', code);
    notifyListeners();
  }

  Future<void> _start() async {
    if (_server != null) return;
    error = '';
    try {
      final s = await HttpServer.bind(InternetAddress.anyIPv4, homePort,
          shared: true);
      _server = s;
      s.listen(_handle, onError: (_) {});
      recorder.setKeepAlive(true);
    } catch (e) {
      error = '$e';
    }
    await refreshAddresses();
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    addresses = await localIPv4();
    notifyListeners();
  }

  bool _authorized(HttpRequest req) {
    final k = req.headers.value('x-canalix-key') ??
        req.uri.queryParameters['k'] ??
        '';
    if (DateTime.now().isBefore(_lockedUntil)) return false;
    if (k == code) {
      _fails = 0;
      return true;
    }
    if (++_fails >= 10) {
      _fails = 0;
      _lockedUntil = DateTime.now().add(const Duration(minutes: 10));
    }
    return false;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    // L'app tele (page web) appelle depuis une autre origine.
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', 'content-type, x-canalix-key')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = 204;
        await res.close();
        return;
      }
      final path = req.uri.path;
      if (path == '/api/ping') {
        return await _json(res, {'app': 'canalix', 'name': name, 'v': 1});
      }
      if (!_authorized(req)) {
        res.statusCode = 401;
        return await _json(res, {'error': 'code'});
      }
      if (path.startsWith('/files/')) return await _file(req, path.substring(7));
      final body = req.method == 'POST'
          ? (jsonDecode(await utf8.decodeStream(req)) as Map?)
                  ?.cast<String, dynamic>() ??
              const <String, dynamic>{}
          : const <String, dynamic>{};
      switch (path) {
        case '/api/list':
          final st = await recorder.storage();
          return await _json(res, {
            'name': name,
            'items': [
              for (final r in recorder.items)
                if (r.kind == RecKind.live || r.finished) _publicRec(r)
            ],
            'rules': [for (final r in recorder.rules) _publicRule(r)],
            'storage': st == null
                ? null
                : {'free': st.free, 'total': st.total, 'used': st.used},
          });
        case '/api/schedule':
          final r = recorder.scheduleProgramme(
              _source(body), _channel(body), _programme(body['p']));
          return await _json(res, {'id': r.id});
        case '/api/rule':
          final mode = RecRepeat.values.firstWhere(
              (m) => m.name == body['mode'],
              orElse: () => RecRepeat.weekly);
          final rule = recorder.addRule(
              _source(body), _channel(body), _programme(body['p']), mode);
          return await _json(res, {'id': rule.id});
        case '/api/occurrences':
          // Diffusions trouvees dans le guide de l'autre appareil.
          final rule = recorder.ruleById('${body['rule']}');
          if (rule != null) {
            for (final o in (body['list'] as List? ?? const [])) {
              final p = _programme(o);
              recorder.addOccurrence(rule, p);
            }
          }
          return await _json(res, {'ok': rule != null});
        case '/api/now':
          final minutes = (body['minutes'] as num?)?.toInt() ?? 60;
          final r = recorder.recordNow(_source(body), _channel(body),
              Duration(minutes: minutes.clamp(1, 24 * 60)),
              title: body['title'] as String?);
          return await _json(res, {'id': r.id});
        case '/api/stop':
          final r = _find(body['id']);
          if (r != null) recorder.stopRecording(r);
          return await _json(res, {'ok': r != null});
        case '/api/delete':
          final r = _find(body['id']);
          if (r != null) await recorder.delete(r);
          return await _json(res, {'ok': r != null});
        case '/api/unrule':
          final rule = recorder.ruleById('${body['id']}');
          if (rule != null) recorder.removeRule(rule);
          return await _json(res, {'ok': rule != null});
      }
      res.statusCode = 404;
      await _json(res, {'error': 'not found'});
    } catch (e) {
      try {
        res.statusCode = 400;
        await _json(res, {'error': '$e'});
      } catch (_) {}
    }
  }

  Recording? _find(Object? id) =>
      recorder.items.where((r) => r.id == '$id').firstOrNull;

  Source _source(Map<String, dynamic> b) {
    final s = (b['src'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Source(
      id: '${s['id'] ?? 'remote'}',
      name: '${s['name'] ?? ''}',
      kind: SourceKind.m3u,
      url: '',
      userAgent: '${s['ua'] ?? ''}',
    );
  }

  Channel _channel(Map<String, dynamic> b) =>
      Channel.fromJson((b['ch'] as Map).cast<String, dynamic>());

  Programme _programme(Object? o) {
    final p = (o as Map?)?.cast<String, dynamic>() ?? const {};
    return Programme((p['start'] as num).toInt(), (p['stop'] as num).toInt(),
        '${p['title'] ?? ''}', '');
  }

  Future<void> _json(HttpResponse res, Object body) async {
    res.headers.set('content-type', 'application/json; charset=utf-8');
    res.write(jsonEncode(body));
    await res.close();
  }

  /// Envoie le fichier video, avec reprise (Range) pour pouvoir avancer.
  Future<void> _file(HttpRequest req, String id) async {
    final res = req.response;
    final r = _find(id.split('.').first);
    final f = r == null || r.path.isEmpty ? null : File(r.path);
    if (f == null || !await f.exists()) {
      res.statusCode = 404;
      await res.close();
      return;
    }
    final len = await f.length();
    final ext = r!.path.split('.').last.toLowerCase();
    res.headers
      ..set('Content-Type', switch (ext) {
        'mp4' || 'm4v' => 'video/mp4',
        'mkv' => 'video/x-matroska',
        _ => 'video/mp2t',
      })
      ..set('Accept-Ranges', 'bytes');
    var start = 0, end = len - 1;
    final range = req.headers.value('range');
    final m = range == null
        ? null
        : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
    if (m != null) {
      if (m[1]!.isNotEmpty) start = int.parse(m[1]!);
      if (m[2]!.isNotEmpty) end = min(int.parse(m[2]!), len - 1);
      if (m[1]!.isEmpty && m[2]!.isNotEmpty) {
        start = max(0, len - int.parse(m[2]!));
        end = len - 1;
      }
      if (start > end || start >= len) {
        res.statusCode = 416;
        res.headers.set('Content-Range', 'bytes */$len');
        await res.close();
        return;
      }
      res.statusCode = 206;
      res.headers.set('Content-Range', 'bytes $start-$end/$len');
    }
    res.contentLength = end - start + 1;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(f.openRead(start, end + 1));
    await res.close();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }
}

/// Adresses IPv4 du reseau local de cet appareil.
Future<List<String>> localIPv4() async {
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final out = <String>[];
    for (final i in list) {
      for (final a in i.addresses) {
        final ip = a.address;
        if (a.isLoopback || ip.startsWith('169.254.')) continue;
        if (ip.startsWith('10.') ||
            ip.startsWith('192.168.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
          out.add(ip);
        }
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

// ------------------------------------------------------------------- Client

class FoundRecorder {
  final String host;
  final String name;
  const FoundRecorder(this.host, this.name);
}

/// Enregistrement vu sur l'enregistreur maison.
class RemoteRec {
  final Map<String, dynamic> j;
  RemoteRec(this.j);
  String get id => '${j['id']}';
  String get title => '${j['title']}';
  String get channel => '${j['channel']}';
  String get chId => '${j['chId']}';
  String get logo => '${j['logo'] ?? ''}';
  int get start => (j['start'] as num).toInt();
  int get stop => (j['stop'] as num).toInt();
  int get bytes => (j['bytes'] as num?)?.toInt() ?? 0;
  String get ruleId => '${j['rule'] ?? ''}';
  String get ext => '${j['ext'] ?? 'ts'}';
  RecStatus get status => RecStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => RecStatus.failed);
  bool get active => status == RecStatus.recording;
  bool get finished => !active && status != RecStatus.scheduled;
}

class RemoteRule {
  final Map<String, dynamic> j;
  RemoteRule(this.j);
  String get id => '${j['id']}';
  String get title => '${j['title']}';
  String get channel => '${j['channel']}';
  String get chId => '${j['chId']}';
  String get src => '${j['src']}';
  RecRepeat get mode => RecRepeat.values
      .firstWhere((m) => m.name == j['mode'], orElse: () => RecRepeat.weekly);
  int get weekday => (j['weekday'] as num?)?.toInt() ?? 1;
  int get minute => (j['minute'] as num?)?.toInt() ?? 0;
}

/// Cote ecran : envoie les enregistrements a l'enregistreur maison.
class HomeClient extends ChangeNotifier {
  late SharedPreferences _prefs;
  String host = '';
  String name = '';
  String code = '';

  /// true = les enregistrements de direct partent a l'enregistreur maison.
  bool get paired => host.isNotEmpty && code.isNotEmpty;

  bool online = false;
  String error = '';
  List<RemoteRec> items = [];
  List<RemoteRule> rules = [];
  ({int free, int total, int used})? storage;
  Timer? _poll;
  int _listeners = 0;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    host = _prefs.getString('homec_host') ?? '';
    name = _prefs.getString('homec_name') ?? '';
    code = _prefs.getString('homec_code') ?? '';
    if (paired) unawaited(refresh());
  }

  String get _base => 'http://$host:$homePort';
  Map<String, String> get _h =>
      {'x-canalix-key': code, 'content-type': 'application/json'};

  /// Adresse de lecture d'un enregistrement termine ou en cours.
  String fileUrl(RemoteRec r) => '$_base/files/${r.id}.${r.ext}?k=$code';

  /// Cherche les enregistreurs Canalix sur le reseau local.
  static Future<List<FoundRecorder>> scan() async {
    final mine = await localIPv4();
    final found = <FoundRecorder>[];
    final seen = <String>{};
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 900);
    Future<void> probe(String ip) async {
      try {
        final req = await client
            .getUrl(Uri.parse('http://$ip:$homePort/api/ping'))
            .timeout(const Duration(milliseconds: 1200));
        final res = await req.close().timeout(const Duration(seconds: 2));
        final j = jsonDecode(await utf8.decodeStream(res)) as Map;
        if (j['app'] == 'canalix' && seen.add(ip)) {
          found.add(FoundRecorder(ip, '${j['name']}'));
        }
      } catch (_) {}
    }

    // Cet appareil lui-meme d'abord (utile pour verifier).
    final targets = <String>[];
    for (final ip in mine) {
      final base = ip.substring(0, ip.lastIndexOf('.') + 1);
      for (var i = 1; i < 255; i++) {
        targets.add('$base$i');
      }
    }
    const batch = 64;
    for (var i = 0; i < targets.length; i += batch) {
      await Future.wait(targets.skip(i).take(batch).map(probe));
    }
    client.close(force: true);
    return found;
  }

  /// Verifie le code et retient l'enregistreur.
  Future<bool> pair(String host, String name, String code) async {
    try {
      final r = await http.get(Uri.parse('http://$host:$homePort/api/list'),
          headers: {'x-canalix-key': code}).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return false;
    } catch (_) {
      return false;
    }
    this.host = host;
    this.name = name;
    this.code = code;
    await _prefs.setString('homec_host', host);
    await _prefs.setString('homec_name', name);
    await _prefs.setString('homec_code', code);
    await refresh();
    return true;
  }

  Future<void> forget() async {
    host = name = code = '';
    items = [];
    rules = [];
    storage = null;
    online = false;
    await _prefs.remove('homec_host');
    await _prefs.remove('homec_name');
    await _prefs.remove('homec_code');
    notifyListeners();
  }

  /// Rafraichit la liste toutes les 10 s tant qu'un ecran l'affiche.
  void watch() {
    _listeners++;
    _poll ??= Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    refresh();
  }

  void unwatch() {
    if (--_listeners <= 0) {
      _listeners = 0;
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> refresh() async {
    if (!paired) return;
    try {
      final r = await http
          .get(Uri.parse('$_base/api/list'), headers: _h)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 401) {
        online = false;
        error = 'code';
      } else {
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        items = [
          for (final e in (j['items'] as List? ?? const []))
            RemoteRec((e as Map).cast<String, dynamic>())
        ];
        rules = [
          for (final e in (j['rules'] as List? ?? const []))
            RemoteRule((e as Map).cast<String, dynamic>())
        ];
        final s = j['storage'] as Map?;
        storage = s == null
            ? null
            : (
                free: (s['free'] as num).toInt(),
                total: (s['total'] as num).toInt(),
                used: (s['used'] as num).toInt(),
              );
        if ((j['name'] as String?)?.isNotEmpty == true) name = j['name'];
        online = true;
        error = '';
      }
    } catch (_) {
      online = false;
      error = 'offline';
    }
    notifyListeners();
  }

  Future<bool> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = await http
          .post(Uri.parse('$_base$path'), headers: _h, body: jsonEncode(body))
          .timeout(const Duration(seconds: 8));
      await refresh();
      return r.statusCode == 200;
    } catch (_) {
      online = false;
      notifyListeners();
      return false;
    }
  }

  Map<String, dynamic> _src(Source s) =>
      {'id': s.id, 'name': s.name, 'ua': s.userAgent};
  Map<String, dynamic> _p(Programme p) =>
      {'start': p.start, 'stop': p.stop, 'title': p.title};

  Future<bool> schedule(Source s, Channel c, Programme p) => _post(
      '/api/schedule', {'src': _src(s), 'ch': c.toJson(), 'p': _p(p)});

  Future<bool> addRule(
      Source s, Channel c, Programme p, RecRepeat mode, EpgData epg) async {
    try {
      final r = await http
          .post(Uri.parse('$_base/api/rule'),
              headers: _h,
              body: jsonEncode({
                'src': _src(s),
                'ch': c.toJson(),
                'p': _p(p),
                'mode': mode.name,
              }))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return false;
      await refresh();
      await pushGuide(s.id, epg, (id) => id == c.id ? c : null);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> recordNow(Source s, Channel c, Duration d, {String? title}) =>
      _post('/api/now', {
        'src': _src(s),
        'ch': c.toJson(),
        'minutes': d.inMinutes,
        'title': ?title,
      });

  Future<bool> stop(RemoteRec r) => _post('/api/stop', {'id': r.id});
  Future<bool> delete(RemoteRec r) => _post('/api/delete', {'id': r.id});
  Future<bool> removeRule(RemoteRule r) => _post('/api/unrule', {'id': r.id});

  bool isScheduled(String sourceId, Channel c, Programme p) => items.any((r) =>
      r.j['src'] == sourceId &&
      r.chId == c.id &&
      !r.finished &&
      r.start <= p.start &&
      r.stop >= p.stop - 60000);

  Iterable<RemoteRec> covering(String sourceId, Channel c, Programme p) =>
      items.where((r) =>
          r.j['src'] == sourceId &&
          r.chId == c.id &&
          !r.finished &&
          r.start <= p.start &&
          r.stop >= p.stop - 60000);

  /// Les series « chaque diffusion » de l'enregistreur suivent le guide de
  /// cet ecran : on lui envoie les prochaines diffusions trouvees.
  Future<void> pushGuide(
      String sourceId, EpgData epg, Channel? Function(String id) lookup) async {
    if (!paired || epg.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final horizon = now + const Duration(days: 8).inMilliseconds;
    for (final rule in rules) {
      if (rule.mode != RecRepeat.everyAiring || rule.src != sourceId) continue;
      final ch = lookup(rule.chId);
      if (ch == null) continue;
      final list = epg.forChannel(ch) ?? const <Programme>[];
      final want = RecRule.normalize(rule.title);
      final matches = [
        for (final p in list)
          if (p.stop > now && p.start < horizon && RecRule.normalize(p.title) == want)
            _p(p)
      ];
      if (matches.isEmpty) continue;
      try {
        await http
            .post(Uri.parse('$_base/api/occurrences'),
                headers: _h,
                body: jsonEncode({'rule': rule.id, 'list': matches}))
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
