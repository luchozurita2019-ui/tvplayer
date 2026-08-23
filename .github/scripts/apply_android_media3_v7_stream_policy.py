from pathlib import Path

ROOT = Path('.')
candidates = list((ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'))
if not candidates:
    raise SystemExit('No se encontro MainActivity.kt')
main = candidates[0]
text = main.read_text()


def replace_once(old: str, new: str, label: str):
    global text
    if old not in text:
        raise SystemExit(f'No se encontro marcador: {label}')
    text = text.replace(old, new, 1)

replace_once(
    '    private var firstFrameReported = false\n',
    '''    private var firstFrameReported = false
    private var currentStartupTimeoutMs = STARTUP_TIMEOUT_MS
    private var currentRebufferTimeoutMs = REBUFFER_TIMEOUT_MS
    private var currentReadTimeoutMs = 8000
    private var currentStreamKind = "AUTO"
''',
    'stream policy fields',
)

replace_once(
    '''        cancelStartupTimeout()
        cancelRebufferTimeout()

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setConnectTimeoutMs(5000)
            .setReadTimeoutMs(8000)
            .setAllowCrossProtocolRedirects(true)''',
    '''        cancelStartupTimeout()
        cancelRebufferTimeout()

        val parsed = Uri.parse(url)
        val path = parsed.path?.lowercase() ?: ""
        val isHlsStream = path.endsWith(".m3u8")
        val isTsStream = path.endsWith(".ts")
        when {
            isHlsStream -> {
                currentStreamKind = "HLS"
                currentStartupTimeoutMs = 5000L
                currentRebufferTimeoutMs = 15000L
                currentReadTimeoutMs = 8000
            }
            isTsStream -> {
                currentStreamKind = "TS"
                currentStartupTimeoutMs = 4000L
                currentRebufferTimeoutMs = 10000L
                currentReadTimeoutMs = 6000
            }
            else -> {
                currentStreamKind = "AUTO"
                currentStartupTimeoutMs = 5000L
                currentRebufferTimeoutMs = 12000L
                currentReadTimeoutMs = 8000
            }
        }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setConnectTimeoutMs(5000)
            .setReadTimeoutMs(currentReadTimeoutMs)
            .setAllowCrossProtocolRedirects(true)''',
    'per-format HTTP policy',
)

replace_once(
    '''        val parsed = Uri.parse(url)
        val path = parsed.path?.lowercase() ?: ""
        val itemBuilder = MediaItem.Builder().setUri(parsed)''',
    '''        val itemBuilder = MediaItem.Builder().setUri(parsed)''',
    'deduplicate parsed URL',
)

replace_once(
    '        }.also { handler.postDelayed(it, STARTUP_TIMEOUT_MS) }',
    '        }.also { handler.postDelayed(it, currentStartupTimeoutMs) }',
    'startup timeout policy',
)
replace_once(
    '                        "error" to "El canal no entregó señal en 5 segundos",',
    '''                        "error" to (
                            "El canal no entregó señal a tiempo · " +
                            currentStreamKind
                        ),''',
    'startup timeout message',
)
replace_once(
    '        }.also { handler.postDelayed(it, REBUFFER_TIMEOUT_MS) }',
    '        }.also { handler.postDelayed(it, currentRebufferTimeoutMs) }',
    'rebuffer timeout policy',
)
replace_once(
    '                        "error" to "La señal dejó de entregar datos durante 15 segundos",',
    '''                        "error" to (
                            "La señal dejó de entregar datos · " +
                            currentStreamKind
                        ),''',
    'rebuffer timeout message',
)

replace_once(
    '''        firstFrameReported = false
        openStartedAtMs = 0L
    }''',
    '''        firstFrameReported = false
        openStartedAtMs = 0L
        currentStartupTimeoutMs = STARTUP_TIMEOUT_MS
        currentRebufferTimeoutMs = REBUFFER_TIMEOUT_MS
        currentReadTimeoutMs = 8000
        currentStreamKind = "AUTO"
    }''',
    'reset stream policy',
)

main.write_text(text)

for marker in [
    'currentStreamKind = "HLS"',
    'currentStreamKind = "TS"',
    'currentStartupTimeoutMs = 4000L',
    'currentRebufferTimeoutMs = 10000L',
    'currentRebufferTimeoutMs = 15000L',
    '.setReadTimeoutMs(currentReadTimeoutMs)',
]:
    if marker not in text:
        raise SystemExit(f'Falta politica TS/HLS: {marker}')

print('Politica live V7 aplicada: TS rapido, HLS tolerante y AUTO intermedio.')
