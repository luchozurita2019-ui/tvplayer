from pathlib import Path


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'{label}: expected text not found in {path}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')

# Make PlayerScreen itself own the playback network guard so every entry path
# (catalog, favorites, future deep links) pauses artwork downloads.
replace_once(
    'lib/screens/player_screen.dart',
    "import '../models/playback_settings.dart';\nimport '../services/playback_metrics_service.dart';",
    "import '../models/playback_settings.dart';\nimport '../services/artwork_cache_service.dart';\nimport '../services/playback_metrics_service.dart';",
    'player artwork service import',
)
replace_once(
    'lib/screens/player_screen.dart',
    "  void initState() {\n    super.initState();\n    _currentIndex = widget.initialIndex;",
    "  void initState() {\n    super.initState();\n    ArtworkCacheService.instance.pauseForPlayback();\n    _currentIndex = widget.initialIndex;",
    'player pause artwork',
)
replace_once(
    'lib/screens/player_screen.dart',
    "    unawaited(_player.dispose());\n    super.dispose();",
    "    unawaited(_player.dispose());\n    ArtworkCacheService.instance.resumeBrowsing();\n    super.dispose();",
    'player resume artwork',
)

# Favorites also uses the controlled disk-backed artwork cache instead of raw
# Image.network, so scrolling favorites obeys the same 3-request ceiling.
replace_once(
    'lib/screens/home_screen.dart',
    "import '../services/artwork_cache_service.dart';\nimport 'add_source_screen.dart';",
    "import '../services/artwork_cache_service.dart';\nimport '../widgets/cached_artwork_image.dart';\nimport 'add_source_screen.dart';",
    'home cached artwork import',
)
old = """    return CircleAvatar(
      backgroundColor: Colors.transparent,
      child: ClipOval(
        child: Image.network(
          logo,
          width: 40,
          height: 40,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.tv),
        ),
      ),
    );
"""
new = """    return CircleAvatar(
      backgroundColor: Colors.transparent,
      child: ClipOval(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CachedArtworkImage(
            url: logo,
            fit: BoxFit.contain,
            cacheWidth: 80,
            fallback: const Icon(Icons.tv),
          ),
        ),
      ),
    );
"""
replace_once('lib/screens/home_screen.dart', old, new, 'favorites cached artwork')

print('Artwork playback path guards applied')
