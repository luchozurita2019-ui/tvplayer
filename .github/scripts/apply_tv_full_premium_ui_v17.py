from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise RuntimeError(f"No se encontró el bloque esperado: {label}")


def replace_region(text: str, start: str, end: str, replacement: str, label: str) -> str:
    start_at = text.find(start)
    if start_at < 0:
        if replacement in text:
            return text
        raise RuntimeError(f"No se encontró inicio de región: {label}")
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise RuntimeError(f"No se encontró fin de región: {label}")
    return text[:start_at] + replacement + text[end_at:]


def insert_import(text: str, anchor: str, line: str, label: str) -> str:
    if line in text:
        return text
    return replace_once(text, anchor, anchor + line, label)


# ---------------------------------------------------------------------------
# Version 1.2.5+17
# ---------------------------------------------------------------------------
pubspec_path = ROOT / "pubspec.yaml"
pubspec = pubspec_path.read_text(encoding="utf-8")
pubspec = replace_once(pubspec, "version: 1.2.4+16", "version: 1.2.5+17", "version")
pubspec = pubspec.replace(
    "# TV FULL PRO 1.2.4+16 automatic-version-stamp marker.",
    "# TV FULL PRO 1.2.5+17 premium-neon-ui marker.",
)
pubspec_path.write_text(pubspec, encoding="utf-8")


# ---------------------------------------------------------------------------
# Home / main sections
# ---------------------------------------------------------------------------
source_path = ROOT / "lib/screens/source_content_screen.dart"
source = source_path.read_text(encoding="utf-8")
source = insert_import(
    source,
    "import '../widgets/parental_unlock_dialog.dart';\n",
    "import '../widgets/tv_full_premium_ui.dart';\n",
    "premium UI import home",
)

home_build = '''  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final active = provider.selectedPlaylist ?? widget.playlist;
    final update = _updates.availableUpdate;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TvFullPremiumBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(52, 32, 52, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TV FULL PRO',
                            style: TextStyle(
                              fontSize: 38,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.15,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: tvFullBlue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  active.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ParentalLockButton(
                      unlocked: !_parental.enabled || _parental.isUnlocked,
                      hiddenCategoryCount: 0,
                      onPressed: () => unawaited(_handleParentalLock()),
                    ),
                    const SizedBox(width: 8),
                    if (provider.hasMultiplePlaylists) ...[
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_choosePlaylist(context)),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                        label: const Text('Cambiar lista'),
                      ),
                      const SizedBox(width: 18),
                    ] else
                      const SizedBox(width: 18),
                    const TvFullClock(),
                  ],
                ),
                if (update != null) ...[
                  const SizedBox(height: 14),
                  _UpdateBanner(
                    versionName: update.versionName,
                    onUpdate: () => unawaited(_openUpdate()),
                  ),
                ],
                const Spacer(flex: 2),
                const Text(
                  '¿Qué querés ver?',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  flex: 10,
                  child: Row(
                    children: [
                      Expanded(
                        child: _SectionButton(
                          autofocus: true,
                          eyebrow: 'EN DIRECTO',
                          title: 'TV EN VIVO',
                          subtitle: 'Disfrutá de la mejor programación en vivo',
                          icon: Icons.live_tv_rounded,
                          accent: tvFullCyan,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => XtreamLiveScreen(playlist: active),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: _SectionButton(
                          eyebrow: 'CATÁLOGO',
                          title: 'PELÍCULAS',
                          subtitle: 'Miles de películas para ver cuando quieras',
                          icon: Icons.movie_outlined,
                          accent: tvFullViolet,
                          onFocused: () => _prewarmMovies(active),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => XtreamMoviesScreen(playlist: active),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: _SectionButton(
                          eyebrow: 'TEMPORADAS',
                          title: 'SERIES',
                          subtitle: 'Las mejores series en un solo lugar',
                          icon: Icons.ondemand_video_rounded,
                          accent: const Color(0xFFA04CFF),
                          onFocused: () => _prewarmSeries(active),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => XtreamSeriesScreen(playlist: active),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: tvFullViolet,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Contenido actualizado',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tu contenido listo para disfrutar',
                          style: TextStyle(color: Colors.white45, fontSize: 11.5),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const AppVersionBadge(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

'''
source = replace_region(
    source,
    "  @override\n  Widget build(BuildContext context) {",
    "  void _prewarmMovies",
    home_build,
    "home premium build",
)

section_button = '''class _SectionButton extends StatefulWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onFocused;
  final bool autofocus;

  const _SectionButton({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.onFocused,
    this.autofocus = false,
  });

  @override
  State<_SectionButton> createState() => _SectionButtonState();
}

class _SectionButtonState extends State<_SectionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    final scale = _focused ? (lowRam ? 1.035 : 1.065) : 1.0;
    return AnimatedScale(
      scale: scale,
      duration: Duration(milliseconds: lowRam ? 90 : 150),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Duration(milliseconds: lowRam ? 90 : 150),
        curve: Curves.easeOutCubic,
        decoration: tvFullGlassDecoration(
          focused: _focused,
          radius: 22,
          accent: widget.accent,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(22),
            onFocusChange: (value) {
              if (_focused != value) setState(() => _focused = value);
              if (value) widget.onFocused?.call();
            },
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.accent.withValues(alpha: _focused ? .28 : .16),
                          tvFullViolet.withValues(alpha: _focused ? .20 : .09),
                        ],
                      ),
                      border: Border.all(
                        color: widget.accent.withValues(alpha: _focused ? .75 : .28),
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 37,
                      color: _focused ? widget.accent : Colors.white70,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.eyebrow,
                    style: TextStyle(
                      color: _focused ? widget.accent : Colors.white45,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 25,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    widget.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
'''
source = replace_region(
    source,
    "class _SectionButton extends StatefulWidget {",
    "\u0000",
    section_button,
    "section button",
) if "\u0000" in source else source[:source.find("class _SectionButton extends StatefulWidget {")] + section_button
source_path.write_text(source, encoding="utf-8")


# ---------------------------------------------------------------------------
# Startup / blocked screen
# ---------------------------------------------------------------------------
home_path = ROOT / "lib/screens/home_screen.dart"
home = home_path.read_text(encoding="utf-8")
home = insert_import(
    home,
    "import '../widgets/app_version_badge.dart';\n",
    "import '../widgets/tv_full_premium_ui.dart';\n",
    "premium UI import startup",
)
startup_class = '''class _StartupView extends StatelessWidget {
  final String message;
  final String? deviceCode;
  final bool busy;
  final bool blocked;

  const _StartupView({
    required this.message,
    this.deviceCode,
    this.busy = true,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TvFullPremiumBackground(
        child: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 650),
              margin: const EdgeInsets.all(34),
              padding: const EdgeInsets.fromLTRB(46, 38, 46, 32),
              decoration: tvFullGlassDecoration(
                focused: false,
                radius: 24,
                accent: blocked ? const Color(0xFFFF6B78) : tvFullCyan,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (blocked ? const Color(0xFFFF6B78) : tvFullBlue)
                          .withValues(alpha: .12),
                      border: Border.all(
                        color: (blocked ? const Color(0xFFFF6B78) : tvFullCyan)
                            .withValues(alpha: .46),
                      ),
                    ),
                    child: Icon(
                      blocked ? Icons.lock_outline_rounded : Icons.live_tv_rounded,
                      size: blocked ? 38 : 36,
                      color: blocked ? const Color(0xFFFF8B94) : tvFullCyan,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'TV FULL PRO',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  if (blocked) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'El contenido guardado se conserva y se habilitará de nuevo al reactivar el servicio.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                  if (deviceCode != null && deviceCode!.trim().isNotEmpty) ...[
                    const SizedBox(height: 26),
                    const Text(
                      'CÓDIGO DE DISPOSITIVO',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      deviceCode!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: tvFullCyan,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  if (busy) ...[
                    const SizedBox(height: 28),
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: tvFullCyan,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const AppVersionBadge(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
'''
home = home[:home.find("class _StartupView extends StatelessWidget {")] + startup_class
home_path.write_text(home, encoding="utf-8")


# ---------------------------------------------------------------------------
# Category row shared across LIVE / Movies / Series
# ---------------------------------------------------------------------------
category_path = ROOT / "lib/widgets/tv_catalog_category_row.dart"
category_path.write_text('''import 'package:flutter/material.dart';

import 'tv_full_premium_ui.dart';

class TvCatalogCategoryRow extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final bool primary;
  final VoidCallback onTap;

  const TvCatalogCategoryRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
    this.primary = false,
  });

  @override
  State<TvCatalogCategoryRow> createState() => _TvCatalogCategoryRowState();
}

class _TvCatalogCategoryRowState extends State<TvCatalogCategoryRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _focused || widget.selected;
    final scale = _focused ? 1.035 : 1.0;
    final row = AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: highlighted
              ? LinearGradient(
                  colors: [
                    tvFullBlue.withValues(alpha: _focused ? .20 : .11),
                    tvFullViolet.withValues(alpha: _focused ? .13 : .07),
                    const Color(0xB80B1422),
                  ],
                )
              : null,
          border: Border.all(
            color: _focused
                ? tvFullCyan
                : widget.selected
                    ? tvFullBlue.withValues(alpha: .58)
                    : Colors.transparent,
            width: _focused ? 1.8 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: tvFullCyan.withValues(alpha: .16),
                    blurRadius: 13,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _focused ? Colors.white : Colors.white.withValues(alpha: .86),
                      fontSize: 14,
                      fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: widget.primary ? 10 : 2),
      child: widget.primary
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row,
                const SizedBox(height: 7),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: tvFullBlue.withValues(alpha: .16),
                ),
              ],
            )
          : row,
    );
  }
}
''', encoding="utf-8")


# ---------------------------------------------------------------------------
# Helpers for catalogue screens
# ---------------------------------------------------------------------------
def premium_catalog_shell(text: str, data_type: str, return_line: str, label: str) -> str:
    text = replace_once(
        text,
        "        backgroundColor: const Color(0xFF05090F),\n        appBar: AppBar(\n",
        "        backgroundColor: Colors.transparent,\n        appBar: AppBar(\n          backgroundColor: const Color(0xA3050910),\n          surfaceTintColor: Colors.transparent,\n",
        f"{label} transparent appbar",
    )
    text = replace_once(
        text,
        f"        body: FutureBuilder<{data_type}>(\n",
        f"        body: TvFullPremiumBackground(\n          compact: true,\n          child: FutureBuilder<{data_type}>(\n",
        f"{label} background open",
    )
    text = replace_once(
        text,
        return_line + "\n          },\n        ),\n      ),",
        return_line + "\n          },\n          ),\n        ),\n      ),",
        f"{label} background close",
    )
    return text


def premium_sidebar(text: str, width_marker: str, label: str) -> str:
    old = "          child: ColoredBox(\n            color: const Color(0xFF08111B),\n            child: ListView.builder("
    new = "          child: DecoratedBox(\n            decoration: BoxDecoration(\n              gradient: const LinearGradient(\n                begin: Alignment.topCenter,\n                end: Alignment.bottomCenter,\n                colors: [Color(0xD9101928), Color(0xCC07101D)],\n              ),\n              border: Border(\n                right: BorderSide(color: tvFullBlue, width: .35),\n              ),\n            ),\n            child: ListView.builder("
    return replace_once(text, old, new, f"{label} premium sidebar")


# ---------------------------------------------------------------------------
# LIVE
# ---------------------------------------------------------------------------
live_path = ROOT / "lib/screens/xtream_live_screen.dart"
live = live_path.read_text(encoding="utf-8")
live = insert_import(
    live,
    "import '../widgets/tv_catalog_category_row.dart';\n",
    "import '../widgets/tv_full_premium_ui.dart';\n",
    "premium UI import live",
)
live = premium_catalog_shell(
    live,
    "_LiveData",
    "            return _buildCatalog(data);",
    "live",
)
live = premium_sidebar(live, "width: 220", "live")

live_row = '''class _ChannelRowState extends State<_ChannelRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
      child: AnimatedScale(
        scale: _focused ? (lowRam ? 1.012 : 1.025) : 1,
        duration: Duration(milliseconds: lowRam ? 70 : 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: Duration(milliseconds: lowRam ? 70 : 120),
          decoration: tvFullGlassDecoration(
            focused: _focused,
            radius: 12,
            accent: tvFullCyan,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              autofocus: widget.autofocus,
              borderRadius: BorderRadius.circular(12),
              onFocusChange: (value) => setState(() => _focused = value),
              onTap: widget.onTap,
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: CachedArtworkImage(
                          url: widget.channel.logoUrl,
                          fit: BoxFit.contain,
                          cacheWidth: 84,
                          cacheHeight: 84,
                          priority: _focused ? 100 : 20,
                          prefetchExtent: 0,
                          fallback: Container(
                            alignment: Alignment.center,
                            color: Colors.white.withValues(alpha: .04),
                            child: Text(
                              _initials(widget.channel.name),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: _focused ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                    ),
                    if ((widget.channel.group ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          widget.channel.group!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _focused ? tvFullCyan.withValues(alpha: .75) : Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\\s+'))
        .where((e) => e.isNotEmpty)
        .take(2);
    final text = words.map((e) => e.substring(0, 1).toUpperCase()).join();
    return text.isEmpty ? 'TV' : text;
  }
}

'''
live = replace_region(
    live,
    "class _ChannelRowState extends State<_ChannelRow> {",
    "class _LiveData {",
    live_row,
    "live focused channel row",
)

blocked = '''class _BlockedCatalog extends StatelessWidget {
  final String message;
  const _BlockedCatalog({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TvFullPremiumBackground(
        compact: true,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 540),
            padding: const EdgeInsets.all(32),
            decoration: tvFullGlassDecoration(radius: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 46, color: tvFullCyan),
                const SizedBox(height: 14),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
'''
live = live[:live.find("class _BlockedCatalog extends StatelessWidget {")] + blocked
live_path.write_text(live, encoding="utf-8")


# ---------------------------------------------------------------------------
# Movies
# ---------------------------------------------------------------------------
movies_path = ROOT / "lib/screens/xtream_movies_screen.dart"
movies = movies_path.read_text(encoding="utf-8")
movies = insert_import(
    movies,
    "import '../widgets/tv_catalog_category_row.dart';\n",
    "import '../widgets/tv_full_premium_ui.dart';\n",
    "premium UI import movies",
)
movies = premium_catalog_shell(
    movies,
    "_MovieData",
    "            return _catalog(data);",
    "movies",
)
movies = premium_sidebar(movies, "width: 250", "movies")

movie_detail_start = movies.find("class _MovieDetailScreen extends StatelessWidget {")
movie_card_start = movies.find("class _MovieCard extends StatefulWidget {")
if movie_detail_start < 0 or movie_card_start < 0:
    raise RuntimeError("No se encontró MovieDetail/MovieCard")
movie_detail = movies[movie_detail_start:movie_card_start]
movie_detail = replace_once(
    movie_detail,
    "    return Scaffold(\n      backgroundColor: const Color(0xFF05090F),\n      appBar: AppBar(title: const Text('Película')),\n      body: Padding(\n",
    "    return Scaffold(\n      backgroundColor: Colors.transparent,\n      appBar: AppBar(\n        backgroundColor: const Color(0xA3050910),\n        surfaceTintColor: Colors.transparent,\n        title: const Text('Película'),\n      ),\n      body: TvFullPremiumBackground(\n        compact: true,\n        child: Padding(\n",
    "movie detail premium open",
)
# close the body wrapper using the final build closing sequence in this class
needle = "        ),\n      ),\n    );\n  }\n\n  void _play"
pos = movie_detail.rfind(needle)
if pos < 0:
    raise RuntimeError("No se encontró cierre MovieDetail")
movie_detail = movie_detail[:pos] + "        ),\n      ),\n    );\n  }\n\n  void _play" + movie_detail[pos + len(needle):]
movies = movies[:movie_detail_start] + movie_detail + movies[movie_card_start:]

movie_card = '''class _MovieCardState extends State<_MovieCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedScale(
      scale: _focused ? (lowRam ? 1.025 : 1.055) : 1,
      duration: Duration(milliseconds: lowRam ? 80 : 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Duration(milliseconds: lowRam ? 80 : 140),
        decoration: tvFullGlassDecoration(
          focused: _focused,
          radius: 15,
          accent: tvFullViolet,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(15),
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CachedArtworkImage(
                    url: widget.item.cover,
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    cacheHeight: 480,
                    priority: _focused ? 100 : 10,
                    prefetchExtent: 0,
                    fallback: const ColoredBox(
                      color: Color(0xFF111E29),
                      child: Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: Colors.white30,
                          size: 42,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.12,
                          fontWeight: _focused ? FontWeight.w900 : FontWeight.w800,
                        ),
                      ),
                      if ((widget.item.category ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          widget.item.category!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _focused ? tvFullCyan.withValues(alpha: .72) : Colors.white38,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

'''
movies = replace_region(
    movies,
    "class _MovieCardState extends State<_MovieCard> {",
    "class _MovieData {",
    movie_card,
    "premium movie card",
)
movies_path.write_text(movies, encoding="utf-8")


# ---------------------------------------------------------------------------
# Series
# ---------------------------------------------------------------------------
series_path = ROOT / "lib/screens/xtream_series_screen.dart"
series = series_path.read_text(encoding="utf-8")
series = insert_import(
    series,
    "import '../widgets/tv_catalog_category_row.dart';\n",
    "import '../widgets/tv_full_premium_ui.dart';\n",
    "premium UI import series",
)
series = premium_catalog_shell(
    series,
    "_SeriesData",
    "            return _catalog(data);",
    "series",
)
series = premium_sidebar(series, "width: 250", "series")

# Series detail: background while keeping the episode/season logic intact.
detail_state_start = series.find("class _SeriesDetailScreenState extends State<_SeriesDetailScreen> {")
series_card_start = series.find("class _SeriesCard extends StatefulWidget {")
if detail_state_start < 0 or series_card_start < 0:
    raise RuntimeError("No se encontró SeriesDetail/SeriesCard")
detail_region = series[detail_state_start:series_card_start]
detail_region = replace_once(
    detail_region,
    "    return Scaffold(\n      backgroundColor: const Color(0xFF05090F),\n      appBar: AppBar(title: const Text('Serie')),\n      body: Padding(\n",
    "    return Scaffold(\n      backgroundColor: Colors.transparent,\n      appBar: AppBar(\n        backgroundColor: const Color(0xA3050910),\n        surfaceTintColor: Colors.transparent,\n        title: const Text('Serie'),\n      ),\n      body: TvFullPremiumBackground(\n        compact: true,\n        child: Padding(\n",
    "series detail premium open",
)
needle = "        ),\n      ),\n    );\n  }\n\n  void _play"
pos = detail_region.rfind(needle)
if pos < 0:
    raise RuntimeError("No se encontró cierre SeriesDetail")
detail_region = detail_region[:pos] + "        ),\n      ),\n    );\n  }\n\n  void _play" + detail_region[pos + len(needle):]
series = series[:detail_state_start] + detail_region + series[series_card_start:]

series_card = '''class _SeriesCardState extends State<_SeriesCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedScale(
      scale: _focused ? (lowRam ? 1.025 : 1.055) : 1,
      duration: Duration(milliseconds: lowRam ? 80 : 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Duration(milliseconds: lowRam ? 80 : 140),
        decoration: tvFullGlassDecoration(
          focused: _focused,
          radius: 15,
          accent: const Color(0xFFA04CFF),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(15),
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CachedArtworkImage(
                    url: widget.item.cover,
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    cacheHeight: 480,
                    priority: _focused ? 100 : 10,
                    prefetchExtent: 0,
                    fallback: const ColoredBox(
                      color: Color(0xFF111E29),
                      child: Center(
                        child: Icon(
                          Icons.video_library_outlined,
                          size: 42,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Text(
                    widget.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: _focused ? FontWeight.w900 : FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

'''
series = replace_region(
    series,
    "class _SeriesCardState extends State<_SeriesCard> {",
    "class _SeriesData {",
    series_card,
    "premium series card",
)
series_path.write_text(series, encoding="utf-8")


# Guardrails: playback engine must remain untouched by this UI update.
main_activity = (ROOT / "android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt").read_text(encoding="utf-8")
for marker in (
    "LIVE_STARTUP_DEADLINE_MS = 4500L",
    "MAX_LIVE_ENDED_RECOVERIES = 1",
    '"setAudioTrack"',
    '"setSubtitleTrack"',
    "WIFI_MODE_FULL_HIGH_PERF",
):
    if marker not in main_activity:
        raise RuntimeError(f"Se perdió una optimización de reproducción: {marker}")

print("TV FULL PRO 1.2.5+17 premium UI aplicado")
