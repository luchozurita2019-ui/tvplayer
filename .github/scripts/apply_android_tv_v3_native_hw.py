from pathlib import Path

# 1) Let media_kit_video own Android's Surface/MediaCodec path.
player = Path('lib/screens/player_screen.dart')
s = player.read_text(encoding='utf-8')
old = '''        // Android TV: el audio avanza a tiempo real pero el video puede quedar
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
'''
new = '''        // Android TV: no forzamos hwdec/framedrop/video-sync desde la app.
        // media_kit_video administra su Surface nativa y la ruta MediaCodec de
        // Android. Forzar mediacodec-copy obliga a copiar frames al CPU y puede
        // trabar tanto el video como la interfaz en TVs/TV Box modestos.
'''
if old in s:
    s = s.replace(old, new, 1)
elif 'mediacodec-copy' in s:
    raise SystemExit('Unexpected Android hwdec block; refusing blind patch')
player.write_text(s, encoding='utf-8')

# 2) Do not rebuild the full live-video widget on every position event.
view = Path('lib/widgets/live_video_view.dart')
v = view.read_text(encoding='utf-8')
old_pos = '''    _positionSub = widget.player.stream.position.listen((value) {
      if (!mounted) return;
      if (value != _position) {
        _position = value;
        _lastProgressAt = DateTime.now();
      }
      setState(() {});
    });
'''
new_pos = '''    _positionSub = widget.player.stream.position.listen((value) {
      if (!mounted) return;
      if (value != _position) {
        _position = value;
        _lastProgressAt = DateTime.now();
      }
      // En TV en vivo la posición sólo sirve como señal de progreso. Evitamos
      // reconstruir Video + controles varias veces por segundo: el timer de
      // estado actualiza la insignia EN VIVO de forma mucho más barata.
      if (!widget.isLiveContent) {
        setState(() {});
      }
    });
'''
if old_pos not in v:
    raise SystemExit('Position listener anchor not found')
v = v.replace(old_pos, new_pos, 1)
v = v.replace(
    "    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {\n",
    "    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {\n",
    1,
)
view.write_text(v, encoding='utf-8')

# 3) Update registration version for fresh Android TV installs.
remote = Path('lib/services/remote_provisioning_service.dart')
r = remote.read_text(encoding='utf-8')
r = r.replace(
    "'app_version': '1.0.0+1-android-tv-panel-v1',",
    "'app_version': '1.0.0+1-android-tv-panel-v3-native-hw',",
    1,
)
remote.write_text(r, encoding='utf-8')

# Validation.
ps = player.read_text(encoding='utf-8')
vv = view.read_text(encoding='utf-8')
rr = remote.read_text(encoding='utf-8')
if 'mediacodec-copy' in ps:
    raise SystemExit('mediacodec-copy still present')
if "Timer.periodic(const Duration(seconds: 1)" not in vv:
    raise SystemExit('live UI timer was not reduced')
if 'if (!widget.isLiveContent)' not in vv:
    raise SystemExit('live position rebuild guard missing')
if 'android-tv-panel-v3-native-hw' not in rr:
    raise SystemExit('V3 app version marker missing')
print('Android TV V3 native hardware/UI patch applied')
