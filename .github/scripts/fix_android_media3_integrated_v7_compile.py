from pathlib import Path

screen = Path('lib/screens/android_media3_texture_player_screen.dart')
text = screen.read_text()
text = text.replace("(event['width'] as num?)?.toDouble() ?? 0;", "(event['width'] as num?)?.toDouble() ?? 0.0;")
text = text.replace("(event['height'] as num?)?.toDouble() ?? 0;", "(event['height'] as num?)?.toDouble() ?? 0.0;")
text = text.replace("(event['pixelWidthHeightRatio'] as num?)?.toDouble() ?? 1;", "(event['pixelWidthHeightRatio'] as num?)?.toDouble() ?? 1.0;")
text = text.replace("(event['displayAspectRatio'] as num?)?.toDouble() ?? 0;", "(event['displayAspectRatio'] as num?)?.toDouble() ?? 0.0;")
text = text.replace("                  : 0);", "                  : 0.0);")
screen.write_text(text)
print('V7 Dart numeric typing corregido.')
