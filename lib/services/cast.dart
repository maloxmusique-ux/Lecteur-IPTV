import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';

import '../models/models.dart';

/// Un Chromecast (ou televiseur Google TV) trouve sur le reseau.
class CastDevice {
  final String name;
  final String host;
  final int port;
  const CastDevice(this.name, this.host, this.port);

  @override
  bool operator ==(Object other) =>
      other is CastDevice && other.host == host && other.port == port;
  @override
  int get hashCode => Object.hash(host, port);
}

/// Resultat d'une recherche : appareils Cast, et autres televiseurs vus
/// sur le reseau qui n'ont pas Chromecast (ex. Samsung, LG).
class CastScan {
  final List<CastDevice> devices;
  final List<String> otherTvs;
  const CastScan(this.devices, this.otherTvs);
}

/// Recherche complete, avec trois methodes en parallele car le multicast
/// est souvent bloque (pare-feu Windows, routeurs, adaptateurs virtuels) :
/// 1. mDNS "_googlecast._tcp" (methode officielle) ;
/// 2. SSDP/DIAL (repond aussi pour les televiseurs sans Chromecast) ;
/// 3. balayage du reseau local : port 8009 (protocole Cast, en TLS).
Future<CastScan> scanForCast(
    {@visibleForTesting List<InternetAddress>? interfaces}) async {
  final ifaces = interfaces ?? await _localIPv4();
  final results = await Future.wait([
    discoverCastDevices().catchError((_) => <CastDevice>[]),
    _ssdp(ifaces).catchError((_) => <String, (String, String)>{}),
    _sweep(ifaces).catchError((_) => <String>[]),
  ]);
  final mdns = results[0] as List<CastDevice>;
  final ssdp = results[1] as Map<String, (String, String)>;
  final open8009 = results[2] as List<String>;

  final byHost = <String, CastDevice>{for (final d in mdns) d.host: d};
  for (final ip in {...open8009, ...ssdp.keys}) {
    if (byHost.containsKey(ip)) continue;
    if (!open8009.contains(ip) && !await _isCast(ip)) continue;
    final name = await _eurekaName(ip) ?? ssdp[ip]?.$1 ?? 'Chromecast ($ip)';
    byHost[ip] = CastDevice(name, ip, 8009);
  }
  final others = <String>[
    for (final e in ssdp.entries)
      if (!byHost.containsKey(e.key) && e.value.$2.isNotEmpty)
        '${e.value.$1} (${e.value.$2})',
  ];
  return CastScan(
      byHost.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
      others.toSet().toList()..sort());
}

/// Adresses IPv4 privees de l'appareil (Wi-Fi, Ethernet).
Future<List<InternetAddress>> _localIPv4() async {
  final out = <InternetAddress>[];
  try {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      final n = i.name.toLowerCase();
      if (n.contains('vethernet') || n.contains('virtualbox') ||
          n.contains('vmware') || n.contains('wsl') || n.startsWith('docker') ||
          n.startsWith('br-') || n.contains('loopback')) {
        continue;
      }
      for (final a in i.addresses) {
        final b = a.rawAddress;
        final private = b[0] == 10 ||
            (b[0] == 192 && b[1] == 168) ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31);
        if (private) out.add(a);
      }
    }
  } catch (_) {}
  return out.take(4).toList();
}

/// SSDP : ip -> (nom, fabricant si c'est un televiseur sans Cast).
Future<Map<String, (String, String)>> _ssdp(List<InternetAddress> ifaces) async {
  final locations = <String, String>{};
  final sockets = <RawDatagramSocket>[];
  final group = InternetAddress('239.255.255.250');
  for (final a in [...ifaces, InternetAddress.anyIPv4]) {
    try {
      final sock = await RawDatagramSocket.bind(a, 0);
      sockets.add(sock);
      sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = sock.receive();
        if (d == null) return;
        final text = latin1.decode(d.data, allowInvalid: true);
        final m = RegExp(r'^location:\s*(\S+)', caseSensitive: false, multiLine: true)
            .firstMatch(text);
        if (m != null) locations[d.address.address] = m.group(1)!;
      });
      for (final st in const [
        'urn:dial-multiscreen-org:service:dial:1',
        'urn:schemas-upnp-org:device:MediaRenderer:1',
      ]) {
        final msg = 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\nMX: 2\r\nST: $st\r\n\r\n';
        sock.send(utf8.encode(msg), group, 1900);
      }
    } catch (_) {}
  }
  await Future<void>.delayed(const Duration(milliseconds: 2500));
  for (final s in sockets) {
    s.close();
  }
  final out = <String, (String, String)>{};
  await Future.wait(locations.entries.map((e) async {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await c.getUrl(Uri.parse(e.value));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final xml = await res.transform(utf8.decoder).join();
      c.close(force: true);
      String tag(String t) =>
          RegExp('<$t>([^<]*)</$t>').firstMatch(xml)?.group(1)?.trim() ?? '';
      final maker = tag('manufacturer');
      final type = tag('deviceType').toLowerCase();
      final tv = type.contains('mediarenderer') || type.contains('tv') ||
          RegExp('samsung|lg |lg electronics|sony|roku|vizio|hisense|tcl|philips|panasonic',
                  caseSensitive: false)
              .hasMatch(maker);
      out[e.key] = (tag('friendlyName'), tv ? maker : '');
    } catch (_) {}
  }));
  return out;
}

/// Balaye le /24 de chaque interface a la recherche du port Cast (8009).
Future<List<String>> _sweep(List<InternetAddress> ifaces) async {
  final targets = <String>{};
  for (final a in ifaces) {
    final b = a.rawAddress;
    for (var i = 1; i < 255; i++) {
      if (i != b[3]) targets.add('${b[0]}.${b[1]}.${b[2]}.$i');
    }
  }
  final open = <String>[];
  final list = targets.toList();
  const batch = 96;
  for (var i = 0; i < list.length; i += batch) {
    await Future.wait(list.skip(i).take(batch).map((ip) async {
      try {
        final s = await Socket.connect(ip, 8009,
            timeout: const Duration(milliseconds: 600));
        s.destroy();
        if (await _isCast(ip)) open.add(ip);
      } catch (_) {}
    }));
  }
  return open;
}

/// Le port 8009 parle TLS sur un appareil Cast.
Future<bool> _isCast(String ip) async {
  try {
    final s = await SecureSocket.connect(ip, 8009,
        onBadCertificate: (_) => true, timeout: const Duration(seconds: 2));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Nom donne a l'appareil dans Google Home.
Future<String?> _eurekaName(String ip) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final req = await c.getUrl(
        Uri.parse('http://$ip:8008/setup/eureka_info?params=name'));
    final res = await req.close().timeout(const Duration(seconds: 2));
    final body = await res.transform(utf8.decoder).join();
    c.close(force: true);
    final n = (jsonDecode(body) as Map)['name'];
    return n is String && n.isNotEmpty ? n : null;
  } catch (_) {
    return null;
  }
}

/// Recherche des appareils Google Cast (mDNS "_googlecast._tcp").
Future<List<CastDevice>> discoverCastDevices(
    {Duration timeout = const Duration(seconds: 4)}) async {
  const bg = MethodChannel('streamflow/background');
  if (Platform.isAndroid) {
    // Android filtre le multicast sans ce verrou.
    try {
      await bg.invokeMethod('multicastLock', true);
    } catch (_) {}
  }
  final found = <CastDevice>{};
  final client = MDnsClient();
  try {
    await client.start();
    const service = '_googlecast._tcp.local';
    final ptrs = await client
        .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(service),
            timeout: timeout)
        .toList();
    for (final ptr in ptrs) {
      var name = ptr.domainName.split('._googlecast').first;
      // Nom lisible dans le TXT (cle "fn").
      final txt = await client
          .lookup<TxtResourceRecord>(ResourceRecordQuery.text(ptr.domainName),
              timeout: const Duration(seconds: 1))
          .toList();
      for (final t in txt) {
        for (final line in t.text.split('\n')) {
          if (line.startsWith('fn=')) name = line.substring(3);
        }
      }
      final srvs = await client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName),
              timeout: const Duration(seconds: 1))
          .toList();
      for (final srv in srvs) {
        final ips = await client
            .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
                timeout: const Duration(seconds: 1))
            .toList();
        final host = ips.isNotEmpty ? ips.first.address.address : srv.target;
        found.add(CastDevice(name, host, srv.port));
      }
    }
  } catch (_) {
    // Reseau sans multicast : l'utilisateur peut entrer l'adresse a la main.
  } finally {
    client.stop();
    if (Platform.isAndroid) {
      try {
        await bg.invokeMethod('multicastLock', false);
      } catch (_) {}
    }
  }
  return found.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// Adapte l'adresse d'un flux pour le Chromecast : les flux Xtream en
/// MPEG-TS sont demandes en HLS (.m3u8), seul format direct qu'il lit.
(String, String, bool) castMediaFor(Channel c) {
  var url = c.url;
  final live = c.type == ContentType.live;
  final lower = url.toLowerCase();
  if ((url.contains('/live/') || url.contains('/timeshift/')) &&
      lower.endsWith('.ts')) {
    url = '${url.substring(0, url.length - 3)}.m3u8';
  }
  final l = url.toLowerCase();
  final type = l.contains('.m3u8')
      ? 'application/x-mpegURL'
      : l.endsWith('.mp4') || l.endsWith('.m4v')
          ? 'video/mp4'
          : l.endsWith('.mkv')
              ? 'video/x-matroska'
              : l.endsWith('.webm')
                  ? 'video/webm'
                  : 'video/mp2t';
  return (url, type, live);
}

enum CastState { idle, connecting, playing, paused, buffering, error }

/// Session de diffusion vers un Chromecast (protocole Cast v2).
class CastSession extends ChangeNotifier {
  CastSession._();
  static final instance = CastSession._();

  static const _ns = (
    conn: 'urn:x-cast:com.google.cast.tp.connection',
    beat: 'urn:x-cast:com.google.cast.tp.heartbeat',
    recv: 'urn:x-cast:com.google.cast.receiver',
    media: 'urn:x-cast:com.google.cast.media',
  );
  static const _appId = 'CC1AD845'; // Lecteur multimedia par defaut de Google.

  SecureSocket? _socket;
  Timer? _ping;
  final _buffer = BytesBuilder();
  int _req = 1;
  String? _transport;
  int? _mediaSession;
  Completer<String>? _launch;

  CastDevice? device;
  Channel? item;
  CastState state = CastState.idle;
  String? error;

  bool get active => device != null && state != CastState.idle;

  Future<void> play(CastDevice d, Channel c) async {
    if (device != d || _socket == null) {
      await stop();
      device = d;
      state = CastState.connecting;
      error = null;
      notifyListeners();
      try {
        _socket = await SecureSocket.connect(d.host, d.port,
            onBadCertificate: (_) => true,
            timeout: const Duration(seconds: 8));
      } catch (e) {
        _fail('connect');
        return;
      }
      _socket!.listen(_onData, onError: (_) => _fail('socket'), onDone: () {
        if (state != CastState.idle) _fail('closed');
      });
      _send('receiver-0', _ns.conn, {'type': 'CONNECT'});
      _ping = Timer.periodic(const Duration(seconds: 5),
          (_) => _send('receiver-0', _ns.beat, {'type': 'PING'}));
    }
    item = c;
    state = CastState.connecting;
    notifyListeners();
    try {
      _transport ??= await _launchApp();
    } catch (_) {
      _fail('launch');
      return;
    }
    final (url, type, live) = castMediaFor(c);
    _send(_transport!, _ns.media, {
      'type': 'LOAD',
      'requestId': _req++,
      'autoplay': true,
      'media': {
        'contentId': url,
        'contentUrl': url,
        'contentType': type,
        'streamType': live ? 'LIVE' : 'BUFFERED',
        'metadata': {
          'metadataType': 0,
          'title': c.name,
          if (c.logo.isNotEmpty) 'images': [{'url': c.logo}],
        },
      },
    });
  }

  Future<String> _launchApp() {
    _launch = Completer<String>();
    _send('receiver-0', _ns.recv,
        {'type': 'LAUNCH', 'appId': _appId, 'requestId': _req++});
    return _launch!.future.timeout(const Duration(seconds: 15));
  }

  void pauseResume() {
    if (_transport == null || _mediaSession == null) return;
    _send(_transport!, _ns.media, {
      'type': state == CastState.paused ? 'PLAY' : 'PAUSE',
      'mediaSessionId': _mediaSession,
      'requestId': _req++,
    });
  }

  void setVolume(double level) {
    _send('receiver-0', _ns.recv, {
      'type': 'SET_VOLUME',
      'volume': {'level': level.clamp(0.0, 1.0)},
      'requestId': _req++,
    });
  }

  Future<void> stop() async {
    if (_socket != null) {
      try {
        _send('receiver-0', _ns.recv, {'type': 'STOP', 'requestId': _req++});
        await _socket!.flush();
      } catch (_) {}
    }
    _close();
    state = CastState.idle;
    device = null;
    item = null;
    notifyListeners();
  }

  void _close() {
    _ping?.cancel();
    _ping = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _transport = null;
    _mediaSession = null;
    _buffer.clear();
  }

  void _fail(String why) {
    _close();
    error = why;
    state = CastState.error;
    notifyListeners();
  }

  void _send(String dest, String ns, Map<String, Object?> payload) {
    final s = _socket;
    if (s == null) return;
    final msg = encodeCastMessage(
        'sender-0', dest, ns, jsonEncode(payload));
    final len = ByteData(4)..setUint32(0, msg.length);
    try {
      s.add(len.buffer.asUint8List());
      s.add(msg);
    } catch (_) {}
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    var bytes = _buffer.takeBytes();
    while (bytes.length >= 4) {
      final len = ByteData.sublistView(bytes, 0, 4).getUint32(0);
      if (bytes.length < 4 + len) break;
      final msg = decodeCastMessage(bytes.sublist(4, 4 + len));
      bytes = bytes.sublist(4 + len);
      if (msg != null) _handle(msg.$1, msg.$2);
    }
    _buffer.add(bytes);
  }

  void _handle(String ns, String payload) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = j['type'];
    if (ns == _ns.beat && type == 'PING') {
      _send('receiver-0', _ns.beat, {'type': 'PONG'});
    } else if (ns == _ns.recv && type == 'RECEIVER_STATUS') {
      final apps = (j['status']?['applications'] as List?) ?? const [];
      final app = apps.whereType<Map>().where((a) => a['appId'] == _appId);
      if (app.isNotEmpty) {
        final t = '${app.first['transportId']}';
        if (_launch != null && !_launch!.isCompleted) {
          _send(t, _ns.conn, {'type': 'CONNECT'});
          _launch!.complete(t);
        }
      } else if (_transport != null && state != CastState.connecting) {
        // L'appli a ete fermee depuis la tele.
        _close();
        state = CastState.idle;
        device = null;
        notifyListeners();
      }
    } else if (ns == _ns.media && type == 'MEDIA_STATUS') {
      final list = (j['status'] as List?) ?? const [];
      if (list.isEmpty) return;
      final st = list.first as Map;
      _mediaSession = st['mediaSessionId'] as int? ?? _mediaSession;
      state = switch (st['playerState']) {
        'PLAYING' => CastState.playing,
        'PAUSED' => CastState.paused,
        'BUFFERING' => CastState.buffering,
        'IDLE' when st['idleReason'] == 'ERROR' => CastState.error,
        _ => state,
      };
      if (state == CastState.error) error = 'media';
      notifyListeners();
    } else if (ns == _ns.media &&
        (type == 'LOAD_FAILED' || type == 'INVALID_REQUEST')) {
      error = 'media';
      state = CastState.error;
      notifyListeners();
    }
  }
}

// ------------------------------------------------- Protobuf CastMessage

void _varint(BytesBuilder b, int v) {
  while (v >= 0x80) {
    b.addByte((v & 0x7f) | 0x80);
    v >>= 7;
  }
  b.addByte(v);
}

void _str(BytesBuilder b, int field, String s) {
  final bytes = utf8.encode(s);
  _varint(b, (field << 3) | 2);
  _varint(b, bytes.length);
  b.add(bytes);
}

/// Encode un message CastMessage (protocole Cast v2, charge utile texte).
Uint8List encodeCastMessage(
    String source, String dest, String namespace, String payload) {
  final b = BytesBuilder();
  _varint(b, 1 << 3); // protocol_version
  _varint(b, 0); //       CASTV2_1_0
  _str(b, 2, source);
  _str(b, 3, dest);
  _str(b, 4, namespace);
  _varint(b, 5 << 3); // payload_type
  _varint(b, 0); //       STRING
  _str(b, 6, payload);
  return b.toBytes();
}

/// Decode un CastMessage : renvoie (namespace, charge utile).
(String, String)? decodeCastMessage(Uint8List data) {
  var i = 0;
  int readVarint() {
    var shift = 0, result = 0;
    while (i < data.length) {
      final byte = data[i++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) break;
      shift += 7;
    }
    return result;
  }

  String? ns, payload;
  try {
    while (i < data.length) {
      final key = readVarint();
      final field = key >> 3, wire = key & 7;
      if (wire == 0) {
        readVarint();
      } else if (wire == 2) {
        final len = readVarint();
        final bytes = data.sublist(i, i + len);
        i += len;
        if (field == 4) ns = utf8.decode(bytes, allowMalformed: true);
        if (field == 6) payload = utf8.decode(bytes, allowMalformed: true);
      } else {
        return null;
      }
    }
  } catch (_) {
    return null;
  }
  return ns == null || payload == null ? null : (ns, payload);
}

/// AirPlay (iPhone, iPad, Mac) : ouvre le lecteur Apple avec le bouton
/// AirPlay. Marche avec Apple TV et les televiseurs compatibles AirPlay 2
/// (Samsung, LG, Sony, Vizio... recents).
class AirPlay {
  AirPlay._();
  static const _ch = MethodChannel('canalix/airplay');
  static bool get supported => Platform.isIOS || Platform.isMacOS;

  /// Appareil fictif qui represente le choix "AirPlay" dans la liste.
  static const device = CastDevice('AirPlay', 'airplay', 0);

  static Future<void> play(Channel c, {String userAgent = ''}) async {
    final (url, _, _) = castMediaFor(c);
    await _ch.invokeMethod('play', {
      'url': url,
      'title': c.name,
      'userAgent': userAgent,
    });
  }
}
