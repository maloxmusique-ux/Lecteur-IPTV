import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vault.dart';

/// Type de serveur fourni par le VPN de l'utilisateur.
enum ProxyKind { socks5, http }

/// Reglages de la connexion protegee (VPN de l'utilisateur).
class ProxyConfig {
  final bool enabled;
  final ProxyKind kind;
  final String host;
  final int port;
  final String user;
  final String password;

  const ProxyConfig({
    this.enabled = false,
    this.kind = ProxyKind.socks5,
    this.host = '',
    this.port = 1080,
    this.user = '',
    this.password = '',
  });

  bool get usable => enabled && host.trim().isNotEmpty && port > 0 && port < 65536;

  Map<String, dynamic> toJson() => {
        'on': enabled,
        'kind': kind.name,
        'host': host,
        'port': port,
        'user': user,
        'pass': password,
      };

  factory ProxyConfig.fromJson(Map<String, dynamic> j) => ProxyConfig(
        enabled: j['on'] == true,
        kind: j['kind'] == 'http' ? ProxyKind.http : ProxyKind.socks5,
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as int?) ?? 1080,
        user: (j['user'] as String?) ?? '',
        password: (j['pass'] as String?) ?? '',
      );
}

/// Fait passer tout le trafic de l'app (catalogue, guide, lecture,
/// enregistrements) par le VPN de l'utilisateur.
///
/// Un petit relais local (127.0.0.1) recoit les requetes de l'app et du
/// lecteur, puis les envoie au serveur SOCKS5 ou HTTP du VPN. Si le VPN
/// ne repond pas, les requetes echouent : rien ne passe sans protection.
class ProxyBridge {
  ProxyBridge._();

  static const _prefKey = 'proxy_v1';
  static ProxyConfig config = const ProxyConfig();
  static ServerSocket? _server;

  /// Adresse a donner au lecteur (vide = connexion directe).
  static String get mpvProxy =>
      _server == null ? '' : 'http://127.0.0.1:${_server!.port}';

  static bool get active => _server != null;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      try {
        config = ProxyConfig.fromJson(
            jsonDecode(Vault.decrypt(raw)) as Map<String, dynamic>);
      } catch (_) {}
    }
    await _apply();
  }

  /// Enregistre (mot de passe chiffre) et applique.
  static Future<void> save(ProxyConfig c) async {
    config = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, Vault.encrypt(jsonEncode(c.toJson())));
    await _apply();
  }

  static Future<void> _apply() async {
    await _server?.close();
    _server = null;
    if (!config.usable) {
      HttpOverrides.global = null;
      return;
    }
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((c) => _handle(c, config), onError: (_) {});
    HttpOverrides.global = _Overrides(server.port);
  }

  // ------------------------------------------------------------- Relais

  static Future<void> _handle(Socket client, ProxyConfig cfg) async {
    Socket? upstream;
    try {
      final reader = _Reader(client);
      final head = await reader.readHead();
      final lines = head.split('\r\n');
      final parts = lines.first.split(' ');
      if (parts.length < 3) throw const FormatException('bad request');
      final method = parts[0].toUpperCase();

      if (method == 'CONNECT') {
        // HTTPS : tunnel brut vers l'hote demande.
        final (h, p) = _hostPort(parts[1], 443);
        upstream = await _connectUpstream(h, p, cfg);
        client.add(latin1.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
        if (reader.rest.isNotEmpty) upstream.add(reader.rest);
      } else {
        // HTTP : requete "http://hote/chemin" reecrite en "/chemin".
        final uri = Uri.parse(parts[1]);
        upstream = await _connectUpstream(uri.host, uri.hasPort ? uri.port : 80, cfg);
        final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
        final out = StringBuffer('$method ${path.isEmpty ? '/' : path} ${parts[2]}\r\n');
        for (final l in lines.skip(1)) {
          final k = l.split(':').first.toLowerCase();
          if (l.isEmpty || k == 'proxy-connection' || k == 'connection' ||
              k == 'proxy-authorization') {
            continue;
          }
          out.write('$l\r\n');
        }
        // Une requete par connexion : l'hote peut changer a la suivante.
        out.write('Connection: close\r\n\r\n');
        upstream.add(latin1.encode(out.toString()));
        if (reader.rest.isNotEmpty) upstream.add(reader.rest);
      }
      final up = upstream;
      reader.pipeTo(up);
      up.listen(client.add,
          onDone: () => client.destroy(), onError: (_) => client.destroy());
    } catch (e) {
      debugPrint('VPN relais : $e');
      try {
        client.add(latin1.encode(
            'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'));
        await client.flush();
      } catch (_) {}
      client.destroy();
      upstream?.destroy();
    }
  }

  static (String, int) _hostPort(String s, int def) {
    if (s.startsWith('[')) {
      final end = s.indexOf(']');
      final port = int.tryParse(s.substring(end + 2)) ?? def;
      return (s.substring(1, end), port);
    }
    final i = s.lastIndexOf(':');
    return i < 0 ? (s, def) : (s.substring(0, i), int.tryParse(s.substring(i + 1)) ?? def);
  }

  /// Ouvre une connexion vers [host]:[port] a travers le VPN.
  static Future<Socket> _connectUpstream(String host, int port,
      [ProxyConfig? cfg]) async {
    final c = cfg ?? config;
    final s = await Socket.connect(c.host.trim(), c.port,
        timeout: const Duration(seconds: 10));
    final r = _Reader(s);
    try {
      if (c.kind == ProxyKind.socks5) {
        final auth = c.user.isNotEmpty;
        s.add([5, 1, auth ? 2 : 0]);
        final hello = await r.read(2);
        if (hello[0] != 5 || hello[1] == 0xFF) throw const SocketException('VPN : méthode refusée');
        if (hello[1] == 2) {
          final u = utf8.encode(c.user), p = utf8.encode(c.password);
          s.add([1, u.length, ...u, p.length, ...p]);
          final res = await r.read(2);
          if (res[1] != 0) throw const SocketException('VPN : identifiants refusés');
        }
        // Le nom est resolu par le VPN (pas de fuite DNS).
        final h = utf8.encode(host);
        s.add([5, 1, 0, 3, h.length, ...h, port >> 8, port & 0xFF]);
        final rep = await r.read(4);
        if (rep[1] != 0) throw SocketException('VPN : connexion refusée (${rep[1]})');
        final skip = switch (rep[3]) {
          1 => 4,
          4 => 16,
          _ => (await r.read(1))[0],
        };
        await r.read(skip + 2);
      } else {
        final auth = c.user.isEmpty
            ? ''
            : 'Proxy-Authorization: Basic ${base64Encode(utf8.encode('${c.user}:${c.password}'))}\r\n';
        s.add(latin1.encode(
            'CONNECT $host:$port HTTP/1.1\r\nHost: $host:$port\r\n$auth\r\n'));
        final head = await r.readHead();
        final code = int.tryParse(head.split(' ').elementAtOrNull(1) ?? '') ?? 0;
        if (code == 407) throw const SocketException('VPN : identifiants refusés');
        if (code != 200) throw SocketException('VPN : réponse $code');
      }
    } catch (_) {
      s.destroy();
      rethrow;
    }
    return r.detach();
  }

  // ------------------------------------------------------------- Test

  /// Adresse IP publique vue par Internet, avec et sans le VPN.
  /// Leve une exception claire si le VPN ne repond pas.
  static Future<(String?, String)> testIp(ProxyConfig c) async {
    Future<String> ip(int? relayPort) async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..findProxy = (_) => relayPort == null ? 'DIRECT' : 'PROXY 127.0.0.1:$relayPort';
      try {
        final req = await client.getUrl(Uri.parse('https://api.ipify.org'));
        final res = await req.close().timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) {
          throw SocketException('VPN : réponse ${res.statusCode}');
        }
        return (await res.transform(utf8.decoder).join()).trim();
      } finally {
        client.close(force: true);
      }
    }

    String? direct;
    try {
      direct = await ip(null);
    } catch (_) {}
    // Relais temporaire avec les reglages a tester.
    final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    tmp.listen((s) => _handle(s, c));
    try {
      return (direct, await ip(tmp.port));
    } finally {
      await tmp.close();
    }
  }
}

class _Overrides extends HttpOverrides {
  final int port;
  _Overrides(this.port);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final c = super.createHttpClient(context);
    c.findProxy = (uri) {
      final h = uri.host;
      // Le reseau local reste direct (ex. Chromecast) ; tout le reste
      // passe par le VPN.
      if (h == 'localhost' || h == '127.0.0.1' || _isLan(h)) return 'DIRECT';
      return 'PROXY 127.0.0.1:$port';
    };
    return c;
  }

  static bool _isLan(String h) {
    final a = InternetAddress.tryParse(h);
    if (a == null || a.type != InternetAddressType.IPv4) return false;
    final b = a.rawAddress;
    return b[0] == 10 ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31);
  }
}

/// Lecture par blocs d'une socket, avec ce qui a ete lu en trop.
class _Reader {
  final Socket socket;
  final _buf = BytesBuilder();
  late final StreamSubscription<Uint8List> _sub;
  Completer<void>? _wait;
  bool _done = false;

  _Reader(this.socket) {
    _sub = socket.listen((d) {
      _buf.add(d);
      _wait?.complete();
      _wait = null;
    }, onDone: () {
      _done = true;
      _wait?.complete();
      _wait = null;
    }, onError: (_) {
      _done = true;
      _wait?.complete();
      _wait = null;
    });
  }

  Uint8List get rest => _buf.takeBytes();

  Future<void> _more() async {
    if (_done) throw const SocketException('connexion fermée');
    _wait = Completer<void>();
    await _wait!.future.timeout(const Duration(seconds: 15));
  }

  Future<Uint8List> read(int n) async {
    while (_buf.length < n) {
      await _more();
    }
    final all = _buf.takeBytes();
    _buf.add(all.sublist(n));
    return all.sublist(0, n);
  }

  /// Lit les en-tetes HTTP jusqu'a la ligne vide.
  Future<String> readHead() async {
    while (true) {
      final bytes = _buf.toBytes();
      for (var i = 0; i + 3 < bytes.length; i++) {
        if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
          _buf.clear();
          _buf.add(bytes.sublist(i + 4));
          return latin1.decode(bytes.sublist(0, i));
        }
      }
      if (bytes.length > 64 * 1024) throw const FormatException('en-têtes trop longs');
      await _more();
    }
  }

  /// Envoie tout ce qui arrive ensuite vers [dest].
  void pipeTo(Socket dest) {
    _sub.onData(dest.add);
    _sub.onDone(() => dest.destroy());
    _sub.onError((_) => dest.destroy());
  }

  /// Rend une socket utilisable normalement (apres la negociation).
  Socket detach() {
    final leftover = _buf.takeBytes();
    _sub.pause();
    return _DetachedSocket(socket, _sub, leftover);
  }
}

/// Socket deja negociee : les donnees deja lues sont rendues en premier.
class _DetachedSocket extends StreamView<Uint8List> implements Socket {
  final Socket _inner;
  _DetachedSocket(this._inner, StreamSubscription<Uint8List> sub, Uint8List leftover)
      : super(_resume(sub, leftover));

  static Stream<Uint8List> _resume(StreamSubscription<Uint8List> sub, Uint8List leftover) {
    late StreamController<Uint8List> c;
    c = StreamController<Uint8List>(
      onListen: () {
        if (leftover.isNotEmpty) c.add(leftover);
        sub.onData(c.add);
        sub.onDone(c.close);
        sub.onError(c.addError);
        sub.resume();
      },
      onPause: sub.pause,
      onResume: sub.resume,
      onCancel: sub.cancel,
    );
    return c.stream;
  }

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding e) => _inner.encoding = e;
  @override
  void add(List<int> data) => _inner.add(data);
  @override
  void addError(Object error, [StackTrace? st]) => _inner.addError(error, st);
  @override
  Future addStream(Stream<List<int>> stream) => _inner.addStream(stream);
  @override
  Future close() => _inner.close();
  @override
  Future get done => _inner.done;
  @override
  Future flush() => _inner.flush();
  @override
  void write(Object? object) => _inner.write(object);
  @override
  void writeAll(Iterable objects, [String sep = '']) => _inner.writeAll(objects, sep);
  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _inner.writeln(object);
  @override
  InternetAddress get address => _inner.address;
  @override
  void destroy() => _inner.destroy();
  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);
  @override
  int get port => _inner.port;
  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;
  @override
  int get remotePort => _inner.remotePort;
  @override
  bool setOption(SocketOption option, bool enabled) => _inner.setOption(option, enabled);
  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
}
