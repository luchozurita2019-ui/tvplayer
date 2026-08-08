from pathlib import Path

path = Path('tooling/apply_v34_patch.py')
s = path.read_text()
needle = 'for token in [\n'
insert = '''s = s.replace(
    "                if ((_isBuffering || _reconnecting || _softRecovering) &&\\n",
    "                if ((_isBuffering || _reconnecting) &&\\n",
)
s = s.replace(
    """                        _softRecovering
                            ? 'Recuperando la señal…'
                            : _normalProbeFallbackUsed && _retryCount == 0
""",
    """                        _normalProbeFallbackUsed && _retryCount == 0
""",
)

'''
if needle not in s:
    raise SystemExit('No se encontró punto de inserción')
s = s.replace(needle, insert + needle, 1)
path.write_text(s)
