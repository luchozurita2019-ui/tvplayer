import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';

import 'providers/iptv_provider.dart';
import 'screens/home_screen.dart';

const bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');

void main() {
  // Inicializa el motor nativo de media_kit antes de correr la app.
  if (!_androidTvBuild) {
    MediaKit.ensureInitialized();
  }
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
        builder: (context, child) {
          if (!_androidTvBuild || child == null) {
            return child ?? const SizedBox.shrink();
          }
          return Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: child,
            ),
          );
        },
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: scheme,
          scaffoldBackgroundColor: darkNavy,
          focusColor: const Color(0x6634A8FF),
          hoverColor: const Color(0x332A9CFF),
          splashColor: const Color(0x4434A8FF),
          highlightColor: const Color(0x2234A8FF),
          visualDensity: _androidTvBuild
              ? const VisualDensity(horizontal: 0.5, vertical: 0.5)
              : VisualDensity.standard,
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
              minimumSize: _androidTvBuild ? const Size(56, 48) : null,
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: ButtonStyle(
              minimumSize: _androidTvBuild
                  ? const WidgetStatePropertyAll(Size(48, 48))
                  : null,
              backgroundColor: _androidTvBuild
                  ? WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return const Color(0x5534A8FF);
                      }
                      return null;
                    })
                  : null,
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
