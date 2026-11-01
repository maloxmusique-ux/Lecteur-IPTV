import '../models/models.dart';

final _attr = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

/// Parse une playlist M3U/M3U8 etendue.
///
/// Optimise pour les grosses playlists (100k+ entrees) : une seule passe,
/// aucune allocation inutile, a executer dans un isolate.
Catalog parseM3u(String content) {
  final channels = <Channel>[];
  var epgUrl = '';

  String? name;
  var attrs = <String, String>{};
  var headers = <String, String>{};
  String? extGroup;
  // Identifiant stable : l'URL, suffixee si elle apparait plusieurs fois.
  final seenUrls = <String, int>{};

  var start = 0;
  final len = content.length;
  while (start < len) {
    var end = content.indexOf('\n', start);
    if (end == -1) end = len;
    var line = content.substring(start, end).trim();
    start = end + 1;
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTM3U')) {
      for (final m in _attr.allMatches(line)) {
        final k = m.group(1)!.toLowerCase();
        if ((k == 'url-tvg' || k == 'x-tvg-url') && epgUrl.isEmpty) {
          epgUrl = m.group(2)!.split(',').first.trim();
        }
      }
    } else if (line.startsWith('#EXTINF')) {
      attrs = {};
      for (final m in _attr.allMatches(line)) {
        attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
      }
      // Le nom est apres la derniere virgule situee hors des guillemets.
      name = _extractTitle(line);
    } else if (line.startsWith('#EXTGRP:')) {
      extGroup = line.substring(8).trim();
    } else if (line.startsWith('#EXTVLCOPT:')) {
      final opt = line.substring(11);
      final eq = opt.indexOf('=');
      if (eq > 0) {
        final k = opt.substring(0, eq).trim().toLowerCase();
        final v = opt.substring(eq + 1).trim();
        if (k == 'http-user-agent') headers['User-Agent'] = v;
        if (k == 'http-referrer' || k == 'http-referer') {
          headers['Referer'] = v;
        }
      }
    } else if (line.startsWith('#')) {
      continue;
    } else {
      // Ligne URL.
      final url = line;
      final title = (name == null || name.isEmpty)
          ? (attrs['tvg-name'] ?? url)
          : name;
      final group = attrs['group-title'] ?? extGroup ?? '';
      final dup = seenUrls.update(url, (n) => n + 1, ifAbsent: () => 0);
      channels.add(Channel(
        id: dup == 0 ? url : '$url#$dup',
        name: title,
        url: url,
        logo: attrs['tvg-logo'] ?? '',
        group: group,
        epgId: attrs['tvg-id'] ?? '',
        type: _guessType(url, group),
        headers: headers.isEmpty ? const {} : headers,
      ));
      name = null;
      attrs = {};
      headers = {};
      extGroup = null;
    }
  }
  return Catalog.fromChannels(channels, epgUrl: epgUrl);
}

String _extractTitle(String line) {
  var inQuote = false;
  var lastComma = -1;
  for (var i = 0; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == 0x22) {
      inQuote = !inQuote;
    } else if (c == 0x2C && !inQuote) {
      lastComma = i;
    }
  }
  return lastComma == -1 ? '' : line.substring(lastComma + 1).trim();
}

/// Les M3U exportes par les serveurs Xtream contiennent /movie/ et /series/.
ContentType _guessType(String url, String group) {
  if (url.contains('/movie/')) return ContentType.movie;
  if (url.contains('/series/')) return ContentType.series;
  final lower = url.toLowerCase();
  if (lower.endsWith('.mp4') || lower.endsWith('.mkv') ||
      lower.endsWith('.avi')) {
    return ContentType.movie;
  }
  return ContentType.live;
}
