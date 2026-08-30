from pathlib import Path

ROOT = Path('.')


def replace(path: str, old: str, new: str, count: int = 1):
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:160]!r}')
    p.write_text(text.replace(old, new, count), encoding='utf-8')


# Version bump.
replace('pubspec.yaml', 'version: 1.2.8+20', 'version: 1.2.9+21')

path = 'android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt'

# Persistent LIVE HTTP connection pool.
replace(
    path,
    'import okhttp3.Dns\n',
    'import okhttp3.ConnectionPool\nimport okhttp3.Dns\n',
)

old_clients = '''    private val fallbackDns by lazy { TvFullFallbackDns() }\n    private val fallbackHttpClient by lazy {\n        OkHttpClient.Builder()\n            .dns(fallbackDns)\n            .connectTimeout(12, TimeUnit.SECONDS)\n            .readTimeout(35, TimeUnit.SECONDS)\n            .followRedirects(true)\n            .followSslRedirects(true)\n            .build()\n    }\n'''
new_clients = '''    private val fallbackDns by lazy { TvFullFallbackDns() }\n    private val liveLoadErrorPolicy by lazy { TvFullLiveLoadErrorPolicy() }\n    private val liveHttpClient by lazy {\n        OkHttpClient.Builder()\n            .connectTimeout(4, TimeUnit.SECONDS)\n            .readTimeout(10, TimeUnit.SECONDS)\n            .retryOnConnectionFailure(true)\n            .connectionPool(ConnectionPool(8, 5, TimeUnit.MINUTES))\n            .followRedirects(true)\n            .followSslRedirects(true)\n            .build()\n    }\n    private val fallbackHttpClient by lazy {\n        OkHttpClient.Builder()\n            .dns(fallbackDns)\n            .connectTimeout(12, TimeUnit.SECONDS)\n            .readTimeout(35, TimeUnit.SECONDS)\n            .retryOnConnectionFailure(true)\n            .connectionPool(ConnectionPool(4, 5, TimeUnit.MINUTES))\n            .followRedirects(true)\n            .followSslRedirects(true)\n            .build()\n    }\n'''
replace(path, old_clients, new_clients)

old_factory = '''        if (useFallbackDns) {\n            val cached = fallbackMediaSourceFactory\n            if (cached != null && fallbackMediaSourceKey == key) return cached\n            val okHttpFactory = OkHttpDataSource.Factory(fallbackHttpClient)\n                .setUserAgent(userAgent)\n            if (headers.isNotEmpty()) okHttpFactory.setDefaultRequestProperties(headers)\n            return DefaultMediaSourceFactory(okHttpFactory).also {\n                fallbackMediaSourceFactory = it\n                fallbackMediaSourceKey = key\n            }\n        }\n\n        val cached = normalMediaSourceFactory\n        if (cached != null && normalMediaSourceKey == key) return cached\n        val httpFactory = DefaultHttpDataSource.Factory()\n            .setUserAgent(userAgent)\n            .setAllowCrossProtocolRedirects(true)\n            // LIVE conserva conexión rápida para detectar hosts muertos, pero\n            // permite más tiempo de lectura una vez conectado. Esto protege\n            // contra servidores que entregan segmentos con jitter.\n            .setConnectTimeoutMs(if (isLive) 4000 else 12000)\n            .setReadTimeoutMs(if (isLive) 10000 else 30000)\n        if (headers.isNotEmpty()) httpFactory.setDefaultRequestProperties(headers)\n        return DefaultMediaSourceFactory(httpFactory).also {\n            normalMediaSourceFactory = it\n            normalMediaSourceKey = key\n        }\n'''
new_factory = '''        if (useFallbackDns) {\n            val cached = fallbackMediaSourceFactory\n            if (cached != null && fallbackMediaSourceKey == key) return cached\n            val okHttpFactory = OkHttpDataSource.Factory(fallbackHttpClient)\n                .setUserAgent(userAgent)\n            if (headers.isNotEmpty()) okHttpFactory.setDefaultRequestProperties(headers)\n            val mediaFactory = DefaultMediaSourceFactory(okHttpFactory)\n            if (isLive) mediaFactory.setLoadErrorHandlingPolicy(liveLoadErrorPolicy)\n            return mediaFactory.also {\n                fallbackMediaSourceFactory = it\n                fallbackMediaSourceKey = key\n            }\n        }\n\n        val cached = normalMediaSourceFactory\n        if (cached != null && normalMediaSourceKey == key) return cached\n\n        // LIVE usa un único OkHttpClient por sesión. Esto conserva sockets/TLS\n        // entre manifiestos y segmentos y deja que OkHttp recupere fallos de\n        // conexión antes de escalar el error al reproductor completo.\n        if (isLive) {\n            val okHttpFactory = OkHttpDataSource.Factory(liveHttpClient)\n                .setUserAgent(userAgent)\n            if (headers.isNotEmpty()) okHttpFactory.setDefaultRequestProperties(headers)\n            return DefaultMediaSourceFactory(okHttpFactory)\n                .setLoadErrorHandlingPolicy(liveLoadErrorPolicy)\n                .also {\n                    normalMediaSourceFactory = it\n                    normalMediaSourceKey = key\n                }\n        }\n\n        // VOD conserva su ruta anterior: esta versión toca únicamente LIVE.\n        val httpFactory = DefaultHttpDataSource.Factory()\n            .setUserAgent(userAgent)\n            .setAllowCrossProtocolRedirects(true)\n            .setConnectTimeoutMs(12000)\n            .setReadTimeoutMs(30000)\n        if (headers.isNotEmpty()) httpFactory.setDefaultRequestProperties(headers)\n        return DefaultMediaSourceFactory(httpFactory).also {\n            normalMediaSourceFactory = it\n            normalMediaSourceKey = key\n        }\n'''
replace(path, old_factory, new_factory)

# Marker used by CI verification.
p = ROOT / 'pubspec.yaml'
text = p.read_text(encoding='utf-8')
if '# TV FULL PRO 1.2.9+21 live-session-guardian-v21' not in text:
    text += '\n# TV FULL PRO 1.2.9+21 live-session-guardian-v21\n'
p.write_text(text, encoding='utf-8')
