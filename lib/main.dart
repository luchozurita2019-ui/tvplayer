import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'providers/iptv_provider.dart';
import 'screens/remote_access_gate.dart';
import 'services/tv_ui_settings_service.dart';
import 'widgets/tv_remote_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Esta rama es exclusivamente para TV: landscape fijo y experiencia
  // inmersiva para no desperdiciar píxeles ni recursos con barras del sistema.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const IptvPlayerApp());
}

class IptvPlayerApp extends StatelessWidget {
  const IptvPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IptvProvider()),
        ChangeNotifierProvider(
          create: (_) => TvUiSettingsService()..load(),
        ),
      ],
      child: const _TvFullMaterialApp(),
    );
  }
}

class _TvFullMaterialApp extends StatelessWidget {
  const _TvFullMaterialApp();

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF1677FF);
    const darkNavy = Color(0xFF060B12);
    final ui = context.watch<TvUiSettingsService>();

    final scheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: Brightness.dark,
      surface: const Color(0xFF0C1725),
    );

    return MaterialApp(
      title: 'TV FULL PRO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: darkNavy,
        splashFactory: NoSplash.splashFactory,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF08111D),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF0C1725),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0C1725),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: brandBlue, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: brandBlue,
            foregroundColor: Colors.white,
          ),
        ),
        focusColor: brandBlue.withValues(alpha: 0.18),
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(ui.textScale),
          ),
          child: TvRemoteScope(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const RemoteAccessGate(),
    );
  }
}
