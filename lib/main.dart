import 'package:media_kit_video/media_kit_video.dart';

import 'dart:io';
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'l10n/i18n.dart';
import 'player/player_engine.dart';
import 'services/license.dart';
import 'services/migrate.dart';
import 'services/pip.dart';
import 'services/proxy.dart';
import 'services/vault.dart';
import 'services/recorder.dart';
import 'services/reminders.dart';
import 'state/app_state.dart';
import 'state/settings.dart';
import 'ui/home_screen.dart';
import 'ui/legal_screen.dart';
import 'ui/profiles_screen.dart';
import 'ui/reminder_alert.dart';

/// Navigateur global (alertes de rappel affichees par-dessus tout).
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await migrateFromStreamFlow();
  await Vault.init();
  // VPN de l'utilisateur (si configure) avant toute connexion.
  await ProxyBridge.init();

  // Cache d'images en memoire plus genereux (logos de chaines).
  PaintingBinding.instance.imageCache
    ..maximumSize = 2000
    ..maximumSizeBytes = 200 << 20;

  final settings = Settings();
  await settings.init();
  final app = AppState(settings);
  await app.init();
  final reminders = ReminderService(settings);
  await reminders.init();
  final recorder = RecordingService(settings);
  await recorder.init();
  final license = LicenseService();
  await license.init();
  // Les series "chaque diffusion" suivent le guide de la source active.
  var lastGuide = app.epg;
  recorder.updateGuide(app.active?.id ?? '', app.epg);
  app.addListener(() {
    if (identical(app.epg, lastGuide)) return;
    lastGuide = app.epg;
    recorder.updateGuide(app.active?.id ?? '', app.epg);
  });
  final engine = PlayerEngine(settings);
  engine.onProgress = app.saveProgress;
  PipController(engine, settings);
  // Lecture qui echoue : verifier si le fournisseur refuse une connexion
  // de plus (meme compte deja utilise sur un autre appareil).
  engine.addListener(() {
    if (engine.lastError == null) {
      app.clearConnectionsFull();
    } else if (engine.retries >= 2) {
      app.checkConnections();
    }
  });

  // Windows : ouvert tout seul par la tache planifiee pour un
  // enregistrement. On se referme apres si personne n'a touche l'app.
  if (Platform.isWindows && args.contains('--background')) {
    _autoQuitWhenIdle(recorder);
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: engine),
        ChangeNotifierProvider.value(value: reminders),
        ChangeNotifierProvider.value(value: recorder),
        ChangeNotifierProvider.value(value: license),
      ],
      child: const CanalixApp(),
    ),
  );
}

class CanalixApp extends StatelessWidget {
  const CanalixApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.select<Settings, String>((s) => s.effectiveLang);
    final legal = context.select<AppState, bool>((a) => a.legalAccepted);
    final chosen = context.select<AppState, bool>((a) => a.profileChosen);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3D7BFF),
      brightness: Brightness.dark,
      surface: const Color(0xFF0E1116),
    );
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Canalix',
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      supportedLocales: [for (final l in kLanguages.keys) Locale(l)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        visualDensity: VisualDensity.standard,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          },
        ),
      ),
      // Navigation a la telecommande (Android TV) : la touche OK active.
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
      },
      // Echap = retour (ordinateur). Les dialogues et le lecteur gerent
      // Echap eux-memes avant d'arriver ici.
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              navigatorKey.currentState?.maybePop(),
        },
        child: _PipAware(child: child!),
      ),
      // La cle force la reconstruction complete quand la langue change.
      home: KeyedSubtree(
        key: ValueKey('$lang-${context.watch<AppState>().reloadCount.value}'),
        child: !legal
            ? const LegalGate()
            : !chosen
            ? const ProfilesScreen(startup: true)
            : const _UserAgentSync(
                child: ReminderListener(child: HomeScreen()),
              ),
      ),
    );
  }
}

/// Transmet le User-Agent de la source active au moteur de lecture.
class _UserAgentSync extends StatelessWidget {
  final Widget child;
  const _UserAgentSync({required this.child});

  @override
  Widget build(BuildContext context) {
    final ua = context.select<AppState, String>(
      (a) => a.active?.userAgent ?? '',
    );
    context.read<PlayerEngine>().setUserAgent(ua);
    return child;
  }
}

/// Affiche une alerte quand une emission rappelee commence.
class ReminderListener extends StatefulWidget {
  final Widget child;
  const ReminderListener({super.key, required this.child});

  @override
  State<ReminderListener> createState() => _ReminderListenerState();
}

class _ReminderListenerState extends State<ReminderListener> {
  StreamSubscription<Reminder>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = context.read<ReminderService>().due.listen(_onDue);
  }

  void _onDue(Reminder r) {
    final nav = navigatorKey.currentState;
    if (nav != null) showReminderAlert(nav, r);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Dans le mini-lecteur flottant (fenetre minuscule), seule la video
/// s'affiche, quel que soit l'ecran ou se trouvait l'utilisateur.
class _PipAware extends StatelessWidget {
  final Widget child;
  const _PipAware({required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tiny = Platform.isAndroid && size.width < 420 && size.height < 420;
    if (!tiny) return child;
    final engine = context.watch<PlayerEngine>();
    if (engine.current == null) return child;
    return Stack(
      children: [
        Offstage(child: child),
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            child: Video(controller: engine.video, controls: NoVideoControls),
          ),
        ),
      ],
    );
  }
}

void _autoQuitWhenIdle(RecordingService recorder) {
  var touched = false;
  GestureBinding.instance.pointerRouter
      .addGlobalRoute((e) => touched = touched || e is PointerDownEvent);
  HardwareKeyboard.instance.addHandler((_) {
    touched = true;
    return false;
  });
  final started = DateTime.now();
  Timer.periodic(const Duration(minutes: 1), (t) {
    if (touched) {
      t.cancel();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final busy = recorder.items.any((r) =>
        r.active ||
        (r.status == RecStatus.scheduled &&
            r.start - now < const Duration(minutes: 15).inMilliseconds));
    // Marge de 5 minutes au demarrage (connexion, guide).
    if (!busy && DateTime.now().difference(started).inMinutes >= 5) {
      t.cancel();
      exit(0);
    }
  });
}
