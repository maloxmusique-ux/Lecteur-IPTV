import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamflow/l10n/i18n.dart';
import 'package:streamflow/l10n/strings.dart';
import 'package:streamflow/models/models.dart';
import 'package:streamflow/models/profile.dart';
import 'package:streamflow/services/cast.dart';
import 'package:streamflow/services/epg_parser.dart';
import 'package:streamflow/services/xtream_api.dart';
import 'package:streamflow/state/app_state.dart';

void main() {
  group('Traductions', () {
    test('chaque cle utilisee existe dans les 4 langues', () {
      final used = <String>{
        'info.res', 'info.vcodec', 'info.fps', 'info.vbr', 'info.acodec',
        'info.abr', 'info.hwdec', 'info.drops', 'info.cache', 'info.speed',
      };
      final re = RegExp(r"tr\('([a-zA-Z0-9_.]+)'");
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in re.allMatches(f.readAsStringSync())) {
          used.add(m.group(1)!);
        }
      }
      final missing = used.where((k) => !kStrings.containsKey(k)).toList();
      expect(missing, isEmpty, reason: 'Cles manquantes : $missing');
      for (final e in kStrings.entries) {
        expect(e.value.length, 4, reason: e.key);
        for (final s in e.value) {
          expect(s.isNotEmpty, isTrue, reason: e.key);
        }
        // Memes parametres dans toutes les langues.
        final params = RegExp(r'\{\d\}').allMatches(e.value[0]).length;
        for (final s in e.value) {
          expect(RegExp(r'\{\d\}').allMatches(s).length, params,
              reason: e.key);
        }
      }
      expect(kStrings['day.short']!.every((s) => s.split(',').length == 7),
          isTrue);
      expect(kStrings['month.short']!.every((s) => s.split(',').length == 12),
          isTrue);
    });

    test('changement de langue et parametres', () {
      currentLang = 'en';
      expect(tr('tab.movies'), 'Movies');
      expect(tr('common.minutes', [30]), '30 min');
      currentLang = 'es';
      expect(tr('tab.movies'), 'Películas');
      currentLang = 'fr';
      expect(tr('series.season', [2]), 'Saison 2');
      expect(tr('cle.inconnue'), 'cle.inconnue');
    });
  });

  group('Rattrapage Xtream', () {
    const source = Source(
      id: 's',
      name: 'Test',
      kind: SourceKind.xtream,
      url: 'http://srv.test:8080/',
      username: 'u',
      password: 'p w',
    );
    final channel = Channel(
        id: 'live_42', name: 'Ch', url: '', archiveDays: 3);

    test('identifiant de flux', () {
      expect(channel.streamId, '42');
      expect(Channel(id: 'http://x', name: '', url: '').streamId, '');
      expect(channel.hasArchive, isTrue);
    });

    test('URL de rattrapage', () {
      final url = XtreamApi(source).catchupUrl(
          channel, '2026-11-01 20:00:00', const Duration(minutes: 90));
      expect(url,
          'http://srv.test:8080/timeshift/u/p%20w/90/2026-11-01:20-00/42.ts');
    });

    test('heure du serveur avec decalage', () {
      final utc = DateTime.utc(2026, 11, 2, 1, 30).millisecondsSinceEpoch;
      // Serveur a UTC-5.
      expect(XtreamApi.serverTime(utc, -5 * 3600000), '2026-11-01 20:30:00');
    });
  });

  group('Guide TV', () {
    test('garde le passe des chaines avec rattrapage', () {
      const xml = '''<tv>
  <programme start="20261029100000 +0000" stop="20261029110000 +0000" channel="a"><title>Vieux A</title></programme>
  <programme start="20261029100000 +0000" stop="20261029110000 +0000" channel="b"><title>Vieux B</title></programme>
  <programme start="20261101100000 +0000" stop="20261101110000 +0000" channel="a"><title>Actuel</title></programme>
  <programme start="20261101100000 +0000" stop="20261101110000 +0000" channel="a"><title>Doublon</title></programme>
  <programme start="20261106100000 +0000" stop="20261106110000 +0000" channel="a"><title>Dans 5 jours</title></programme>
</tv>''';
      final now = DateTime.utc(2026, 11, 1, 10, 30).millisecondsSinceEpoch;
      final epg = parseXmltv(xml, nowMs: now, archiveHours: {'a': 7 * 24});
      final a = epg.programmes['a']!.map((p) => p.title).toList();
      expect(a, ['Vieux A', 'Actuel', 'Dans 5 jours']);
      expect(epg.programmes['b'], isNull);
    });
  });

  group('Reprise et parental', () {
    test('position reprenable', () {
      final c = Channel(id: 'vod_1', name: 'Film', url: 'u', type: ContentType.movie);
      expect(WatchProgress(c, 10000, 6000000, 0).resumable, isFalse);
      expect(WatchProgress(c, 600000, 6000000, 0).resumable, isTrue);
      expect(WatchProgress(c, 5900000, 6000000, 0).resumable, isFalse);
      final back = WatchProgress.fromJson(
          WatchProgress(c, 600000, 6000000, 5).toJson());
      expect(back.item.name, 'Film');
      expect(back.posMs, 600000);
    });

    test('detection des categories adultes', () {
      for (final g in ['XXX Adult', 'Pour adultes', '18+ Films', 'FR| ADULTS']) {
        expect(kAdultPattern.hasMatch(g), isTrue, reason: g);
      }
      for (final g in ['Sports', 'Enfants', 'Films 2018', 'News 24']) {
        expect(kAdultPattern.hasMatch(g), isFalse, reason: g);
      }
    });
  });

  group('Chromecast et fiches', () {
    test('message Cast v2 aller-retour', () {
      const payload = '{"type":"PING","texte":"éàü"}';
      final bytes = encodeCastMessage(
          'sender-0', 'receiver-0', 'urn:x-cast:com.google.cast.tp.heartbeat', payload);
      final back = decodeCastMessage(bytes)!;
      expect(back.$1, 'urn:x-cast:com.google.cast.tp.heartbeat');
      expect(back.$2, payload);
    });

    test('flux Xtream converti en HLS pour Chromecast', () {
      final live = Channel(id: 'live_1', name: 'A', url: 'http://s/live/u/p/1.ts');
      final (url, type, isLive) = castMediaFor(live);
      expect(url, 'http://s/live/u/p/1.m3u8');
      expect(type, 'application/x-mpegURL');
      expect(isLive, isTrue);
      final movie = Channel(
          id: 'vod_2', name: 'B', url: 'http://s/movie/u/p/2.mp4',
          type: ContentType.movie);
      expect(castMediaFor(movie).$2, 'video/mp4');
    });

    test('fiche Xtream', () {
      final m = MediaInfo.fromXtream({
        'movie_image': 'http://img/p.jpg',
        'backdrop_path': ['http://img/b.jpg'],
        'plot': 'Un film.',
        'releasedate': '2024-05-01',
        'rating': '7.4',
        'duration_secs': 5400,
        'youtube_trailer': 'abc123',
        'genre': 'Action',
      });
      expect(m.year, '2024');
      expect(m.rating, 7.4);
      expect(m.duration, const Duration(minutes: 90));
      expect(m.trailer, 'https://www.youtube.com/watch?v=abc123');
      expect(m.backdrop, 'http://img/b.jpg');
    });
  });

  test('guide filtre sur les chaines de la liste', () {
    const xml = '''<tv>
  <channel id="a.fr"><display-name>Chaine A</display-name></channel>
  <channel id="b.fr"><display-name>Chaine B</display-name></channel>
  <channel id="z.fr"><display-name>Autre</display-name></channel>
  <programme start="20261101100000 +0000" stop="20261101110000 +0000" channel="a.fr"><title>A</title></programme>
  <programme start="20261101100000 +0000" stop="20261101110000 +0000" channel="b.fr"><title>B</title></programme>
  <programme start="20261101100000 +0000" stop="20261101110000 +0000" channel="z.fr"><title>Z</title></programme>
</tv>''';
    final now = DateTime.utc(2026, 11, 1, 10, 30).millisecondsSinceEpoch;
    final epg = parseXmltv(xml,
        nowMs: now, wantedIds: {'a.fr'}, wantedNames: {'chaineb'});
    expect(epg.programmes.keys.toSet(), {'a.fr', 'b.fr'});
  });
}
