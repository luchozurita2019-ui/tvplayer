import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playback_settings.dart';

class PlaybackSettingsService {
  static const _key = 'playback_settings_v1';

  Future<PlaybackSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return PlaybackSettings.balanced;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return PlaybackSettings.fromJson(decoded);
    } catch (_) {
      return PlaybackSettings.balanced;
    }
  }

  Future<void> save(PlaybackSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
