from pathlib import Path

TV = Path('native-tv-complete/app/src/main/java/com/tvfull/pro/TvHomeActivity.kt')
text = TV.read_text(encoding='utf-8')
old = '''        reconnectAttempts = 0
        vodRecoveryToken++
        vodRecoveryAttempts = 0
        lastKnownPositionMs = 0L
        forceHlsNextAttempt = false
        hlsFallbackTried = false
        player?.stop()
'''
new = '''        reconnectAttempts = 0
        player?.stop()
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'prepare V6 stop state: expected 1 match, found {count}')
TV.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Native TV V6 preparation applied successfully.')
