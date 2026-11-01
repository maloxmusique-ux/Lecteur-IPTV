import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/models/models.dart';
import 'package:streamflow/services/epg_parser.dart';
import 'package:streamflow/services/m3u_parser.dart';

void main() {
  group('M3U', () {
    test('parse attributs, groupes, en-tetes et types', () {
      const m3u = '''
#EXTM3U url-tvg="http://epg.example/guide.xml.gz"
#EXTINF:-1 tvg-id="tf1.fr" tvg-logo="http://l/tf1.png" group-title="France",TF1 HD
#EXTVLCOPT:http-user-agent=MyUA
http://srv/live/u/p/1.ts
#EXTINF:-1 tvg-name="Film, le" group-title="VOD, Action",Film, avec virgule
http://srv/movie/u/p/2.mkv
#EXTINF:0,Sans groupe
#EXTGRP:Divers
http://srv/3.m3u8
''';
      final c = parseM3u(m3u);
      expect(c.epgUrl, 'http://epg.example/guide.xml.gz');
      expect(c.live.length, 2);
      expect(c.movies.length, 1);

      final tf1 = c.live.first;
      expect(tf1.name, 'TF1 HD');
      expect(tf1.epgId, 'tf1.fr');
      expect(tf1.group, 'France');
      expect(tf1.headers['User-Agent'], 'MyUA');

      expect(c.movies.first.name, 'avec virgule');
      expect(c.movies.first.group, 'VOD, Action');
      expect(c.live[1].group, 'Divers');
      expect(c.groups[ContentType.live], ['France', 'Divers']);
    });

    test('100 000 entrees en moins d\'une seconde', () {
      final b = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 100000; i++) {
        b.writeln('#EXTINF:-1 tvg-id="c$i" tvg-logo="http://l/$i.png" '
            'group-title="G${i % 50}",Chaine $i');
        b.writeln('http://srv/live/u/p/$i.ts');
      }
      final sw = Stopwatch()..start();
      final c = parseM3u(b.toString());
      sw.stop();
      expect(c.live.length, 100000);
      expect(c.groups[ContentType.live]!.length, 50);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('cache JSON aller-retour', () {
      final c = parseM3u('#EXTM3U\n#EXTINF:-1 group-title="A",X\nhttp://x/1.ts\n');
      final back = Catalog.fromJson(c.toJson());
      expect(back.live.single.name, 'X');
      expect(back.live.single.group, 'A');
    });
  });

  group('XMLTV', () {
    test('heure avec fuseau', () {
      expect(parseXmltvTime('20261101120000 +0100'),
          DateTime.utc(2026, 11, 1, 11).millisecondsSinceEpoch);
      expect(parseXmltvTime('20261101120000'),
          DateTime.utc(2026, 11, 1, 12).millisecondsSinceEpoch);
    });

    test('parse programmes, filtre fenetre, now/next', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="tf1.fr"><display-name>TF1 HD</display-name></channel>
  <programme start="20261101100000 +0000" stop="20261101110000 +0000" channel="tf1.fr">
    <title lang="fr">Matin</title>
  </programme>
  <programme start="20261101110000 +0000" stop="20261101120000 +0000" channel="tf1.fr">
    <title lang="fr">Journal &amp; Meteo</title><desc>Infos</desc>
  </programme>
  <programme start="20261101120000 +0000" stop="20261101130000 +0000" channel="tf1.fr">
    <title>Film</title>
  </programme>
  <programme start="20261001120000 +0000" stop="20261001130000 +0000" channel="tf1.fr">
    <title>Trop vieux</title>
  </programme>
</tv>''';
      final now = DateTime.utc(2026, 11, 1, 11, 30).millisecondsSinceEpoch;
      final epg = parseXmltv(xml, nowMs: now);
      expect(epg.programmes['tf1.fr']!.length, 3);

      // Correspondance par tvg-id.
      final byId = Channel(id: '1', name: 'x', url: '', epgId: 'tf1.fr');
      final (cur, next) = epg.nowNext(byId, now);
      expect(cur!.title, 'Journal & Meteo');
      expect(cur.desc, 'Infos');
      expect(next!.title, 'Film');
      expect(cur.progress(now), closeTo(0.5, 0.001));

      // Correspondance par nom (M3U sans tvg-id).
      final byName = Channel(id: '2', name: 'TF1 HD', url: '');
      expect(epg.nowNext(byName, now).$1!.title, 'Journal & Meteo');

      final back = EpgData.fromJson(epg.toJson());
      expect(back.nowNext(byId, now).$2!.title, 'Film');
    });
  });
}
