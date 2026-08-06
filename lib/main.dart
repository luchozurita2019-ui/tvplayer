import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'providers/iptv_provider.dart';
import 'screens/home_screen.dart';

void main() {
  // Inicializa el motor nativo de media_kit antes de correr la app.
  MediaKit.ensureInitialized();
  runApp(const IptvPlayerApp());
}

class IptvPlayerApp extends StatelessWidget {
  const IptvPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => IptvProvider(),
      child: MaterialApp(
        title: 'IPTV Player',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
