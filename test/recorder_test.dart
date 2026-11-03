import 'dart:io' hide ContentType;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamflow/models/models.dart';
import 'package:streamflow/services/recorder.dart';
import 'package:streamflow/state/settings.dart';

Future<RecordingService> _service(Directory dir) async {
  final settings = Settings();
  await settings.init();
  settings.update((s) => s.recFolder = dir.path);
  final rec = RecordingService(settings);
  await rec.init();
  return rec;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('HLS redirige : les segments sont lus depuis la bonne adresse', () async {
    final tmp = await Directory.systemTemp.createTemp('cx_hls');
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var seq = 0;
    srv.listen((req) async {
      final p = req.uri.path;
      if (p == '/live/u/p/1.m3u8') {
        req.response.statusCode = 302;
        req.response.headers.set('location', '/hls/tok123/index.m3u8');
      } else if (p == '/hls/tok123/index.m3u8') {
        seq++;
        req.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$seq\n'
            '#EXTINF:2,\nseg$seq.ts\n#EXTINF:2,\nseg${seq + 1}.ts\n');
      } else if (p.startsWith('/hls/tok123/seg')) {
        req.response.add(List.filled(188 * 10, 0x47));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final rec = await _service(tmp);
    const src = Source(id: 's', name: 'S', kind: SourceKind.xtream, url: 'x');
    final ch = Channel(
        id: 'c', name: 'Chaine', url: 'http://127.0.0.1:${srv.port}/live/u/p/1.m3u8',
        logo: '', group: '', type: ContentType.live);
    final r = rec.recordNow(src, ch, const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(seconds: 7));
    expect(r.status, RecStatus.done, reason: r.error);
    expect(r.bytes, greaterThan(188 * 10));
    rec.dispose();
    await srv.close(force: true);
  });

  test('Episodes a la suite : un seul enregistrement', () async {
    final tmp = await Directory.systemTemp.createTemp('cx_merge');
    final rec = await _service(tmp);
    const src = Source(id: 's', name: 'S', kind: SourceKind.xtream, url: 'x');
    final ch = Channel(
        id: 'c', name: 'Teletoon', url: 'http://127.0.0.1:1/x.ts', logo: '',
        group: '', type: ContentType.live, epgId: 'tt');
    final base = DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch;
    const ep = 11 * 60000;
    final progs = [
      for (var i = 0; i < 6; i++)
        Programme(base + i * ep, base + (i + 1) * ep, 'Angelo la débrouille', ''),
      Programme(base + 6 * ep, base + 7 * ep, 'Autre emission', ''),
      Programme(base + 5 * 3600000, base + 5 * 3600000 + ep, 'Angelo la débrouille', ''),
    ];
    rec.updateGuide('s', EpgData({'tt': progs}, const {}));
    rec.addRule(src, ch, progs.first, RecRepeat.everyAiring);
    final planned = rec.items.where((r) => r.status == RecStatus.scheduled).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    expect(planned.length, 2, reason: 'un bloc pour les 6 episodes, un pour le soir');
    expect(planned.first.stop, greaterThanOrEqualTo(base + 6 * ep));
    expect(recFailReason('HTTP 403'), contains('403'));
    rec.dispose();
  });
}
