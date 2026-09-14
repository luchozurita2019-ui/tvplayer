import 'dart:convert';

// Datos sintéticos: nunca usar catálogos ni credenciales reales en tests.
const testKeyId = '00112233445566778899aabbccddeeff';
const testKey = 'ffeeddccbbaa99887766554433221100';
const testPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg6Pj/HwAEmgKHIN7SxQAAAABJRU5ErkJggg==';

Map<String, Object?> providerSample({bool drm = true, bool icon = true}) => {
  'name': 'ESPN HD',
  'type': 'HLS',
  if (icon) 'icono': 'data:image/png;base64,$testPngBase64',
  if (drm) 'drm_license_uri': 'kid:$testKeyId,k:$testKey',
  'original_url': 'https://provider.example.test/stream/index.m3u8',
  'headers': {
    'Origin': 'https://provider.example.test',
    'Referer': 'https://provider.example.test/',
    'User-Agent': 'Provider test agent',
  },
};

String providerFixture([List<Object?>? samples]) => jsonEncode({
  // Deliberadamente no coincide: se deben contar los samples reales.
  'summary': {'categories': 5, 'streams': 120},
  'categories': [
    {
      'name': 'Lista de deportes',
      'samples': samples ?? [providerSample()],
    },
  ],
});
