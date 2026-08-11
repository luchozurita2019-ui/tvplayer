import 'dart:async';

import 'package:http/http.dart' as http;

class InternetSpeedTestResult {
  final double downloadMbps;
  final int latencyMs;
  final int bytesTransferred;
  final Duration transferDuration;
  final DateTime measuredAt;

  const InternetSpeedTestResult({
    required this.downloadMbps,
    required this.latencyMs,
    required this.bytesTransferred,
    required this.transferDuration,
    required this.measuredAt,
  });
}

class InternetSpeedTestService {
  InternetSpeedTestService._();

  static final InternetSpeedTestService instance =
      InternetSpeedTestService._();

  static const String _userAgent = 'TV FULL Internet Test/1.0';
  static final Uri _downloadEndpoint =
      Uri.parse('https://speed.cloudflare.com/__down');

  final http.Client _client = http.Client();

  Future<InternetSpeedTestResult> run({
    Duration requestTimeout = const Duration(seconds: 15),
  }) async {
    final latencySamples = <int>[];
    for (var i = 0; i < 3; i++) {
      final sample = await _download(
        1024,
        timeout: const Duration(seconds: 6),
        sampleId: 'latency-$i',
      );
      latencySamples.add(sample.elapsed.inMilliseconds.clamp(1, 60000));
    }
    latencySamples.sort();
    final latencyMs = latencySamples[latencySamples.length ~/ 2];

    // Calentamiento corto para evitar que DNS/TLS domine la medición grande.
    await _download(
      256 * 1024,
      timeout: requestTimeout,
      sampleId: 'warmup',
    );

    // Dos tamaños progresivos permiten que conexiones rápidas tengan tiempo de
    // alcanzar velocidad sostenida sin consumir una cantidad excesiva de datos.
    final samples = <_DownloadSample>[];
    for (final bytes in const [2 * 1024 * 1024, 8 * 1024 * 1024]) {
      samples.add(
        await _download(
          bytes,
          timeout: requestTimeout,
          sampleId: 'download-$bytes',
        ),
      );
    }

    final usable = samples.where((sample) => sample.bytes > 0).toList();
    if (usable.isEmpty) {
      throw Exception('No se recibieron datos suficientes para medir la velocidad.');
    }

    // Tomamos la mejor muestra sostenida. La muestra pequeña sirve para redes
    // lentas; la de 8 MB evita subestimar enlaces rápidos por el costo inicial.
    var bestMbps = 0.0;
    var totalBytes = 0;
    var totalDuration = Duration.zero;
    for (final sample in usable) {
      final seconds = sample.elapsed.inMicroseconds / 1000000.0;
      if (seconds <= 0) continue;
      final mbps = (sample.bytes * 8) / seconds / 1000000.0;
      if (mbps > bestMbps) bestMbps = mbps;
      totalBytes += sample.bytes;
      totalDuration += sample.elapsed;
    }

    if (bestMbps <= 0) {
      throw Exception('No se pudo calcular una velocidad de descarga válida.');
    }

    return InternetSpeedTestResult(
      downloadMbps: bestMbps,
      latencyMs: latencyMs,
      bytesTransferred: totalBytes,
      transferDuration: totalDuration,
      measuredAt: DateTime.now(),
    );
  }

  Future<_DownloadSample> _download(
    int bytes, {
    required Duration timeout,
    required String sampleId,
  }) async {
    final uri = _downloadEndpoint.replace(
      queryParameters: <String, String>{
        'bytes': '$bytes',
        // Evita que intermediarios reutilicen una respuesta anterior.
        'tvfull': '${DateTime.now().microsecondsSinceEpoch}-$sampleId',
      },
    );

    final stopwatch = Stopwatch()..start();
    final request = http.Request('GET', uri)
      ..headers.addAll(const {
        'User-Agent': _userAgent,
        'Accept': 'application/octet-stream,*/*',
        'Cache-Control': 'no-cache',
      });

    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      stopwatch.stop();
      throw Exception(
        'El servidor de prueba respondió HTTP ${response.statusCode}.',
      );
    }

    var received = 0;
    await for (final chunk in response.stream.timeout(timeout)) {
      received += chunk.length;
    }
    stopwatch.stop();

    return _DownloadSample(bytes: received, elapsed: stopwatch.elapsed);
  }
}

class _DownloadSample {
  final int bytes;
  final Duration elapsed;

  const _DownloadSample({required this.bytes, required this.elapsed});
}
