import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'player/player_engine.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/legal_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Cache d'images en memoire plus genereux (logos de chaines).
  PaintingBinding.instance.imageCache
    ..maximumSize = 2000
    ..maximumSizeBytes = 200 << 20;

  final app = AppState();
  await app.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider(create: (_) => PlayerEngine()),
      ],
      child: const StreamFlowApp(),
    ),
  );
}

class StreamFlowApp extends StatelessWidget {
  const StreamFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3D7BFF),
      brightness: Brightness.dark,
      surface: const Color(0xFF0E1116),
    );
    return MaterialApp(
      title: 'StreamFlow',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        visualDensity: VisualDensity.standard,
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        }),
      ),
      // Navigation a la telecommande (Android TV) : la touche OK active.
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      home: context.select<AppState, bool>((a) => a.legalAccepted)
          ? const _UserAgentSync(child: HomeScreen())
          : const LegalGate(),
    );
  }
}

/// Transmet le User-Agent de la source active au moteur de lecture.
class _UserAgentSync extends StatelessWidget {
  final Widget child;
  const _UserAgentSync({required this.child});

  @override
  Widget build(BuildContext context) {
    final ua = context.select<AppState, String>((a) => a.active?.userAgent ?? '');
    context.read<PlayerEngine>().setUserAgent(ua);
    return child;
  }
}
