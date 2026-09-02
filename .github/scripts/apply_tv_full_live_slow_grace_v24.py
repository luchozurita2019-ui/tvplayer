from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAIN = ROOT / "android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt"
PUBSPEC = ROOT / "pubspec.yaml"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 match, found {count}")
    return text.replace(old, new, 1)


main = MAIN.read_text(encoding="utf-8")

main = replace_once(
    main,
    '''        private const val LIVE_STARTUP_CHECK_INTERVAL_MS = 750L
        private const val LIVE_STARTUP_NO_PROGRESS_MS = 5500L
''',
    '''        private const val LIVE_STARTUP_CHECK_INTERVAL_MS = 750L
        // A los 5,5 s sin progreso entramos en tolerancia, pero no matamos la señal.
        // Sólo declaramos canal muerto tras 9 s completos sin bytes/buffer/tracks.
        private const val LIVE_STARTUP_SLOW_SIGNAL_MS = 5500L
        private const val LIVE_STARTUP_NO_PROGRESS_MS = 9000L
''',
    "startup thresholds",
)

main = replace_once(
    main,
    "        private const val MAX_LIVE_ENDED_RECOVERIES = 2\n",
    "        private const val MAX_LIVE_ENDED_RECOVERIES = 5\n",
    "ended recovery budget",
)

main = replace_once(
    main,
    '''            val age = now - startupStartedAtMs
            val silentFor = now - startupLastProgressAtMs
            if (age < maxWaitMs && silentFor < LIVE_STARTUP_NO_PROGRESS_MS) {
                mainHandler.postDelayed(
                    startupDeadline ?: return@Runnable,
                    LIVE_STARTUP_CHECK_INTERVAL_MS,
                )
                return@Runnable
            }
''',
    '''            val age = now - startupStartedAtMs
            val silentFor = now - startupLastProgressAtMs

            // Fase 1: misma respuesta rápida de siempre. A los 5,5 s no
            // interrumpimos: sólo pasamos a una breve ventana de tolerancia.
            if (age < maxWaitMs && silentFor < LIVE_STARTUP_SLOW_SIGNAL_MS) {
                mainHandler.postDelayed(
                    startupDeadline ?: return@Runnable,
                    LIVE_STARTUP_CHECK_INTERVAL_MS,
                )
                return@Runnable
            }

            // Fase 2: un canal lento todavía puede completar manifiesto/TLS,
            // descubrir tracks o empezar a llenar buffer. Cualquier progreso
            // renueva startupLastProgressAtMs y vuelve a abrir esta ventana.
            if (age < maxWaitMs && silentFor < LIVE_STARTUP_NO_PROGRESS_MS) {
                mainHandler.postDelayed(
                    startupDeadline ?: return@Runnable,
                    LIVE_STARTUP_CHECK_INTERVAL_MS,
                )
                return@Runnable
            }
''',
    "two-stage startup guard",
)

main = replace_once(
    main,
    "    override fun onTracksChanged(tracks: Tracks) = sendTracks()\n",
    '''    override fun onTracksChanged(tracks: Tracks) {
        if (isLive && tracks.groups.isNotEmpty()) {
            // Descubrir tracks demuestra que la señal está viva aunque todavía
            // no haya primer frame. Evitamos matar canales lentos justo antes
            // de que Media3 termine de preparar audio/video.
            val now = System.currentTimeMillis()
            liveNetworkProgressAtMs = now
            startupLastProgressAtMs = maxOf(startupLastProgressAtMs, now)
        }
        sendTracks()
    }
''',
    "track progress signal",
)

MAIN.write_text(main, encoding="utf-8")

pubspec = PUBSPEC.read_text(encoding="utf-8")
pubspec = replace_once(
    pubspec,
    "version: 1.3.1+23\n",
    "version: 1.3.2+24\n",
    "version bump",
)
if "# TV FULL PRO 1.3.2+24 live-slow-grace-v24" not in pubspec:
    pubspec = pubspec.rstrip() + "\n\n# TV FULL PRO 1.3.2+24 live-slow-grace-v24\n"
PUBSPEC.write_text(pubspec, encoding="utf-8")

print("Applied TV FULL PRO 1.3.2+24 live slow-grace detector patch")
