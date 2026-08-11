from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text()

text = text.replace(
"""  bool _providerIssueHint = false;\n\n  String? _errorMessage;\n""",
"""  bool _providerIssueHint = false;\n\n  String? _baselineTlsVerify;\n  String? _baselineUserAgent;\n  String? _baselineReferrer;\n  String? _baselineHttpHeaderFields;\n\n  String? _errorMessage;\n""",
1,
)

text = text.replace(
"""  List<ServerCompatibilityMode> _compatibilityPlan = const [\n    ServerCompatibilityMode.direct,\n    ServerCompatibilityMode.compatible,\n    ServerCompatibilityMode.liveRecovery,\n    ServerCompatibilityMode.advanced,\n  ];\n""",
"""  List<ServerCompatibilityMode> _compatibilityPlan = const [\n    ServerCompatibilityMode.direct,\n    ServerCompatibilityMode.nativeHttp,\n    ServerCompatibilityMode.mpvHttp,\n    ServerCompatibilityMode.tlsLegacy,\n    ServerCompatibilityMode.compatible,\n    ServerCompatibilityMode.liveRecovery,\n    ServerCompatibilityMode.advanced,\n    ServerCompatibilityMode.xtreamHls,\n  ];\n""",
1,
)

old_config = """      if (platform is NativePlayer) {\n        // keep-open=yes convierte un EOF en una pausa del Player. En IPTV\n"""
new_config = """      if (platform is NativePlayer) {\n        // Guardamos los defaults reales de esta compilación de libmpv. Los\n        // fallbacks HTTP/TLS pueden tocar opciones globales del Player, por lo\n        // que cada apertura restaura estos valores antes de probar otro modo.\n        try {\n          _baselineTlsVerify = (await platform.getProperty('tls-verify')).trim();\n        } catch (_) {}\n        try {\n          _baselineUserAgent = (await platform.getProperty('user-agent')).trim();\n        } catch (_) {}\n        try {\n          _baselineReferrer = (await platform.getProperty('referrer')).trim();\n        } catch (_) {}\n        try {\n          _baselineHttpHeaderFields =\n              (await platform.getProperty('http-header-fields')).trim();\n        } catch (_) {}\n\n        // keep-open=yes convierte un EOF en una pausa del Player. En IPTV\n"""
if old_config not in text:
    raise SystemExit('configure anchor not found')
text = text.replace(old_config, new_config, 1)

old_prepare = """        await platform.setProperty('demuxer-lavf-propagate-opts', 'yes');\n        await platform.setProperty('demuxer-lavf-o', '');\n        await platform.setProperty('stream-lavf-o', '');\n        final disableMime =\n"""
new_prepare = """        await platform.setProperty('demuxer-lavf-propagate-opts', 'yes');\n        await platform.setProperty('demuxer-lavf-o', '');\n        await platform.setProperty('stream-lavf-o', '');\n\n        // Restauramos primero el estado HTTP/TLS original para que un fallback\n        // aprendido por un proveedor no contamine al intento siguiente.\n        if (_baselineTlsVerify != null && _baselineTlsVerify!.isNotEmpty) {\n          await platform.setProperty('tls-verify', _baselineTlsVerify!);\n        }\n        if (_baselineUserAgent != null && _baselineUserAgent!.isNotEmpty) {\n          await platform.setProperty('user-agent', _baselineUserAgent!);\n        }\n        await platform.setProperty(\n          'referrer',\n          _baselineReferrer ?? '',\n        );\n        await platform.setProperty(\n          'http-header-fields',\n          _baselineHttpHeaderFields ?? '',\n        );\n\n        if (_compatibilityMode == ServerCompatibilityMode.tlsLegacy) {\n          // Sólo se usa como fallback HTTPS por endpoint. Nunca desactivamos\n          // verificación TLS globalmente para toda la aplicación.\n          await platform.setProperty('tls-verify', 'no');\n        }\n\n        if (_compatibilityMode == ServerCompatibilityMode.mpvHttp) {\n          // Algunos paneles responden distinto cuando los headers se aplican\n          // directamente en libmpv/libavformat en vez de Media.httpHeaders.\n          final nativeHeaders = channel.resolvedHttpHeaders(_defaultUserAgent);\n          String? takeHeader(String wanted) {\n            String? foundKey;\n            for (final key in nativeHeaders.keys) {\n              if (key.toLowerCase() == wanted.toLowerCase()) {\n                foundKey = key;\n                break;\n              }\n            }\n            if (foundKey == null) return null;\n            return nativeHeaders.remove(foundKey);\n          }\n\n          final userAgent = takeHeader('User-Agent');\n          final referrer = takeHeader('Referer');\n          if (userAgent != null && userAgent.isNotEmpty) {\n            await platform.setProperty('user-agent', userAgent);\n          }\n          if (referrer != null && referrer.isNotEmpty) {\n            await platform.setProperty('referrer', referrer);\n          }\n          if (nativeHeaders.isNotEmpty) {\n            final fields = nativeHeaders.entries\n                .map((entry) => '${entry.key}: ${entry.value}')\n                .join(',');\n            await platform.setProperty('http-header-fields', fields);\n          }\n        }\n\n        final disableMime =\n"""
if old_prepare not in text:
    raise SystemExit('prepare compatibility anchor not found')
text = text.replace(old_prepare, new_prepare, 1)

old_recovery = """      final recoveryMode =\n          _compatibilityMode == ServerCompatibilityMode.nativeHttp ||\n                  _compatibilityMode == ServerCompatibilityMode.xtreamHls\n              ? _compatibilityMode\n              : _compatibilityMode == ServerCompatibilityMode.compatible ||\n"""
new_recovery = """      final recoveryMode =\n          _compatibilityMode == ServerCompatibilityMode.nativeHttp ||\n                  _compatibilityMode == ServerCompatibilityMode.mpvHttp ||\n                  _compatibilityMode == ServerCompatibilityMode.tlsLegacy ||\n                  _compatibilityMode == ServerCompatibilityMode.xtreamHls\n              ? _compatibilityMode\n              : _compatibilityMode == ServerCompatibilityMode.compatible ||\n"""
if old_recovery not in text:
    raise SystemExit('recovery anchor not found')
text = text.replace(old_recovery, new_recovery, 1)

old_switch = """    final ServerCompatibilityMode? target = switch (previous) {\n      ServerCompatibilityMode.direct => ServerCompatibilityMode.liveRecovery,\n      ServerCompatibilityMode.nativeHttp => null,\n      ServerCompatibilityMode.compatible => ServerCompatibilityMode.advanced,\n      ServerCompatibilityMode.liveRecovery => ServerCompatibilityMode.advanced,\n      ServerCompatibilityMode.advanced => null,\n      ServerCompatibilityMode.xtreamHls => null,\n    };\n"""
new_switch = """    final ServerCompatibilityMode? target = switch (previous) {\n      ServerCompatibilityMode.direct => ServerCompatibilityMode.liveRecovery,\n      ServerCompatibilityMode.nativeHttp => null,\n      ServerCompatibilityMode.mpvHttp => null,\n      ServerCompatibilityMode.tlsLegacy => null,\n      ServerCompatibilityMode.compatible => ServerCompatibilityMode.advanced,\n      ServerCompatibilityMode.liveRecovery => ServerCompatibilityMode.advanced,\n      ServerCompatibilityMode.advanced => null,\n      ServerCompatibilityMode.xtreamHls => null,\n    };\n"""
if old_switch not in text:
    raise SystemExit('runtime recovery switch not found')
text = text.replace(old_switch, new_switch, 1)

old_plan = """      final learnedPlan = _compatibility.planFor(profile.preferredMode);\n      _compatibilityPlan = _looksLikeXtreamLiveTs(channelUrl)\n          ? learnedPlan\n          : learnedPlan\n              .where((mode) => mode != ServerCompatibilityMode.xtreamHls)\n              .toList(growable: false);\n"""
new_plan = """      final learnedPlan = _compatibility.planFor(profile.preferredMode);\n      final parsedChannelUri = Uri.tryParse(channelUrl);\n      final isHttps = parsedChannelUri?.scheme.toLowerCase() == 'https';\n      final isXtreamLiveTs = _looksLikeXtreamLiveTs(channelUrl);\n      _compatibilityPlan = learnedPlan\n          .where((mode) =>\n              isHttps || mode != ServerCompatibilityMode.tlsLegacy)\n          .where((mode) =>\n              isXtreamLiveTs || mode != ServerCompatibilityMode.xtreamHls)\n          .toList(growable: false);\n"""
if old_plan not in text:
    raise SystemExit('compatibility plan block not found')
text = text.replace(old_plan, new_plan, 1)

old_open_headers = """      final nativeHttp =\n          _compatibilityMode == ServerCompatibilityMode.nativeHttp ||\n              _compatibilityMode == ServerCompatibilityMode.xtreamHls;\n      final headers = channel.resolvedHttpHeaders(\n        fallbackUserAgent,\n        includeDefaultUserAgent: !nativeHttp,\n      );\n      final playbackUrl = _playbackUrlForMode(channel.url);\n      final media = headers.isEmpty\n          ? Media(playbackUrl)\n          : Media(playbackUrl, httpHeaders: headers);\n"""
new_open_headers = """      final nativeHttp =\n          _compatibilityMode == ServerCompatibilityMode.nativeHttp ||\n              _compatibilityMode == ServerCompatibilityMode.xtreamHls;\n      final useMpvHttp =\n          _compatibilityMode == ServerCompatibilityMode.mpvHttp;\n      final headers = channel.resolvedHttpHeaders(\n        fallbackUserAgent,\n        includeDefaultUserAgent: !nativeHttp,\n      );\n      final playbackUrl = _playbackUrlForMode(channel.url);\n      final media = useMpvHttp || headers.isEmpty\n          ? Media(playbackUrl)\n          : Media(playbackUrl, httpHeaders: headers);\n"""
if old_open_headers not in text:
    raise SystemExit('open headers block not found')
text = text.replace(old_open_headers, new_open_headers, 1)

path.write_text(text)
