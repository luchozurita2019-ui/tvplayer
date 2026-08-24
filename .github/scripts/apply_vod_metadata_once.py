from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"Missing expected pattern: {label}")
    return text.replace(old, new, 1)


service_path = Path("lib/services/xtream_vod_service.dart")
text = service_path.read_text()

text = replace_once(
    text,
    """  final String? duration;\n  final String? country;\n  final String? backdrop;\n""",
    """  final String? duration;\n  final String? country;\n  final String? language;\n  final String? originalLanguage;\n  final String? audioInfo;\n  final String? translation;\n  final String? backdrop;\n""",
    "details fields",
)
text = replace_once(
    text,
    """    this.duration,\n    this.country,\n    this.backdrop,\n""",
    """    this.duration,\n    this.country,\n    this.language,\n    this.originalLanguage,\n    this.audioInfo,\n    this.translation,\n    this.backdrop,\n""",
    "details constructor",
)
text = replace_once(
    text,
    """      String? pick(List<String> keys) =>\n          _firstText(info, keys) ?? _firstText(movieData, keys);\n""",
    """      String? pick(List<String> keys) =>\n          _firstText(info, keys) ?? _firstText(movieData, keys);\n      String? pickMetadata(List<String> keys) =>\n          _firstMetadataText(info, keys) ??\n          _firstMetadataText(movieData, keys);\n""",
    "metadata picker",
)
text = replace_once(
    text,
    """        rating: pick(const ['rating', 'rating_5based']) ?? summary.rating,\n        duration: pick(const ['duration', 'duration_secs']),\n        country: pick(const ['country']),\n        backdrop: backdrop,\n""",
    """        rating: pick(const ['rating', 'rating_5based']) ?? summary.rating,\n        duration: pick(const ['duration']) ??\n            _durationFromSeconds(pick(const ['duration_secs'])),\n        country: pickMetadata(const ['country']),\n        language: pickMetadata(\n          const ['language', 'spoken_languages', 'languages'],\n        ),\n        originalLanguage: pickMetadata(\n          const ['original_language', 'originalLanguage'],\n        ),\n        audioInfo: pickMetadata(\n          const ['audio_language', 'audio_languages', 'audio_info', 'audio'],\n        ),\n        translation: pickMetadata(\n          const ['translation', 'translation_type', 'audio_translation', 'dubbing'],\n        ),\n        backdrop: backdrop,\n""",
    "details metadata assignment",
)
text = replace_once(
    text,
    """  static String? _firstImage(dynamic raw) {\n""",
    """  static String? _firstMetadataText(\n    Map<String, dynamic> source,\n    List<String> keys,\n  ) {\n    for (final key in keys) {\n      final value = _metadataText(source[key]);\n      if (value != null) return value;\n    }\n    return null;\n  }\n\n  static String? _metadataText(dynamic raw) {\n    if (raw == null) return null;\n    if (raw is bool) return raw ? 'Sí' : null;\n    if (raw is List) {\n      final values = raw\n          .map(_metadataText)\n          .whereType<String>()\n          .where((value) => value.isNotEmpty)\n          .toList(growable: false);\n      return values.isEmpty ? null : values.join(', ');\n    }\n    if (raw is Map) {\n      final map = Map<String, dynamic>.from(raw);\n      for (final key in const [\n        'name',\n        'label',\n        'language',\n        'title',\n        'iso_639_1',\n      ]) {\n        final value = _metadataText(map[key]);\n        if (value != null) return value;\n      }\n      return null;\n    }\n    if (raw is String) {\n      final value = raw.trim();\n      if (value.isEmpty || value.toLowerCase() == 'null' || value == '0') {\n        return null;\n      }\n      if (value.startsWith('[') || value.startsWith('{')) {\n        try {\n          return _metadataText(jsonDecode(value));\n        } catch (_) {}\n      }\n      return value;\n    }\n    return _text(raw);\n  }\n\n  static String? _durationFromSeconds(String? raw) {\n    final seconds = int.tryParse(raw?.trim() ?? '');\n    if (seconds == null || seconds <= 0) return null;\n    final hours = seconds ~/ 3600;\n    final minutes = (seconds % 3600) ~/ 60;\n    if (hours > 0) {\n      return '${hours}h ${minutes.toString().padLeft(2, '0')} min';\n    }\n    return '${minutes.clamp(1, 59)} min';\n  }\n\n  static String? _firstImage(dynamic raw) {\n""",
    "metadata helpers",
)
service_path.write_text(text)

screen_path = Path("lib/screens/xtream_movies_screen.dart")
text = screen_path.read_text()
text = replace_once(
    text,
    """            rating: details.rating,\n            duration: details.duration,\n            channel: details.toChannel(data.connection!),\n""",
    """            rating: details.rating,\n            duration: details.duration,\n            country: details.country,\n            language: details.language,\n            originalLanguage: details.originalLanguage,\n            audioInfo: details.audioInfo,\n            translation: details.translation,\n            channel: details.toChannel(data.connection!),\n""",
    "movie detail args",
)
text = replace_once(
    text,
    """  final String? rating;\n  final String? duration;\n  final Channel channel;\n""",
    """  final String? rating;\n  final String? duration;\n  final String? country;\n  final String? language;\n  final String? originalLanguage;\n  final String? audioInfo;\n  final String? translation;\n  final Channel channel;\n""",
    "movie detail fields",
)
text = replace_once(
    text,
    """    this.rating,\n    this.duration,\n  });\n""",
    """    this.rating,\n    this.duration,\n    this.country,\n    this.language,\n    this.originalLanguage,\n    this.audioInfo,\n    this.translation,\n  });\n""",
    "movie detail constructor",
)
text = replace_once(
    text,
    """      if ((rating ?? '').trim().isNotEmpty) '★ ${rating!.trim()}',\n    ];\n    return Scaffold(\n""",
    """      if ((rating ?? '').trim().isNotEmpty) '★ ${rating!.trim()}',\n    ];\n    final languageDetails = <String>[\n      if ((language ?? '').trim().isNotEmpty) 'Idioma: ${language!.trim()}',\n      if ((originalLanguage ?? '').trim().isNotEmpty &&\n          originalLanguage!.trim().toLowerCase() !=\n              (language ?? '').trim().toLowerCase())\n        'Original: ${originalLanguage!.trim()}',\n      if ((audioInfo ?? '').trim().isNotEmpty) 'Audio: ${audioInfo!.trim()}',\n      if ((translation ?? '').trim().isNotEmpty)\n        'Traducción: ${translation!.trim()}',\n      if ((country ?? '').trim().isNotEmpty) country!.trim(),\n    ];\n    return Scaffold(\n""",
    "movie language line",
)
text = replace_once(
    text,
    """                  const SizedBox(height: 18),\n                  Text(\n                    (plot ?? '').trim().isEmpty\n""",
    """                  if (languageDetails.isNotEmpty) ...[\n                    const SizedBox(height: 8),\n                    Text(\n                      languageDetails.join('  ·  '),\n                      maxLines: 2,\n                      overflow: TextOverflow.ellipsis,\n                      style: const TextStyle(\n                        color: Colors.white46,\n                        fontSize: 13,\n                        fontWeight: FontWeight.w600,\n                      ),\n                    ),\n                  ],\n                  const SizedBox(height: 16),\n                  Text(\n                    (plot ?? '').trim().isEmpty\n""",
    "movie metadata presentation",
)
screen_path.write_text(text)
