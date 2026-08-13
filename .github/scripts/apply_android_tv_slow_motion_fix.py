from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text()
anchor = "        await platform.setProperty('demuxer-thread', 'yes');\n"
patch = """        await platform.setProperty('demuxer-thread', 'yes');

        // Android TV: el audio avanza a tiempo real pero el video puede quedar
        // atrasado si la CPU no alcanza a decodificar todos los cuadros.
        if (_isAndroidRuntime) {
          try {
            await platform.setProperty('hwdec', 'mediacodec-copy');
          } catch (_) {
            try {
              await platform.setProperty('hwdec', 'auto-safe');
            } catch (_) {}
          }
          try {
            await platform.setProperty('framedrop', 'decoder+vo');
          } catch (_) {}
          try {
            await platform.setProperty('video-sync', 'audio');
          } catch (_) {}
          try {
            await platform.setProperty('interpolation', 'no');
          } catch (_) {}
        }
"""

if "mediacodec-copy" not in text:
    if anchor not in text:
        raise SystemExit('Playback anchor not found')
    text = text.replace(anchor, patch, 1)
    path.write_text(text)
