import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// Coffre-fort pour les identifiants (sources Xtream et M3U).
///
/// Les donnees sont chiffrees en AES-256-GCM. La cle est rangee dans le
/// trousseau du systeme : Keystore (Android), Trousseau (iPhone, Mac),
/// protection des donnees Windows (DPAPI), libsecret (Linux).
/// Si le trousseau n'est pas disponible, la cle reste dans le dossier
/// prive de l'app (moins solide, mais jamais en clair a cote des donnees).
class Vault {
  Vault._();

  static const _prefix = 'v1:';
  static const _keyName = 'canalix_vault_key';
  static Uint8List? _key;

  /// Vrai si la cle est protegee par le systeme.
  static bool hardwareBacked = false;

  static Future<void> init() async {
    if (_key != null) return;
    const storage = FlutterSecureStorage();
    try {
      var k = await storage.read(key: _keyName);
      if (k == null) {
        k = base64Encode(_random(32));
        await storage.write(key: _keyName, value: k);
      }
      _key = base64Decode(k);
      hardwareBacked = true;
      return;
    } catch (e) {
      debugPrint('Trousseau indisponible ($e), cle locale.');
    }
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}vault.key');
    if (await f.exists()) {
      _key = base64Decode((await f.readAsString()).trim());
    } else {
      _key = _random(32);
      await f.create(recursive: true);
      await f.writeAsString(base64Encode(_key!), flush: true);
    }
  }

  /// Pour les tests : cle fixe en memoire.
  @visibleForTesting
  static void useKey(Uint8List key) => _key = key;

  static bool isEncrypted(String s) => s.startsWith(_prefix);

  static String encrypt(String plain) {
    final key = _key;
    if (key == null) return plain; // pas encore initialise : jamais de perte
    final nonce = _random(12);
    final c = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final out = c.process(Uint8List.fromList(utf8.encode(plain)));
    return _prefix + base64Encode(Uint8List.fromList([...nonce, ...out]));
  }

  /// Dechiffre. Un texte non chiffre (ancienne version) est renvoye tel quel.
  /// Leve une exception si la cle ne correspond pas.
  static String decrypt(String data) {
    if (!isEncrypted(data)) return data;
    final key = _key;
    if (key == null) throw StateError('vault not ready');
    final raw = base64Decode(data.substring(_prefix.length));
    final c = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(key), 128, raw.sublist(0, 12), Uint8List(0)));
    return utf8.decode(c.process(raw.sublist(12)));
  }

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}
