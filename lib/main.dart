import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'providers/iptv_provider.dart';
import 'screens/remote_access_gate.dart';

void main() {
  // Inicializa el motor nativo de media_kit antes de correr la app.
  MediaKit.ensureInitialized();
  runApp(const IptvPlayerApp());
}

class IptvPlayerApp extends StatelessWidget {
  const IptvPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF1677FF);
    const darkNavy = Color(0xFF07111F);

    final scheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: Brightness.dark,
      surface: const Color(0xFF0B1627),
    );

    return ChangeNotifierProvider(
      create: (_) => IptvProvider(),
      child: MaterialApp(
        title: 'TV FULL',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: scheme,
          scaffoldBackgroundColor: darkNavy,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF09182B),
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
          ),
          navigationRailTheme: NavigationRailThemeData(
            backgroundColor: const Color(0xFF09182B),
            indicatorColor: brandBlue.withValues(alpha: 0.22),
            selectedIconTheme: const IconThemeData(color: brandBlue),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: const Color(0xFF09182B),
            indicatorColor: brandBlue.withValues(alpha: 0.22),
          ),
          cardTheme: const CardThemeData(
            color: Color(0xFF0D1C30),
            surfaceTintColor: Colors.transparent,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF0B182A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        home: const RemoteAccessGate(),
      ),
    );
  }
}
