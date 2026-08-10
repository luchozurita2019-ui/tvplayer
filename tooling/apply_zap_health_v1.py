from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f'Pattern not found: {label}')
    text = text.replace(old, new, 1)


# Fix escaped HTTP 5xx detection introduced by the generated patch.
text = text.replace("RegExp(r'\\\\b5\\\\d\\\\d\\\\b')", "RegExp(r'\\b5\\d\\d\\b')")

# Keep the previous live picture visible while preparing the next channel.
replace_once(
    "        _isBuffering = true;\n        _reconnecting = isRetry;\n",
    "        _isBuffering = isZap ? false : true;\n        _reconnecting = isRetry;\n",
    'keep previous picture during zap preparation',
)

# A compatibility retry still belongs to the same user-initiated zap.
replace_once(
    "    if (isZap) {\n      _zapStopwatch = Stopwatch()..start();\n      _zapSession = session;\n    }\n",
    "    if (isZap) {\n      _zapStopwatch = Stopwatch()..start();\n      _zapSession = session;\n    } else if (isRetry && (_zapStopwatch?.isRunning ?? false)) {\n      _zapSession = session;\n    }\n",
    'carry zap timing across retry',
)

# A new channel starts with a clean health verdict.
replace_once(
    "      _providerIssueHint = false;\n      _lastConnectionDetail = null;\n      _resetStreamInfo();\n",
    "      _providerIssueHint = false;\n      _lastConnectionDetail = null;\n      _recentBufferingEvents = 0;\n      _bufferingWindowStartedAt = DateTime.now();\n      _connectionHealth.value = _ConnectionHealthSnapshot.stable;\n      _resetStreamInfo();\n",
    'reset connection health on channel change',
)

# Send the replacement command first, then accept stream events. This narrows
# the race where a late event from the previous channel could be counted as the
# first event of the new one.
replace_once(
    "      _acceptPlaybackEvents = true;\n      final channel = widget.playlist[_currentIndex];\n",
    "      final channel = widget.playlist[_currentIndex];\n",
    'move event acceptance after open command',
)
replace_once(
    "      await _player\n          .open(Media(channel.url, httpHeaders: headers))\n          .timeout(_connectTimeout);\n",
    "      final openFuture = _player.open(Media(channel.url, httpHeaders: headers));\n      _acceptPlaybackEvents = true;\n      await openFuture.timeout(_connectTimeout);\n",
    'open replacement before accepting events',
)

# If a zap ultimately gives up, do not leave its stopwatch running forever.
replace_once(
    "    } else {\n      setState(() {\n        _reconnecting = false;\n",
    "    } else {\n      _zapStopwatch?.stop();\n      _zapSession = null;\n      setState(() {\n        _reconnecting = false;\n",
    'stop failed zap timer',
)

path.write_text(text)
