from pathlib import Path

# Run the already-corrected migration first.
source = Path('.github/scripts/port_provider_resolver_v2.py').read_text()
exec(compile(source, '.github/scripts/port_provider_resolver_v2.py', 'exec'))

# The previous regression expected a relative URL without base_url to be
# rejected. With the provider resolver architecture, that case must be kept as
# a dynamic channel so it can be resolved just-in-time at playback.
path = Path('test/provider_json_relative_url_test.dart')
text = path.read_text()
old = """  test('ruta relativa sin base del proveedor no se acepta', () {
    expect(
      () => parser.parse(catalog(url: 'live/channel/manifest.mpd')),
      throwsFormatException,
    );
  });
"""
new = """  test('ruta relativa sin base se conserva para el resolvedor', () {
    final result = parser.parse(catalog(url: 'live/channel/manifest.mpd'));
    final channel = result.channels.single;

    expect(channel.dynamicStreamId, 'live/channel/manifest.mpd');
    expect(channel.dynamicStreamPath, 'live/channel/manifest.mpd');
    expect(channel.url, startsWith('tvfull-dynamic://stream/'));
    expect(channel.streamMimeType, 'application/dash+xml');
  });
"""
if old not in text:
    raise SystemExit('Old relative URL regression block not found')
path.write_text(text.replace(old, new, 1))
