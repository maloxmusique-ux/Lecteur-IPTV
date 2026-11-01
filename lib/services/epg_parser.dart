import 'package:xml/xml_events.dart';

import '../models/models.dart';

/// Parse un guide XMLTV en flux (sans construire d'arbre DOM), ce qui
/// permet de traiter des fichiers de plusieurs centaines de Mo.
///
/// Seuls les programmes dans la fenetre [now - pastHours, now + futureHours]
/// sont conserves pour limiter la memoire.
EpgData parseXmltv(
  String xml, {
  int pastHours = 3,
  int futureHours = 36,
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final minMs = now - pastHours * 3600000;
  final maxMs = now + futureHours * 3600000;

  final programmes = <String, List<Programme>>{};
  final nameIndex = <String, String>{};

  // Etat courant.
  String? channelId; // dans <channel>
  String? progChannel; // dans <programme>
  int progStart = 0, progStop = 0;
  var keepProg = false;
  String? textTarget; // 'title' | 'desc' | 'display-name'
  final text = StringBuffer();
  var title = '', desc = '';

  for (final event in parseEvents(xml)) {
    if (event is XmlStartElementEvent) {
      switch (event.name) {
        case 'channel':
          channelId = _attr(event, 'id');
        case 'display-name':
          if (channelId != null) {
            textTarget = 'display-name';
            text.clear();
          }
        case 'programme':
          progChannel = _attr(event, 'channel');
          progStart = parseXmltvTime(_attr(event, 'start') ?? '');
          progStop = parseXmltvTime(_attr(event, 'stop') ?? '');
          keepProg = progChannel != null &&
              progStop > minMs &&
              progStart < maxMs;
          title = '';
          desc = '';
        case 'title':
          if (keepProg && title.isEmpty) {
            textTarget = 'title';
            text.clear();
          }
        case 'desc':
          if (keepProg && desc.isEmpty) {
            textTarget = 'desc';
            text.clear();
          }
      }
      if (event.isSelfClosing) {
        if (event.name == 'channel') channelId = null;
        if (event.name == 'programme') progChannel = null;
        if (event.name == textTarget) textTarget = null;
      }
    } else if (event is XmlTextEvent || event is XmlCDATAEvent) {
      if (textTarget != null) {
        text.write(
            event is XmlTextEvent ? event.value : (event as XmlCDATAEvent).value);
      }
    } else if (event is XmlEndElementEvent) {
      switch (event.name) {
        case 'display-name':
          if (textTarget == 'display-name' && channelId != null) {
            final n = EpgData.normalizeName(text.toString());
            if (n.isNotEmpty) nameIndex.putIfAbsent(n, () => channelId!);
          }
          textTarget = null;
        case 'title':
          if (textTarget == 'title') title = text.toString().trim();
          textTarget = null;
        case 'desc':
          if (textTarget == 'desc') desc = text.toString().trim();
          textTarget = null;
        case 'channel':
          channelId = null;
        case 'programme':
          if (keepProg && progChannel != null) {
            (programmes[progChannel] ??= [])
                .add(Programme(progStart, progStop, title, desc));
          }
          progChannel = null;
          keepProg = false;
      }
    }
  }

  for (final list in programmes.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  return EpgData(programmes, nameIndex);
}

String? _attr(XmlStartElementEvent e, String name) {
  for (final a in e.attributes) {
    if (a.name == name) return a.value;
  }
  return null;
}

/// Convertit "20261101203000 +0100" en epoch ms (UTC).
int parseXmltvTime(String s) {
  s = s.trim();
  if (s.length < 12) return 0;
  int n(int a, int b) => int.tryParse(s.substring(a, b)) ?? 0;
  final y = n(0, 4), mo = n(4, 6), d = n(6, 8), h = n(8, 10), mi = n(10, 12);
  final sec = s.length >= 14 ? n(12, 14) : 0;
  var ms = DateTime.utc(y, mo, d, h, mi, sec).millisecondsSinceEpoch;
  final sp = s.indexOf(' ');
  if (sp != -1) {
    final tz = s.substring(sp + 1).trim();
    if (tz.length >= 5 && (tz[0] == '+' || tz[0] == '-')) {
      final sign = tz[0] == '-' ? -1 : 1;
      final oh = int.tryParse(tz.substring(1, 3)) ?? 0;
      final om = int.tryParse(tz.substring(3, 5)) ?? 0;
      ms -= sign * (oh * 3600000 + om * 60000);
    }
  }
  return ms;
}
