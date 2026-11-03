import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../state/settings.dart';
import 'net.dart';
import 'notifier.dart';

enum RecStatus { scheduled, recording, done, failed, cancelled }

/// Raison lisible d'un enregistrement rate.
String recFailReason(String err) {
  final e = err.toLowerCase();
  if (e == 'missed') return tr('rec.err.missed');
  if (e == 'interrupted') return tr('rec.err.interrupted');
  if (e == 'empty') return tr('rec.err.empty');
  final code = int.tryParse(RegExp(r'http (\d{3})').firstMatch(e)?.group(1) ?? '');
  if (code == 404) return tr('rec.err.notFound');
  if (code != null && code >= 400 && code < 600) return tr('rec.err.refused', [code]);
  return tr('rec.err.network');
}

/// live = enregistrement d'une chaine en direct entre deux heures,
/// file = telechargement d'un fichier (rattrapage, film, episode).
enum RecKind { live, file }

class Recording {
  final String id;
  final String sourceId;
  final Channel channel;
  final String title;
  final RecKind kind;

  /// URL a telecharger (flux de la chaine, du rattrapage ou du film).
  final String url;
  final String userAgent;
  int start;
  int stop;
  RecStatus status;
  String path;
  int bytes;
  int totalBytes;
  String error;

  /// Serie d'enregistrement qui a cree cette entree ('' = aucune).
  final String ruleId;

  /// Debut de l'emission (sans les marges), pour eviter les doublons.
  final int progStart;

  Recording({
    required this.id,
    required this.sourceId,
    required this.channel,
    required this.title,
    required this.kind,
    required this.url,
    required this.start,
    required this.stop,
    this.userAgent = '',
    this.status = RecStatus.scheduled,
    this.path = '',
    this.bytes = 0,
    this.totalBytes = 0,
    this.error = '',
    this.ruleId = '',
    this.progStart = 0,
  });

  bool get active => status == RecStatus.recording;
  bool get finished =>
      status == RecStatus.done ||
      status == RecStatus.failed ||
      status == RecStatus.cancelled;

  double? get progress {
    if (kind == RecKind.file) {
      return totalBytes > 0 ? (bytes / totalBytes).clamp(0.0, 1.0) : null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (stop <= start) return null;
    return ((now - start) / (stop - start)).clamp(0.0, 1.0);
  }

  /// Entree jouable pour relire l'enregistrement.
  Channel get playable => Channel(
        id: 'rec_$id',
        name: title,
        url: path,
        logo: channel.logo,
        group: channel.name,
        type: ContentType.movie,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'src': sourceId,
        'ch': channel.toJson(),
        'title': title,
        'kind': kind.index,
        'url': url,
        'ua': userAgent,
        'start': start,
        'stop': stop,
        'status': status.index,
        'path': path,
        'bytes': bytes,
        'total': totalBytes,
        'err': error,
        if (ruleId.isNotEmpty) 'rule': ruleId,
        if (progStart != 0) 'ps': progStart,
      };

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'] as String,
        sourceId: j['src'] as String,
        channel: Channel.fromJson(j['ch'] as Map<String, dynamic>),
        title: j['title'] as String,
        kind: RecKind.values[j['kind'] as int],
        url: j['url'] as String,
        userAgent: (j['ua'] as String?) ?? '',
        start: j['start'] as int,
        stop: j['stop'] as int,
        status: RecStatus.values[j['status'] as int],
        path: (j['path'] as String?) ?? '',
        bytes: (j['bytes'] as int?) ?? 0,
        totalBytes: (j['total'] as int?) ?? 0,
        error: (j['err'] as String?) ?? '',
        ruleId: (j['rule'] as String?) ?? '',
        progStart: (j['ps'] as int?) ?? 0,
      );
}

/// Frequence d'un enregistrement.
enum RecRepeat {
  /// Une seule fois.
  once,

  /// Chaque diffusion de l'emission (meme titre, meme chaine, selon le guide).
  everyAiring,

  /// Chaque semaine, meme jour et meme heure.
  weekly,
}

/// Serie d'enregistrements (emission recurrente).
class RecRule {
  final String id;
  final String sourceId;
  final Channel channel;
  final String title;
  final String userAgent;
  final RecRepeat mode;

  /// Pour [RecRepeat.weekly] : jour (lundi = 1), heure de debut en minutes
  /// depuis minuit, et duree en minutes.
  final int weekday;
  final int minuteOfDay;
  final int durationMin;

  /// Diffusions annulees a la main (debut de l'emission en ms).
  final Set<int> skip;
  final int created;

  RecRule({
    required this.id,
    required this.sourceId,
    required this.channel,
    required this.title,
    required this.mode,
    this.userAgent = '',
    this.weekday = 1,
    this.minuteOfDay = 0,
    this.durationMin = 60,
    Set<int>? skip,
    int? created,
  })  : skip = skip ?? <int>{},
        created = created ?? DateTime.now().millisecondsSinceEpoch;

  static String normalize(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9\u00C0-\u017F]'), '');

  bool matches(Programme p) => normalize(p.title) == normalize(title);

  /// Prochaines diffusions hebdomadaires (debut, fin) a partir de [now].
  List<(int, int)> weeklyOccurrences(DateTime now, {int days = 8}) {
    final out = <(int, int)>[];
    for (var i = 0; i < days; i++) {
      final d = DateTime(now.year, now.month, now.day + i);
      if (d.weekday != weekday) continue;
      final start = DateTime(d.year, d.month, d.day, minuteOfDay ~/ 60, minuteOfDay % 60);
      final stop = start.add(Duration(minutes: durationMin));
      if (stop.isAfter(now)) {
        out.add((start.millisecondsSinceEpoch, stop.millisecondsSinceEpoch));
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'src': sourceId,
        'ch': channel.toJson(),
        'title': title,
        'ua': userAgent,
        'mode': mode.index,
        'wd': weekday,
        'min': minuteOfDay,
        'dur': durationMin,
        'skip': skip.toList(),
        'created': created,
      };

  factory RecRule.fromJson(Map<String, dynamic> j) => RecRule(
        id: j['id'] as String,
        sourceId: j['src'] as String,
        channel: Channel.fromJson(j['ch'] as Map<String, dynamic>),
        title: j['title'] as String,
        userAgent: (j['ua'] as String?) ?? '',
        mode: RecRepeat.values[j['mode'] as int],
        weekday: (j['wd'] as int?) ?? 1,
        minuteOfDay: (j['min'] as int?) ?? 0,
        durationMin: (j['dur'] as int?) ?? 60,
        skip: {for (final e in (j['skip'] as List? ?? const [])) e as int},
        created: j['created'] as int?,
      );
}

class _Job {
  bool cancelled = false;
  void Function()? abort;
}

/// Enregistre les chaines en direct (immediatement ou a l'heure prevue)
/// et telecharge les rattrapages et les films.
///
/// L'enregistrement copie le flux tel quel (sans re-encodage) : il ne
/// consomme presque pas de processeur. L'application doit rester ouverte
/// pendant l'enregistrement.
class RecordingService extends ChangeNotifier {
  final Settings settings;
  RecordingService(this.settings);

  late SharedPreferences _prefs;
  List<Recording> items = [];
  List<RecRule> rules = [];
  final _jobs = <String, _Job>{};

  /// Dernier guide connu (pour les series "chaque diffusion").
  String _guideSource = '';
  EpgData _guide = EpgData.empty;
  int _lastRules = 0;
  Timer? _timer;
  Timer? _uiTimer;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
    // Un enregistrement interrompu par la fermeture de l'app reprend
    // s'il n'est pas termine.
    for (final r in items) {
      if (r.status == RecStatus.recording) {
        r.status = r.kind == RecKind.live &&
                r.stop > DateTime.now().millisecondsSinceEpoch
            ? RecStatus.scheduled
            : RecStatus.failed;
        if (r.status == RecStatus.failed) r.error = 'interrupted';
      }
    }
    _save();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    _tick();
  }

  void _load() {
    final rawRules = _prefs.getString('rec_rules');
    if (rawRules != null) {
      try {
        rules = [
          for (final e in jsonDecode(rawRules) as List)
            RecRule.fromJson(e as Map<String, dynamic>),
        ];
      } catch (_) {}
    }
    final raw = _prefs.getString('recordings');
    if (raw == null) return;
    try {
      items = [
        for (final e in jsonDecode(raw) as List)
          Recording.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {}
  }

  Future<void> reload() async {
    await _prefs.reload();
    if (_jobs.isEmpty) {
      _load();
      notifyListeners();
    }
  }

  void _save() {
    _prefs.setString(
        'recordings', jsonEncode([for (final r in items) r.toJson()]));
    _prefs.setString(
        'rec_rules', jsonEncode([for (final r in rules) r.toJson()]));
    _syncBackground();
  }

  static const _bg = MethodChannel('streamflow/background');
  String? _bgState;

  /// Fait en sorte que les enregistrements se fassent meme app fermee :
  /// - Android : service au premier plan + alarme systeme qui relance
  ///   l'app a l'heure prevue (meme apres un redemarrage).
  /// - Windows : tache planifiee qui ouvre Canalix (reduit) a l'heure
  ///   prevue et reveille l'ordinateur s'il est en veille.
  Future<void> _syncBackground() async {
    if (!Platform.isAndroid && !Platform.isWindows) return;
    final active = items.where((r) => r.active).toList();
    final planned = items
        .where((r) => r.status == RecStatus.scheduled)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (Platform.isWindows) {
      _syncWindowsTask(planned.isEmpty ? null : planned.first);
      _syncWindowsAutostart();
      return;
    }
    String? state;
    Map<String, Object>? args;
    if (active.isNotEmpty) {
      state = 'rec:${active.map((r) => r.id).join(',')}';
      args = {
        'title': tr('rec.bgRecording', [active.length]),
        'text': active.map((r) => r.title).join(', '),
        'active': true,
      };
    } else if (planned.isNotEmpty) {
      final n = planned.first;
      state = 'plan:${n.id}:${n.start}';
      args = {
        'title': tr('rec.bgPlanned'),
        'text': '${n.title} · ${dayTime(n.start)}',
        'active': false,
      };
    }
    if (args == null && keepAlive) {
      state = 'home';
      args = {
        'title': tr('home.bgTitle'),
        'text': tr('home.bgText'),
        'active': true,
      };
    }
    if (state == _bgState) return;
    _bgState = state;
    try {
      await _bg.invokeMethod('home', keepAlive);
      await _bg.invokeMethod('alarm', {
        'at': planned.isEmpty ? 0 : planned.first.start,
        'title': planned.isEmpty ? '' : planned.first.title,
      });
      if (args == null) {
        await _bg.invokeMethod('stop');
      } else {
        await Notifier.requestPermission();
        await _bg.invokeMethod('start', args);
      }
    } catch (_) {}
  }

  /// Android 12+ : l'autorisation "Alarmes et rappels" permet de demarrer
  /// a la seconde pres. Sans elle, Android peut decaler de quelques minutes.
  Future<bool> canStartOnTime() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _bg.invokeMethod<bool>('canExact') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> askStartOnTime() async {
    try {
      await _bg.invokeMethod('askExact');
    } catch (_) {}
  }

  bool? _autostart;

  /// Enregistreur maison sur Windows : Canalix demarre (reduit) a
  /// l'ouverture de la session.
  Future<void> _syncWindowsAutostart() async {
    if (_autostart == keepAlive) return;
    _autostart = keepAlive;
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    try {
      if (keepAlive) {
        await Process.run('reg', [
          'add', key, '/v', 'Canalix', '/t', 'REG_SZ', '/d',
          '"${Platform.resolvedExecutable}" --background', '/f'
        ]);
      } else {
        await Process.run('reg', ['delete', key, '/v', 'Canalix', '/f']);
      }
    } catch (_) {
      _autostart = null;
    }
  }

  static const _winTask = r'Canalix\ProchainEnregistrement';
  String? _winState;

  Future<void> _syncWindowsTask(Recording? next) async {
    final state = next == null ? '' : '${next.id}:${next.start}';
    if (state == _winState) return;
    _winState = state;
    try {
      if (next == null) {
        await Process.run('schtasks', ['/Delete', '/TN', _winTask, '/F'],
            runInShell: false);
        return;
      }
      // Ouvre l'app 2 minutes avant pour laisser le temps de se connecter.
      final at = DateTime.fromMillisecondsSinceEpoch(next.start)
          .subtract(const Duration(minutes: 2));
      String two(int n) => n.toString().padLeft(2, '0');
      final boundary = '${at.year}-${two(at.month)}-${two(at.day)}'
          'T${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
      String esc(String v) => v
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');
      final exe = esc(Platform.resolvedExecutable);
      final xml = '<?xml version="1.0" encoding="UTF-16"?>\r\n'
          '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">'
          '<RegistrationInfo><Description>${esc(tr('rec.bgPlanned'))} : ${esc(next.title)}</Description></RegistrationInfo>'
          '<Triggers><TimeTrigger><StartBoundary>$boundary</StartBoundary><Enabled>true</Enabled></TimeTrigger></Triggers>'
          '<Principals><Principal id="Author"><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>'
          '<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>'
          '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>'
          '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>'
          '<StartWhenAvailable>true</StartWhenAvailable>'
          '<WakeToRun>true</WakeToRun>'
          '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>'
          '<Enabled>true</Enabled></Settings>'
          '<Actions Context="Author"><Exec><Command>"$exe"</Command><Arguments>--background</Arguments></Exec></Actions>'
          '</Task>';
      final f = File('${Directory.systemTemp.path}\\canalix_task.xml');
      // UTF-16 LE avec BOM, comme l'attend schtasks.
      final units = <int>[0xFF, 0xFE];
      for (final c in xml.codeUnits) {
        units
          ..add(c & 0xFF)
          ..add(c >> 8);
      }
      await f.writeAsBytes(units, flush: true);
      await Process.run(
          'schtasks', ['/Create', '/TN', _winTask, '/XML', f.path, '/F']);
      try {
        await f.delete();
      } catch (_) {}
    } catch (_) {
      _winState = null;
    }
  }

  /// Espace libre et total (octets) du disque des enregistrements, et
  /// la place prise par les enregistrements termines ou en cours.
  Future<({int free, int total, int used})?> storage() async {
    final used = items.fold<int>(0, (a, r) => a + r.bytes);
    try {
      final dir = (await folder()).path;
      int? free, total;
      if (Platform.isAndroid) {
        final m = await _bg.invokeMapMethod<String, dynamic>(
            'storage', {'path': dir});
        free = (m?['free'] as num?)?.toInt();
        total = (m?['total'] as num?)?.toInt();
      } else if (Platform.isWindows) {
        final drive = dir.length >= 2 && dir[1] == ':'
            ? dir.substring(0, 1)
            : 'C';
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"$d=Get-PSDrive -Name " "$drive" r"; Write-Output ($d.Free.ToString() + ' ' + ($d.Free + $d.Used).ToString())",
        ]);
        final parts = '${r.stdout}'.trim().split(RegExp(r'\s+'));
        if (parts.length == 2) {
          free = int.tryParse(parts[0]);
          total = int.tryParse(parts[1]);
        }
      } else if (Platform.isMacOS || Platform.isLinux) {
        final r = await Process.run('df', ['-Pk', dir]);
        final lines = '${r.stdout}'.trim().split('\n');
        if (lines.length >= 2) {
          final c = lines.last.trim().split(RegExp(r'\s+'));
          if (c.length >= 4) {
            total = (int.tryParse(c[1]) ?? 0) * 1024;
            free = (int.tryParse(c[3]) ?? 0) * 1024;
          }
        }
      }
      if (free == null || total == null || total <= 0) {
        return (free: -1, total: -1, used: used);
      }
      return (free: free, total: total, used: used);
    } catch (_) {
      return (free: -1, total: -1, used: used);
    }
  }

  /// Dossier ou sont ranges les enregistrements.
  Future<Directory> folder() async {
    Directory d;
    if (settings.recFolder.isNotEmpty) {
      d = Directory(settings.recFolder);
    } else if (Platform.isWindows) {
      d = Directory(
          '${Platform.environment['USERPROFILE'] ?? '.'}\\Videos\\Canalix');
    } else if (Platform.isMacOS) {
      d = Directory('${Platform.environment['HOME']}/Movies/Canalix');
    } else if (Platform.isLinux) {
      d = Directory('${Platform.environment['HOME']}/Videos/Canalix');
    } else if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      d = Directory(
          '${(ext ?? await getApplicationDocumentsDirectory()).path}/Recordings');
    } else {
      d = Directory(
          '${(await getApplicationDocumentsDirectory()).path}/Recordings');
    }
    await d.create(recursive: true);
    return d;
  }

  bool isScheduled(String sourceId, Channel c, Programme p) => items.any((r) =>
      r.sourceId == sourceId &&
      r.channel.id == c.id &&
      r.kind == RecKind.live &&
      !r.finished &&
      r.start <= p.start &&
      r.stop >= p.stop - 60000);

  Recording? recordingFor(Channel c) => items
      .where((r) => r.channel.id == c.id && r.active && r.kind == RecKind.live)
      .firstOrNull;

  int get activeCount => items.where((r) => r.active).length;

  /// Programme l'enregistrement d'une emission (avec marges).
  Recording scheduleProgramme(Source s, Channel c, Programme p) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var start = p.start - settings.recPadBefore * 60000;
    if (start < now) start = now;
    return _add(Recording(
      id: _newId(),
      sourceId: s.id,
      channel: c,
      title: p.title.isEmpty ? c.name : p.title,
      kind: RecKind.live,
      url: c.url,
      userAgent: s.userAgent,
      start: start,
      stop: p.stop + settings.recPadAfter * 60000,
    ));
  }

  // ------------------------------------------------ Series d'enregistrement

  /// Cree une serie a partir d'une emission du guide et programme les
  /// prochaines diffusions.
  RecRule addRule(Source s, Channel c, Programme p, RecRepeat mode) {
    final start = DateTime.fromMillisecondsSinceEpoch(p.start);
    final rule = RecRule(
      id: _newId(),
      sourceId: s.id,
      channel: c,
      title: p.title.isEmpty ? c.name : p.title,
      userAgent: s.userAgent,
      mode: mode,
      weekday: start.weekday,
      minuteOfDay: start.hour * 60 + start.minute,
      durationMin: p.duration.inMinutes.clamp(1, 24 * 60),
    );
    rules = [...rules, rule];
    // L'emission choisie est toujours enregistree, meme si son titre
    // dans le guide varie un peu.
    _occurrence(rule, p.start, p.stop, rule.title);
    applyRules();
    return rule;
  }

  /// Arrete une serie et annule ses enregistrements prevus.
  void removeRule(RecRule rule) {
    rules = rules.where((r) => r.id != rule.id).toList();
    for (final r in items) {
      if (r.ruleId == rule.id && r.status == RecStatus.scheduled) {
        r.status = RecStatus.cancelled;
      }
    }
    _save();
    notifyListeners();
  }

  RecRule? ruleById(String id) => rules.where((r) => r.id == id).firstOrNull;

  /// Serie qui couvre cette emission, s'il y en a une.
  RecRule? ruleFor(String sourceId, Channel c, Programme p) {
    for (final r in rules) {
      if (r.sourceId != sourceId || r.channel.id != c.id) continue;
      if (r.mode == RecRepeat.everyAiring && r.matches(p)) return r;
      if (r.mode == RecRepeat.weekly) {
        final d = DateTime.fromMillisecondsSinceEpoch(p.start);
        if (d.weekday == r.weekday &&
            (d.hour * 60 + d.minute - r.minuteOfDay).abs() <= 5) {
          return r;
        }
      }
    }
    return null;
  }

  /// Le guide de la source active vient d'etre charge.
  void updateGuide(String sourceId, EpgData epg) {
    _guideSource = sourceId;
    _guide = epg;
    applyRules();
  }

  /// Programme les prochaines diffusions de toutes les series.
  void applyRules() {
    _lastRules = DateTime.now().millisecondsSinceEpoch;
    if (rules.isEmpty) return;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final horizon = nowMs + const Duration(days: 8).inMilliseconds;
    var changed = false;
    for (final rule in rules) {
      rule.skip.removeWhere((t) => t < nowMs - const Duration(days: 2).inMilliseconds);
      if (rule.mode == RecRepeat.weekly) {
        for (final (a, b) in rule.weeklyOccurrences(now)) {
          // Si le guide connait l'emission a cette heure, on prend ses heures exactes.
          final p = _guideMatch(rule, a);
          changed |= _occurrence(rule, p?.start ?? a, p?.stop ?? b,
              p?.title.isNotEmpty == true ? p!.title : rule.title, save: false);
        }
      } else if (rule.mode == RecRepeat.everyAiring &&
          rule.sourceId == _guideSource) {
        for (final p in _guide.forChannel(rule.channel) ?? const <Programme>[]) {
          if (p.stop <= nowMs || p.start > horizon || !rule.matches(p)) continue;
          changed |= _occurrence(rule, p.start, p.stop, p.title, save: false);
        }
      }
    }
    changed |= _mergeAdjacent();
    if (changed) {
      _save();
      notifyListeners();
      _tick();
    }
  }

  Programme? _guideMatch(RecRule rule, int startMs) {
    if (rule.sourceId != _guideSource) return null;
    for (final p in _guide.forChannel(rule.channel) ?? const <Programme>[]) {
      if ((p.start - startMs).abs() <= 5 * 60000) return p;
      if (p.start > startMs + 5 * 60000) break;
    }
    return null;
  }

  /// Ajoute une diffusion d'une serie si elle n'est pas deja prevue.
  bool _occurrence(RecRule rule, int start, int stop, String title,
      {bool save = true}) {
    if (rule.skip.contains(start)) return false;
    final exists = items.any((r) =>
        r.kind == RecKind.live &&
        r.channel.id == rule.channel.id &&
        r.sourceId == rule.sourceId &&
        ((r.ruleId == rule.id && r.progStart == start) ||
            (!r.finished && r.start <= start && r.stop >= stop - 60000)));
    if (exists) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Episodes colles (ex. dessins animes de 11 min a la suite) : on
    // allonge l'enregistrement precedent au lieu d'en creer un de plus.
    if (rule.mode == RecRepeat.everyAiring) {
      for (final r in items) {
        if (r.ruleId != rule.id || r.finished || r.kind != RecKind.live) continue;
        if (r.start <= start && r.stop >= start - _joinGap) {
          final end = stop + settings.recPadAfter * 60000;
          if (end > r.stop) r.stop = end;
          if (save) {
            _save();
            notifyListeners();
          }
          return true;
        }
      }
    }
    var a = start - settings.recPadBefore * 60000;
    if (a < now) a = now;
    final r = Recording(
      id: _newId(),
      sourceId: rule.sourceId,
      channel: rule.channel,
      title: title,
      kind: RecKind.live,
      url: rule.channel.url,
      userAgent: rule.userAgent,
      start: a,
      stop: stop + settings.recPadAfter * 60000,
      ruleId: rule.id,
      progStart: start,
    );
    items = [r, ...items];
    if (save) {
      _save();
      notifyListeners();
    }
    return true;
  }

  /// Ecart maximal entre deux diffusions pour les enregistrer d'un bloc.
  static const _joinGap = 10 * 60000;

  /// Regroupe les diffusions prevues d'une meme serie qui se suivent.
  bool _mergeAdjacent() {
    var changed = false;
    final byRule = <String, List<Recording>>{};
    for (final r in items) {
      if (r.ruleId.isEmpty || r.kind != RecKind.live) continue;
      if (r.status != RecStatus.scheduled && r.status != RecStatus.recording) continue;
      (byRule[r.ruleId] ??= []).add(r);
    }
    final drop = <String>{};
    for (final list in byRule.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
      Recording? cur;
      for (final r in list) {
        if (cur != null &&
            r.status == RecStatus.scheduled &&
            r.start <= cur.stop + _joinGap) {
          if (r.stop > cur.stop) cur.stop = r.stop;
          drop.add(r.id);
          changed = true;
        } else {
          cur = r;
        }
      }
    }
    if (drop.isNotEmpty) items = items.where((r) => !drop.contains(r.id)).toList();
    return changed;
  }

  /// Diffusion d'une serie trouvee dans le guide d'un autre ecran
  /// (enregistreur maison).
  bool addOccurrence(RecRule rule, Programme p) =>
      _occurrence(rule, p.start, p.stop, p.title.isEmpty ? rule.title : p.title);

  /// Enregistreur maison : garde l'appareil eveille en permanence.
  bool keepAlive = false;
  void setKeepAlive(bool v) {
    if (keepAlive == v) return;
    keepAlive = v;
    _bgState = null;
    _syncBackground();
  }

  /// Enregistre tout de suite pendant [duration].
  Recording recordNow(Source s, Channel c, Duration duration, {String? title}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _add(Recording(
      id: _newId(),
      sourceId: s.id,
      channel: c,
      title: title ?? c.name,
      kind: RecKind.live,
      url: c.url,
      userAgent: s.userAgent,
      start: now,
      stop: now + duration.inMilliseconds,
    ));
  }

  /// Telecharge un fichier (rattrapage, film ou episode) pour plus tard.
  Recording download(Source s, Channel c, String url, String title) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _add(Recording(
      id: _newId(),
      sourceId: s.id,
      channel: c,
      title: title,
      kind: RecKind.file,
      url: url,
      userAgent: s.userAgent,
      start: now,
      stop: now,
    ));
  }

  Recording _add(Recording r) {
    items = [r, ...items];
    _save();
    notifyListeners();
    _tick();
    return r;
  }

  int _idSeq = 0;
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idSeq++ % 1296).toRadixString(36)}';

  /// Arrete un enregistrement en cours ou annule un enregistrement prevu.
  void stopRecording(Recording r) {
    final job = _jobs[r.id];
    if (job != null) {
      job.cancelled = true;
      job.abort?.call();
      if (r.kind == RecKind.live) {
        r.stop = DateTime.now().millisecondsSinceEpoch;
      }
    } else if (r.status == RecStatus.scheduled) {
      r.status = RecStatus.cancelled;
      // Une diffusion annulee a la main ne revient pas (ni les episodes
      // regroupes dans le meme bloc).
      final rule = ruleById(r.ruleId);
      if (rule != null) {
        rule.skip.add(r.progStart);
        for (final p in _guide.forChannel(rule.channel) ?? const <Programme>[]) {
          if (p.start >= r.start && p.start < r.stop) rule.skip.add(p.start);
        }
      }
    }
    _save();
    notifyListeners();
  }

  /// Supprime l'entree (et le fichier si [deleteFile]).
  Future<void> delete(Recording r, {bool deleteFile = true}) async {
    stopRecording(r);
    items = items.where((e) => e.id != r.id).toList();
    _save();
    notifyListeners();
    if (deleteFile && r.path.isNotEmpty) {
      try {
        final f = File(r.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (rules.isNotEmpty && now - _lastRules > 60000) applyRules();
    for (final r in items) {
      if (r.status != RecStatus.scheduled || _jobs.containsKey(r.id)) continue;
      if (r.kind == RecKind.file || (now >= r.start && now < r.stop)) {
        _startJob(r);
      } else if (r.kind == RecKind.live && now >= r.stop) {
        r.status = RecStatus.failed;
        r.error = 'missed';
        _save();
        notifyListeners();
      }
    }
  }

  Future<void> _startJob(Recording r) async {
    final job = _Job();
    _jobs[r.id] = job;
    r.status = RecStatus.recording;
    r.error = '';
    _save();
    notifyListeners();
    _uiTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (_jobs.isEmpty) {
        _uiTimer?.cancel();
        _uiTimer = null;
      }
      notifyListeners();
    });

    try {
      if (r.path.isEmpty) {
        final dir = await folder();
        r.path = '${dir.path}${Platform.pathSeparator}${_fileName(r)}';
      }
      if (r.kind == RecKind.live) {
        await _recordLive(r, job);
      } else {
        await _downloadFile(r, job);
      }
      if (job.cancelled && r.kind == RecKind.file) {
        r.status = RecStatus.cancelled;
      } else {
        r.status = r.bytes > 0 ? RecStatus.done : RecStatus.failed;
        if (r.bytes == 0 && r.error.isEmpty) r.error = 'empty';
      }
    } catch (e) {
      r.status = RecStatus.failed;
      r.error = '$e';
    } finally {
      _jobs.remove(r.id);
      _save();
      notifyListeners();
      if (r.status == RecStatus.done) {
        Notifier.show(r.id.hashCode & 0x3fffffff, tr('rec.doneNotif'), r.title);
      }
    }
  }

  String _fileName(Recording r) {
    final d = DateTime.fromMillisecondsSinceEpoch(r.start);
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}h${two(d.minute)}';
    var ext = 'ts';
    if (r.kind == RecKind.file) {
      final path = Uri.tryParse(r.url)?.path ?? '';
      final dot = path.lastIndexOf('.');
      if (dot != -1 && path.length - dot <= 5) {
        ext = path.substring(dot + 1).toLowerCase();
        if (ext == 'm3u8') ext = 'ts';
      }
    }
    final base = r.title == r.channel.name
        ? '${r.title} - $stamp'
        : '${r.title} - ${r.channel.name} - $stamp';
    final safe = base.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    return '${safe.length > 150 ? safe.substring(0, 150) : safe}.$ext';
  }

  Map<String, String> _headers(Recording r) => {
        'User-Agent': r.userAgent.isEmpty ? defaultUserAgent : r.userAgent,
        ...r.channel.headers,
      };

  bool _isHls(String url) => url.toLowerCase().contains('.m3u8');

  /// Enregistre un direct jusqu'a l'heure de fin, avec reconnexion.
  Future<void> _recordLive(Recording r, _Job job) async {
    final sink = File(r.path).openWrite(mode: FileMode.append);
    try {
      var failures = 0;
      while (!job.cancelled &&
          DateTime.now().millisecondsSinceEpoch < r.stop) {
        try {
          if (_isHls(r.url)) {
            await _hls(r, job, sink, untilMs: r.stop);
          } else {
            await _stream(r, job, sink, untilMs: r.stop);
          }
          failures = 0;
        } catch (e) {
          failures++;
          r.error = '$e';
        }
        if (job.cancelled) break;
        // Coupure : on reconnecte apres une courte pause.
        await Future<void>.delayed(
            Duration(seconds: failures == 0 ? 1 : (failures * 2).clamp(2, 15)));
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Telecharge un fichier complet (3 tentatives).
  Future<void> _downloadFile(Recording r, _Job job) async {
    for (var attempt = 0; attempt < 3 && !job.cancelled; attempt++) {
      r.bytes = 0;
      final sink = File(r.path).openWrite();
      var ok = false;
      try {
        if (_isHls(r.url)) {
          await _hls(r, job, sink);
        } else {
          await _stream(r, job, sink);
        }
        ok = true;
      } catch (e) {
        r.error = '$e';
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (ok) {
        r.error = '';
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  /// Copie un flux HTTP continu (MPEG-TS) ou un fichier dans [sink].
  Future<void> _stream(Recording r, _Job job, IOSink sink,
      {int? untilMs}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(r.url));
      _headers(r).forEach(req.headers.set);
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      if (untilMs == null && res.contentLength > 0) {
        r.totalBytes = res.contentLength;
      }
      final done = Completer<void>();
      late StreamSubscription<List<int>> sub;
      Timer? stopTimer;
      void finish([Object? e]) {
        stopTimer?.cancel();
        if (done.isCompleted) return;
        e == null ? done.complete() : done.completeError(e);
      }

      sub = res.timeout(const Duration(seconds: 25)).listen(
        (chunk) {
          sink.add(chunk);
          r.bytes += chunk.length;
        },
        onError: (Object e) {
          sub.cancel();
          finish(e);
        },
        onDone: () {
          // Un direct qui se termine avant l'heure = coupure.
          if (untilMs != null &&
              DateTime.now().millisecondsSinceEpoch < untilMs - 2000) {
            finish(const SocketException('stream ended'));
          } else {
            finish();
          }
        },
        cancelOnError: true,
      );
      job.abort = () {
        sub.cancel();
        finish();
      };
      if (untilMs != null) {
        final left = untilMs - DateTime.now().millisecondsSinceEpoch;
        stopTimer = Timer(Duration(milliseconds: left < 0 ? 0 : left), () {
          sub.cancel();
          finish();
        });
      }
      await done.future;
    } finally {
      job.abort = null;
      client.close(force: true);
    }
  }

  /// Enregistre un flux HLS en concatenant ses segments.
  Future<void> _hls(Recording r, _Job job, IOSink sink, {int? untilMs}) async {
    final client = http.Client();
    job.abort = client.close;
    try {
      final headers = _headers(r);
      // Beaucoup de serveurs redirigent la playlist : les segments se
      // trouvent alors par rapport a l'adresse finale, pas a la premiere.
      Future<(Uint8List, Uri)> fetch(Uri u) async {
        final req = http.Request('GET', u)..headers.addAll(headers);
        final res = await client.send(req).timeout(const Duration(seconds: 30));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          await res.stream.drain<void>().catchError((_) {});
          throw HttpException('HTTP ${res.statusCode}');
        }
        final body =
            await res.stream.toBytes().timeout(const Duration(seconds: 90));
        // L'adresse finale peut etre relative (en-tete Location relatif).
        final finalUrl = res is http.BaseResponseWithUrl
            ? u.resolveUri((res as http.BaseResponseWithUrl).url)
            : u;
        return (body, finalUrl);
      }

      var playlist = Uri.parse(r.url);
      Future<String> getPlaylist(Uri u) async {
        final (body, at) = await fetch(u);
        playlist = at;
        return decodeBytes(body);
      }

      var text = await getPlaylist(playlist);
      // Playlist maitre : on prend la meilleure qualite.
      if (text.contains('#EXT-X-STREAM-INF')) {
        final lines = const LineSplitter().convert(text);
        var best = -1;
        Uri? bestUri;
        for (var i = 0; i < lines.length - 1; i++) {
          if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
          final bw = int.tryParse(RegExp(r'BANDWIDTH=(\d+)')
                      .firstMatch(lines[i])
                      ?.group(1) ??
                  '') ??
              0;
          final next = lines[i + 1].trim();
          if (bw > best && next.isNotEmpty && !next.startsWith('#')) {
            best = bw;
            bestUri = playlist.resolve(next);
          }
        }
        if (bestUri == null) throw const FormatException('HLS');
        text = await getPlaylist(bestUri);
      }

      final seen = <String>{};
      var initDone = false;
      while (!job.cancelled) {
        final lines = const LineSplitter().convert(text);
        var target = 6;
        for (final l in lines) {
          if (l.startsWith('#EXT-X-TARGETDURATION:')) {
            target = int.tryParse(l.substring(22).trim()) ?? 6;
          }
          if (!initDone && l.startsWith('#EXT-X-MAP:')) {
            final u = RegExp(r'URI="([^"]+)"').firstMatch(l)?.group(1);
            if (u != null) {
              final (bytes, _) = await fetch(playlist.resolve(u));
              sink.add(bytes);
              r.bytes += bytes.length;
            }
            initDone = true;
          }
        }
        for (final l in lines) {
          final t = l.trim();
          if (t.isEmpty || t.startsWith('#') || !seen.add(t)) continue;
          if (job.cancelled) break;
          if (untilMs != null &&
              DateTime.now().millisecondsSinceEpoch >= untilMs) {
            return;
          }
          final (bytes, _) = await fetch(playlist.resolve(t));
          sink.add(bytes);
          r.bytes += bytes.length;
        }
        if (text.contains('#EXT-X-ENDLIST')) return;
        if (untilMs != null &&
            DateTime.now().millisecondsSinceEpoch >= untilMs) {
          return;
        }
        await Future<void>.delayed(
            Duration(milliseconds: (target * 500).clamp(1000, 6000)));
        if (job.cancelled) break;
        text = await getPlaylist(playlist);
      }
    } finally {
      job.abort = null;
      client.close();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }
}
