import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/i18n.dart';

/// Mode de mise en memoire tampon du lecteur.
enum BufferMode { fast, balanced, stable }

/// Qualite preferee pour les flux adaptatifs (HLS).
enum StreamQuality { best, fhd, hd, low }

/// Reglages globaux de l'application, sauvegardes sur l'appareil.
class Settings extends ChangeNotifier {
  late SharedPreferences _prefs;

  /// 'auto' (langue du systeme) ou un code de [kLanguages].
  String lang = 'auto';

  BufferMode bufferMode = BufferMode.balanced;
  bool hwdec = true;
  StreamQuality quality = StreamQuality.best;

  /// Pause du direct : garde jusqu'a [timeshiftMinutes] du direct sur disque.
  bool timeshift = true;
  int timeshiftMinutes = 60;

  /// Langues preferees (codes separes par des virgules, ex. "fr,fre,fra").
  String audioLangs = '';
  String subLangs = '';

  /// Minutes d'avance pour les rappels.
  int reminderLead = 2;

  /// Passer automatiquement sur la chaine au debut d'une emission rappelee.
  bool reminderAutoSwitch = false;

  /// Dossier des enregistrements (vide = dossier par defaut).
  String recFolder = '';
  int recPadBefore = 1;
  int recPadAfter = 3;

  /// Code parental (vide = desactive).
  String parentalPin = '';

  /// Verrouille automatiquement les categories pour adultes.
  bool lockAdult = true;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('settings_v1');
    if (raw != null) {
      try {
        _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Reglages corrompus : valeurs par defaut.
      }
    }
    _applyLang();
  }

  /// Code de langue reellement utilise.
  String get effectiveLang {
    if (lang != 'auto' && kLanguages.containsKey(lang)) return lang;
    final sys = PlatformDispatcher.instance.locale.languageCode;
    return kLanguages.containsKey(sys) ? sys : 'fr';
  }

  void _applyLang() => currentLang = effectiveLang;

  void update(void Function(Settings s) change) {
    change(this);
    _applyLang();
    _prefs.setString('settings_v1', jsonEncode(toJson()));
    notifyListeners();
  }

  /// Recharge depuis le stockage (apres une restauration de sauvegarde).
  Future<void> reload() async {
    await _prefs.reload();
    final raw = _prefs.getString('settings_v1');
    if (raw != null) _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _applyLang();
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'lang': lang,
        'buffer': bufferMode.index,
        'hwdec': hwdec,
        'quality': quality.index,
        'timeshift': timeshift,
        'tsMin': timeshiftMinutes,
        'alang': audioLangs,
        'slang': subLangs,
        'remLead': reminderLead,
        'remAuto': reminderAutoSwitch,
        'recFolder': recFolder,
        'recBefore': recPadBefore,
        'recAfter': recPadAfter,
        'pin': parentalPin,
        'lockAdult': lockAdult,
      };

  void _fromJson(Map<String, dynamic> j) {
    T v<T>(String k, T d) => j[k] is T ? j[k] as T : d;
    lang = v('lang', 'auto');
    bufferMode = BufferMode.values[
        v<int>('buffer', 1).clamp(0, BufferMode.values.length - 1)];
    hwdec = v('hwdec', true);
    quality = StreamQuality.values[
        v<int>('quality', 0).clamp(0, StreamQuality.values.length - 1)];
    timeshift = v('timeshift', true);
    timeshiftMinutes = v('tsMin', 60);
    audioLangs = v('alang', '');
    subLangs = v('slang', '');
    reminderLead = v('remLead', 2);
    reminderAutoSwitch = v('remAuto', false);
    recFolder = v('recFolder', '');
    recPadBefore = v('recBefore', 1);
    recPadAfter = v('recAfter', 3);
    parentalPin = v('pin', '');
    lockAdult = v('lockAdult', true);
  }
}
