import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../state/settings.dart';
import 'notifier.dart';

/// Rappel d'une emission a venir.
class Reminder {
  final String id;
  final String sourceId;
  final String channelId;
  final String channelName;
  final String logo;
  final String title;
  final int start;
  final int stop;
  bool notified;

  Reminder({
    required this.id,
    required this.sourceId,
    required this.channelId,
    required this.channelName,
    required this.logo,
    required this.title,
    required this.start,
    required this.stop,
    this.notified = false,
  });

  /// Identifiant numerique pour les notifications systeme.
  int get notifId => id.hashCode & 0x3fffffff;

  static String keyOf(String sourceId, Channel c, Programme p) =>
      '$sourceId|${c.id}|${p.start}';

  Map<String, dynamic> toJson() => {
        'id': id,
        's': sourceId,
        'c': channelId,
        'n': channelName,
        'l': logo,
        't': title,
        'a': start,
        'b': stop,
        'x': notified,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as String,
        sourceId: j['s'] as String,
        channelId: j['c'] as String,
        channelName: j['n'] as String,
        logo: (j['l'] as String?) ?? '',
        title: j['t'] as String,
        start: j['a'] as int,
        stop: j['b'] as int,
        notified: (j['x'] as bool?) ?? false,
      );
}

/// Gere les rappels : notification quelques minutes avant le debut,
/// alerte dans l'application et changement de chaine automatique.
class ReminderService extends ChangeNotifier {
  final Settings settings;
  ReminderService(this.settings);

  late SharedPreferences _prefs;
  List<Reminder> items = [];
  Timer? _timer;

  final _due = StreamController<Reminder>.broadcast();

  /// Emet un rappel quand son emission va commencer (app ouverte).
  Stream<Reminder> get due => _due.stream;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('reminders');
    if (raw != null) {
      try {
        items = [
          for (final e in jsonDecode(raw) as List)
            Reminder.fromJson(e as Map<String, dynamic>),
        ];
      } catch (_) {}
    }
    unawaited(Notifier.init());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    _tick();
  }

  Future<void> reload() async {
    await _prefs.reload();
    final raw = _prefs.getString('reminders');
    items = raw == null
        ? []
        : [
            for (final e in jsonDecode(raw) as List)
              Reminder.fromJson(e as Map<String, dynamic>),
          ];
    notifyListeners();
  }

  void _save() => _prefs.setString(
      'reminders', jsonEncode([for (final r in items) r.toJson()]));

  bool has(String sourceId, Channel c, Programme p) {
    final k = Reminder.keyOf(sourceId, c, p);
    return items.any((r) => r.id == k);
  }

  /// Ajoute ou retire un rappel. Renvoie vrai si un rappel a ete ajoute.
  Future<bool> toggle(String sourceId, Channel c, Programme p) async {
    final k = Reminder.keyOf(sourceId, c, p);
    final existing = items.where((r) => r.id == k).firstOrNull;
    if (existing != null) {
      await remove(existing);
      return false;
    }
    final r = Reminder(
      id: k,
      sourceId: sourceId,
      channelId: c.id,
      channelName: c.name,
      logo: c.logo,
      title: p.title,
      start: p.start,
      stop: p.stop,
    );
    items = [...items, r]..sort((a, b) => a.start.compareTo(b.start));
    _save();
    notifyListeners();
    await Notifier.requestPermission();
    await Notifier.schedule(
      r.notifId,
      DateTime.fromMillisecondsSinceEpoch(r.start)
          .subtract(Duration(minutes: settings.reminderLead)),
      r.title,
      tr('rem.notif', [r.channelName, hm(r.start)]),
    );
    return true;
  }

  Future<void> remove(Reminder r) async {
    items = items.where((e) => e.id != r.id).toList();
    _save();
    notifyListeners();
    await Notifier.cancel(r.notifId);
  }

  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lead = settings.reminderLead * 60000;
    var changed = false;
    for (final r in items) {
      if (!r.notified && now >= r.start - lead && now < r.stop) {
        r.notified = true;
        changed = true;
        if (!Notifier.canSchedule) {
          Notifier.show(r.notifId, r.title,
              tr('rem.notif', [r.channelName, hm(r.start)]));
        }
        _due.add(r);
      }
    }
    final before = items.length;
    items = items.where((r) => r.stop > now).toList();
    if (changed || items.length != before) {
      _save();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _due.close();
    super.dispose();
  }
}
