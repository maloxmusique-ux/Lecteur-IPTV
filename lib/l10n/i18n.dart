import 'strings.dart';

/// Langues disponibles pour l'interface (code -> nom affiche).
const kLanguages = {
  'fr': 'Français',
  'en': 'English',
  'es': 'Español',
  'pt': 'Português',
};

const _order = ['fr', 'en', 'es', 'pt'];

/// Langue courante de l'interface (mise a jour par les reglages).
String currentLang = 'fr';

/// Traduit une cle. Les parametres {0}, {1}... sont remplaces par [args].
String tr(String key, [List<Object?> args = const []]) {
  final row = kStrings[key];
  if (row == null) return key;
  final i = _order.indexOf(currentLang);
  var s = (i >= 0 && i < row.length && row[i].isNotEmpty) ? row[i] : row[0];
  for (var n = 0; n < args.length; n++) {
    s = s.replaceAll('{$n}', '${args[n]}');
  }
  return s;
}

/// Nom de jour court localise (lundi = 1).
String weekdayShort(int weekday) =>
    tr('day.short').split(',')[(weekday - 1).clamp(0, 6)];

/// Nom de mois court localise (janvier = 1).
String monthShort(int month) =>
    tr('month.short').split(',')[(month - 1).clamp(0, 11)];

String hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// "lun. 3 nov." ou "Aujourd'hui", "Demain", "Hier".
String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return tr('day.today');
  if (diff == 1) return tr('day.tomorrow');
  if (diff == -1) return tr('day.yesterday');
  return '${weekdayShort(d.weekday)} ${d.day} ${monthShort(d.month)}';
}

/// "Aujourd'hui 20:30" etc.
String dayTime(int ms) =>
    '${dayLabel(DateTime.fromMillisecondsSinceEpoch(ms))} ${hm(ms)}';

String formatBytes(int b) {
  if (b < 1024) return '$b o';
  const u = ['Ko', 'Mo', 'Go', 'To'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${u[i]}';
}

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
