import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const defaultUserAgent = 'StreamFlow/1.0 (Linux; libmpv)';

/// Telecharge une ressource et la renvoie en texte UTF-8.
/// Gere automatiquement les fichiers gzip (.gz), frequents pour les EPG.
Future<String> fetchText(String url, {String userAgent = ''}) async {
  final client = http.Client();
  try {
    final res = await client
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': userAgent.isEmpty ? defaultUserAgent : userAgent,
            'Accept-Encoding': 'gzip',
          },
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    return decodeBytes(res.bodyBytes);
  } finally {
    client.close();
  }
}

String decodeBytes(Uint8List bytes) {
  var data = bytes;
  if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b) {
    data = Uint8List.fromList(gzip.decode(data));
  }
  return utf8.decode(data, allowMalformed: true);
}
