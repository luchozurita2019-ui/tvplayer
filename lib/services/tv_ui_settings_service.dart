import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TvTextSize { small, normal, large }

extension TvTextSizeLabel on TvTextSize {
  String get label => switch (this) {
        TvTextSize.small => 'Pequeño',
        TvTextSize.normal => 'Normal',
        TvTextSize.large => 'Grande',
      };

  double get scale => switch (this) {
        TvTextSize.small => 0.90,
        TvTextSize.normal => 1.00,
        TvTextSize.large => 1.15,
      };
}

class TvUiSettingsService extends ChangeNotifier {
  static const _textSizeKey = 'tv_full_tv_text_size_v1';

  TvTextSize _textSize = TvTextSize.normal;
  bool _loaded = false;

  TvTextSize get textSize => _textSize;
  double get textScale => _textSize.scale;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_textSizeKey);
    _textSize = TvTextSize.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => TvTextSize.normal,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setTextSize(TvTextSize value) async {
    if (_textSize == value) return;
    _textSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textSizeKey, value.name);
  }
}
