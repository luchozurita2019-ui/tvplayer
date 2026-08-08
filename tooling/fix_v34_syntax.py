from pathlib import Path

path = Path('lib/screens/player_screen.dart')
s = path.read_text()

s = s.replace(
    """    if (_runtimeStatsBusy ||
        !mounted ||
        !_hasEverPlayed ||
        _opening ||
        _reconnecting ||
) {
""",
    """    if (_runtimeStatsBusy ||
        !mounted ||
        !_hasEverPlayed ||
        _opening ||
        _reconnecting) {
""",
)

s = s.replace(
    """            ? 'Este canal no responde tras varios intentos.
Probá con otro canal o volvé a intentar más tarde.'
""",
    """            ? 'Este canal no responde tras varios intentos.\\nProbá con otro canal o volvé a intentar más tarde.'
""",
)

# Alineación del ternario del overlay de carga.
s = s.replace(
    """                        _normalProbeFallbackUsed && _retryCount == 0
                                ? 'Probando modo compatible…'
                                : _reconnecting
""",
    """                        _normalProbeFallbackUsed && _retryCount == 0
                            ? 'Probando modo compatible…'
                            : _reconnecting
""",
)

path.write_text(s)
