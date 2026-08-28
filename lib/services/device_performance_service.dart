import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

class DevicePerformanceService {
  DevicePerformanceService._();
  static final DevicePerformanceService instance = DevicePerformanceService._();

  static const MethodChannel _channel = MethodChannel('tvfull/device_identity');

  bool _initialized = false;
  bool _lowRam = false;
  int _memoryClassMb = 0;

  bool get lowRam => _lowRam;
  int get memoryClassMb => _memoryClassMb;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'getDeviceProfile',
        );
        _lowRam = raw?['lowRam'] == true;
        _memoryClassMb = _toInt(raw?['memoryClassMb']);
        if (_memoryClassMb > 0 && _memoryClassMb <= 128) _lowRam = true;
      } catch (_) {
        // Unknown devices keep the normal conservative profile.
      }
    }
    _applyFlutterImageBudget();
  }

  int? artworkDecodeWidth(int? requested) => _scaledArtworkSize(requested);
  int? artworkDecodeHeight(int? requested) => _scaledArtworkSize(requested);

  int? _scaledArtworkSize(int? requested) {
    if (requested == null || requested <= 0 || !_lowRam) return requested;
    final scaled = (requested * .72).round();
    return scaled < 96 ? 96 : scaled;
  }

  void _applyFlutterImageBudget() {
    final cache = PaintingBinding.instance.imageCache;
    if (_lowRam) {
      cache.maximumSize = 80;
      cache.maximumSizeBytes = 24 * 1024 * 1024;
    } else {
      cache.maximumSize = 180;
      cache.maximumSizeBytes = 48 * 1024 * 1024;
    }
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
