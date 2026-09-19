import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

/// Ruta aislada para páginas web declaradas por Fútbol Total.
///
/// No convierte HTML en stream ni modifica Media3. Android abre un WebView
/// nativo y, al cerrarlo, este route vuelve automáticamente al catálogo.
class AndroidWebPlaybackScreen extends StatefulWidget {
  final Channel channel;

  const AndroidWebPlaybackScreen({
    super.key,
    required this.channel,
  });

  @override
  State<AndroidWebPlaybackScreen> createState() =>
      _AndroidWebPlaybackScreenState();
}

class _AndroidWebPlaybackScreenState extends State<AndroidWebPlaybackScreen> {
  static const MethodChannel _web = MethodChannel('tvfull/web_playback');

  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });

    try {
      final headers = widget.channel.resolvedHttpHeaders(
        '',
        includeDefaultUserAgent: false,
      );
      await _web.invokeMethod<void>('open', <String, Object?>{
        'url': widget.channel.url,
        'headers': headers,
      });
      if (mounted) Navigator.of(context).maybePop();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = error.message ?? 'No se pudo abrir la señal web.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = 'No se pudo abrir la señal web.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _error == null
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Abriendo señal…',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.language_rounded,
                    size: 46,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: _opening ? null : () => unawaited(_open()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Volver'),
                  ),
                ],
              ),
      ),
    );
  }
}
