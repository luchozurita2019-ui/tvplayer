from pathlib import Path

path = Path('lib/screens/player_screen.dart')
s = path.read_text()

old_controller = """    _controller = VideoController(_player);"""
new_controller = """    _controller = VideoController(
      _player,
      configuration: _isAndroidRuntime && _androidTvBuild
          ? const VideoControllerConfiguration(
              // mpv-android no confía en `auto/auto-safe`: intenta primero
              // MediaCodec sin copia y conserva mediacodec-copy como fallback.
              vo: 'gpu',
              hwdec: 'mediacodec,mediacodec-copy',
              enableHardwareAcceleration: true,
            )
          : const VideoControllerConfiguration(),
    );"""
if old_controller not in s:
    raise SystemExit('No se encontró la creación esperada de VideoController')
s = s.replace(old_controller, new_controller, 1)

old_android_comment = """        // Android TV: no forzamos opciones de decodificación/sincronización
        // desde la app. media_kit_video administra su Surface nativa y la ruta
        // MediaCodec de Android para evitar copias innecesarias por CPU.
"""
new_android_block = """        // Android TV: baseline tomado de mpv-android. La Surface/GPU sigue
        // administrada por media_kit_video, pero usamos decisiones explícitas
        // que evitan cambios de semántica de `auto-safe` entre versiones.
        if (_isAndroidRuntime && _androidTvBuild) {
          await platform.setProperty('video-sync', 'audio');
          await platform.setProperty('interpolation', 'no');
          // `vo` descarta frames tardíos sin descartar paquetes antes de decode.
          // Es mucho menos agresivo que decoder+vo y mantiene A/V en tiempo real.
          await platform.setProperty('framedrop', 'vo');
        }
"""
if old_android_comment not in s:
    raise SystemExit('No se encontró el bloque Android TV esperado')
s = s.replace(old_android_comment, new_android_block, 1)

path.write_text(s)
print('Baseline mpv-android V4 aplicado correctamente.')
