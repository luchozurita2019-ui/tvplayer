import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'providers/iptv_provider.dart';
import 'screens/home_screen.dart';
import 'services/parental_control_service.dart';
import 'services/remote_access_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ParentalControlService.instance.init();
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
        builder: (context, child) {
          final provider = context.watch<IptvProvider>();
          final blocked =
              provider.initialized ? remoteAccessBlockMessage(provider) : null;
          if (blocked == null) return child ?? const SizedBox.shrink();
          return Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              const ModalBarrier(
                dismissible: false,
                color: Color(0xF205090F),
              ),
              Material(
                color: Colors.transparent,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 52),
                          const SizedBox(height: 16),
                          const Text(
                            'TV FULL PRO',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            blocked,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'El catálogo guardado se conserva. Al reactivar el servicio volverá a habilitarse sin descargar todo otra vez.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        home: const HomeScreen(),
      ),
    );
  }
}
