import 'dart:convert';
import 'dart:io' hide ContentType;
import 'dart:io' as io show ContentType;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamflow/models/models.dart';
import 'package:streamflow/services/home_recorder.dart';
import 'package:streamflow/services/recorder.dart';
import 'package:streamflow/state/settings.dart';

/// Enregistreur maison : un ecran envoie ses enregistrements a un autre
/// appareil Canalix du reseau local, puis les relit.
void main() {
  test('Enregistreur maison : appairage, enregistrement, lecture', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = await Directory.systemTemp.createTemp('canalix_home');

    // Faux flux de chaine en direct.
    final live = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    live.listen((req) async {
      req.response.headers.contentType = io.ContentType('video', 'mp2t');
      try {
        for (var i = 0; i < 400; i++) {
          req.response.add(List.filled(188 * 20, 0x47));
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await req.response.close();
      } catch (_) {}
    });

    final settings = Settings();
    await settings.init();
    settings.update((s) => s.recFolder = tmp.path);
    final recorder = RecordingService(settings);
    await recorder.init();
    final server = HomeServer(recorder);
    await server.init();
    await server.setEnabled(true);
    expect(server.error, isEmpty);
    expect(server.code.length, 6);

    final client = HomeClient();
    await client.init();
    expect(await client.pair('127.0.0.1', 'Salon', '000000'), isFalse);
    expect(await client.pair('127.0.0.1', 'Salon', server.code), isTrue);
    expect(client.online, isTrue);

    const src = Source(
        id: 's1', name: 'Fournisseur', kind: SourceKind.xtream, url: 'x');
    final ch = Channel(
      id: 'c1',
      name: 'Info 24',
      url: 'http://127.0.0.1:${live.port}/live/1.ts',
      logo: '',
      group: 'Nouvelles',
      type: ContentType.live,
    );

    // Emission plus tard : prevue sur l'enregistreur, puis annulee.
    final now = DateTime.now().millisecondsSinceEpoch;
    final later = Programme(now + 3600000, now + 7200000, 'Le Journal', '');
    expect(await client.schedule(src, ch, later), isTrue);
    expect(client.isScheduled('s1', ch, later), isTrue);
    expect(recorder.items.single.status, RecStatus.scheduled);
    await client.stop(client.covering('s1', ch, later).single);
    expect(recorder.items.single.status, RecStatus.cancelled);

    // Enregistrement immediat.
    expect(await client.recordNow(src, ch, const Duration(minutes: 1),
        title: 'Direct'), isTrue);
    await Future<void>.delayed(const Duration(seconds: 4));
    await client.refresh();
    final rec = client.items.firstWhere((r) => r.title == 'Direct');
    expect(rec.active, isTrue);
    expect(rec.bytes, greaterThan(0));
    expect(client.storage, isNotNull);

    // Lecture depuis l'autre ecran, avec reprise (Range).
    final http = HttpClient();
    final req = await http.getUrl(Uri.parse(client.fileUrl(rec)));
    req.headers.set('range', 'bytes=0-99');
    final res = await req.close();
    final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(res.statusCode, 206);
    expect(body.length, 100);
    expect(body.first, 0x47);

    // Sans code : refuse.
    final bad = await (await http.getUrl(Uri.parse(
            'http://127.0.0.1:$homePort/files/${rec.id}.ts')))
        .close();
    expect(bad.statusCode, 401);
    await bad.drain<void>();

    // Serie hebdomadaire creee depuis l'ecran.
    expect(
        await client.addRule(src, ch, later, RecRepeat.weekly, EpgData.empty),
        isTrue);
    expect(client.rules.single.mode, RecRepeat.weekly);
    await client.removeRule(client.rules.single);
    await client.refresh();
    expect(client.rules, isEmpty);

    await client.stop(rec);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await client.refresh();
    expect(client.items.firstWhere((r) => r.id == rec.id).finished, isTrue);
    expect(jsonEncode(client.items.first.j).contains('live/1.ts'), isFalse,
        reason: "l'adresse du flux (mots de passe) ne sort jamais");

    http.close(force: true);
    await server.setEnabled(false);
    recorder.dispose();
    await live.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
