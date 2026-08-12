from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text()

old = """    if (diagnostic != null && _hasEverPlayed && _looksLikeConnectionLog(text)) {\n      _providerIssueHint = _looksProviderSpecific(text);\n      _lastConnectionDetail = diagnostic;\n      _scheduleConnectionDiagnosis(\n        severe: log.level == 'error' || log.level == 'fatal',\n      );\n    }\n"""

new = """    if (widget.isLiveContent && !_hasEverPlayed && _opening) {\n      _rememberStartupCompatibilityHint(text);\n      if (_isDefinitiveStartupFailureLog(text)) {\n        final startupDiagnostic = diagnostic ??\n            'mpv/FFmpeg confirmó que el canal no está disponible durante la apertura';\n        scheduleMicrotask(() {\n          if (!mounted) return;\n          _showChannelMaintenance(startupDiagnostic);\n        });\n        return;\n      }\n    }\n\n    if (diagnostic != null && _hasEverPlayed && _looksLikeConnectionLog(text)) {\n      _providerIssueHint = _looksProviderSpecific(text);\n      _lastConnectionDetail = diagnostic;\n      _scheduleConnectionDiagnosis(\n        severe: log.level == 'error' || log.level == 'fatal',\n      );\n    }\n"""

count = text.count(old)
if count != 1:
    raise SystemExit(f'log startup fast-failure hook: expected 1 match, found {count}')

path.write_text(text.replace(old, new, 1))
print('v41b log fast-failure hook applied successfully')
