import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'providers/iptv_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const TvFullProApp());
}

class TvFullProApp extends StatelessWidget {
  const TvFullProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => IptvProvider(),
      child: MaterialApp(
        title: 'TV FULL PRO',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF05090F),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF42AFFF),
            secondary: Color(0xFF6AC4FF),
            surface: Color(0xFF0B141E),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF08111A),
            foregroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
          ),
          focusColor: const Color(0xFF42AFFF).withValues(alpha: .22),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        shortcuts: <ShortcutActivator, Intent>{
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.numpadEnter):
              const ActivateIntent(),
        },
        home: const HomeScreen(),
      ),
    );
  }
}
