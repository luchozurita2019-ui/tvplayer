import 'package:flutter/material.dart';

import 'cached_artwork_image.dart';
import 'tv_full_premium_ui.dart';

enum CinematicSection { featured, live, movies, series }

class CinematicTile {
  final String id;
  final String title;
  final String? imageUrl;
  final String? category;
  final CinematicSection section;

  const CinematicTile({
    required this.id,
    required this.title,
    required this.section,
    this.imageUrl,
    this.category,
  });
}

/// Presentation only: source loading, access checks and playback remain owned
/// by the existing screens. No automatic carousel, video preview or polling.
class TvCinematicHome extends StatefulWidget {
  final String playlistName;
  final List<CinematicTile> items;
  final List<Widget> actions;
  final Widget? notice;
  final Widget footer;
  final ValueChanged<CinematicSection> onOpenSection;
  final ValueChanged<CinematicTile> onOpenItem;

  const TvCinematicHome({
    super.key,
    required this.playlistName,
    required this.items,
    required this.actions,
    required this.footer,
    required this.onOpenSection,
    required this.onOpenItem,
    this.notice,
  });

  @override
  State<TvCinematicHome> createState() => _TvCinematicHomeState();
}

class _TvCinematicHomeState extends State<TvCinematicHome> {
  CinematicSection _selected = CinematicSection.featured;
  final ScrollController _scroll = ScrollController();
  static const _accent = tvFullCyan;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TvCinematicHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistName != widget.playlistName) {
      _selected = CinematicSection.featured;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return ColoredBox(
          color: const Color(0xFF08090B),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 16, 24, 12),
                child: Row(
                  children: [
                    const Text(
                      'TV FULL',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'PRO',
                      style: TextStyle(
                        color: tvFullViolet,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    ...widget.actions,
                  ],
                ),
              ),
              if (widget.notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: widget.notice!,
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: compact ? 70 : 184,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 28, 10, 16),
                        children: [
                          _nav(
                            CinematicSection.featured,
                            Icons.dashboard_rounded,
                            'Destacados',
                            compact,
                          ),
                          _nav(
                            CinematicSection.live,
                            Icons.live_tv_rounded,
                            'TV en vivo',
                            compact,
                          ),
                          _nav(
                            CinematicSection.movies,
                            Icons.movie_outlined,
                            'Películas',
                            compact,
                          ),
                          _nav(
                            CinematicSection.series,
                            Icons.video_library_outlined,
                            'Series',
                            compact,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: CustomScrollView(
                        controller: _scroll,
                        key: const PageStorageKey('cinematic-home'),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              12,
                              24,
                              compact ? 16 : 30,
                              16,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _label(_selected),
                                          style: const TextStyle(
                                            fontSize: 25,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          widget.playlistName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_selected != CinematicSection.featured)
                                    TextButton(
                                      onPressed: () =>
                                          widget.onOpenSection(_selected),
                                      child: const Text('Ver todo'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          ..._content(compact),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 24, 30, 20),
                            sliver: SliverToBoxAdapter(child: widget.footer),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _nav(
    CinematicSection section,
    IconData icon,
    String label,
    bool compact,
  ) {
    final selected = section == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _FocusSurface(
        autofocus: section == CinematicSection.featured,
        selected: selected,
        label: label,
        onTap: () {
          if (section == CinematicSection.live) {
            widget.onOpenSection(section);
            return;
          }
          setState(() => _selected = section);
          if (_scroll.hasClients) _scroll.jumpTo(0);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 17),
          child: Row(
            children: [
              Icon(icon, size: 23, color: selected ? _accent : Colors.white60),
              if (!compact) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: selected ? Colors.white : Colors.white60,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(bool compact) {
    final items = widget.items
        .where(
          (item) =>
              _selected == CinematicSection.featured ||
              item.section == _selected,
        )
        .toList();
    final lead = items.take(2).toList();
    final rest = items.skip(2).take(10).toList();
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(12, 0, compact ? 16 : 30, 0),
        sliver: SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, size) {
              final cards = lead.isEmpty
                  ? [
                      _sectionCard(
                        _selected == CinematicSection.series
                            ? CinematicSection.series
                            : CinematicSection.movies,
                      ),
                      _sectionCard(
                        _selected == CinematicSection.movies
                            ? CinematicSection.movies
                            : CinematicSection.series,
                      ),
                    ]
                  : lead.map((item) => _poster(item, hero: true)).toList();
              if (size.maxWidth < 500) {
                return Column(
                  children: [
                    for (final card in cards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AspectRatio(aspectRatio: 16 / 10, child: card),
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: AspectRatio(aspectRatio: 16 / 10, child: cards[i]),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
      if (items.isEmpty)
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 18, 30, 4),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Abrí un catálogo para ver sus portadas también en el inicio.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        ),
      if (rest.isNotEmpty) ...[
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 25, 30, 14),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Más para descubrir',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 0, compact ? 16 : 30, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              childAspectRatio: 16 / 11,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _poster(rest[index]),
              childCount: rest.length,
            ),
          ),
        ),
      ],
    ];
  }

  Widget _sectionCard(CinematicSection section) => _FocusSurface(
        label: 'Abrir ${_label(section)}',
        onTap: () => widget.onOpenSection(section),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF202A43), Color(0xFF101318)],
            ),
          ),
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                section == CinematicSection.movies
                    ? Icons.movie_outlined
                    : Icons.video_library_outlined,
                size: 38,
                color: _accent,
              ),
              const SizedBox(height: 14),
              Text(
                _label(section),
                style:
                    const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'Explorar catálogo  →',
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
            ],
          ),
        ),
      );

  Widget _poster(CinematicTile item, {bool hero = false}) => _FocusSurface(
        key: ValueKey(item.id),
        label: item.title,
        onTap: () => widget.onOpenItem(item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedArtworkImage(
              url: item.imageUrl,
              fit: BoxFit.cover,
              cacheWidth: hero ? 780 : 380,
              priority: hero ? 60 : 20,
              prefetchExtent: 0,
              fallback: const ColoredBox(
                color: Color(0xFF171C29),
                child: Center(
                  child: Icon(
                    Icons.movie_outlined,
                    color: Colors.white24,
                    size: 44,
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 1],
                  colors: [Colors.transparent, Color(0xF208090B)],
                ),
              ),
            ),
            Positioned(
              left: hero ? 24 : 16,
              right: 16,
              bottom: hero ? 24 : 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label(item.section).toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFB6C4FF),
                      fontSize: 10,
                      letterSpacing: 1.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: hero ? 27 : 17,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  String _label(CinematicSection section) => switch (section) {
        CinematicSection.featured => 'Destacados',
        CinematicSection.live => 'TV en vivo',
        CinematicSection.movies => 'Películas',
        CinematicSection.series => 'Series',
      };
}

class _FocusSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;
  final bool selected;
  final String label;
  const _FocusSurface({
    super.key,
    required this.child,
    required this.onTap,
    required this.label,
    this.autofocus = false,
    this.selected = false,
  });
  @override
  State<_FocusSurface> createState() => _FocusSurfaceState();
}

class _FocusSurfaceState extends State<_FocusSurface> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.label,
        button: true,
        selected: widget.selected,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 110),
          decoration: BoxDecoration(
            color:
                widget.selected ? const Color(0xFF151B2A) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              width: 2,
              color: _focused ? tvFullCyan : Colors.transparent,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              autofocus: widget.autofocus,
              onTap: widget.onTap,
              onFocusChange: (value) => setState(() => _focused = value),
              child: widget.child,
            ),
          ),
        ),
      );
}
