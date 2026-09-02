import 'dart:async';

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/device_performance_service.dart';
import '../services/live_channel_usage_service.dart';
import 'channel_logo_image.dart';
import 'tv_catalog_category_row.dart';
import 'tv_full_premium_ui.dart';

class TvLivePremiumCatalog extends StatefulWidget {
  final List<Channel> channels;
  final List<String> categories;
  final String? selectedCategory;
  final String query;
  final bool showSearchField;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Channel> onPlay;
  final bool Function(Channel channel) isFavorite;
  final ValueChanged<Channel> onFavoriteToggle;

  const TvLivePremiumCatalog({
    super.key,
    required this.channels,
    required this.categories,
    required this.selectedCategory,
    required this.query,
    required this.onCategorySelected,
    required this.onQueryChanged,
    required this.onPlay,
    required this.isFavorite,
    required this.onFavoriteToggle,
    this.showSearchField = true,
  });

  @override
  State<TvLivePremiumCatalog> createState() => _TvLivePremiumCatalogState();
}

class _TvLivePremiumCatalogState extends State<TvLivePremiumCatalog> {
  final LiveChannelUsageService _usage = LiveChannelUsageService.instance;
  Channel? _focusedChannel;

  @override
  void initState() {
    super.initState();
    unawaited(_usage.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    }));
  }

  @override
  void didUpdateWidget(covariant TvLivePremiumCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focused = _focusedChannel;
    if (focused != null &&
        !widget.channels.any((item) => item.uniqueKey == focused.uniqueKey)) {
      _focusedChannel = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final featured = widget.query.trim().isEmpty
        ? _usage.featuredChannels(
            widget.channels,
            isFavorite: widget.isFavorite,
            limit: 7,
          )
        : const <Channel>[];
    final hero = _focusedChannel ??
        (featured.isNotEmpty
            ? featured.first
            : (widget.channels.isNotEmpty ? widget.channels.first : null));

    return Row(
      children: [
        SizedBox(
          width: 210,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF00A1320), Color(0xF0050A12)],
              ),
              border: Border(
                right: BorderSide(color: Color(0x3039C5FF), width: 1),
              ),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 18),
              itemCount: widget.categories.length + 1,
              itemBuilder: (context, index) {
                final category =
                    index == 0 ? null : widget.categories[index - 1];
                return TvCatalogCategoryRow(
                  label: category ?? 'Todos',
                  selected: category == widget.selectedCategory,
                  primary: index == 0,
                  autofocus: index == 0,
                  onTap: () => widget.onCategorySelected(category),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _toolbar(),
                if (hero != null) ...[
                  const SizedBox(height: 8),
                  _hero(hero),
                ],
                if (featured.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const _SectionTitle(
                    title: 'Canales destacados',
                    subtitle: 'Partidos y deportes · favoritos y más usados',
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 68,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: featured.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final channel = featured[index];
                        return _FeaturedChannelCard(
                          channel: channel,
                          onFocus: () =>
                              setState(() => _focusedChannel = channel),
                          onPlay: () => widget.onPlay(channel),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _SectionTitle(
                  title: widget.selectedCategory ?? 'Todos los canales',
                  subtitle: '${widget.channels.length} canales disponibles',
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: widget.channels.isEmpty
                      ? const Center(
                          child: Text(
                            'No se encontraron canales.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : GridView.builder(
                          key: ValueKey<String>(
                            'premium-live:${widget.selectedCategory ?? 'all'}:${widget.query}',
                          ),
                          padding: const EdgeInsets.only(bottom: 8),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 310,
                            mainAxisExtent: 66,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: widget.channels.length,
                          itemBuilder: (context, index) {
                            final channel = widget.channels[index];
                            return _LiveChannelCard(
                              channel: channel,
                              onFocus: () =>
                                  setState(() => _focusedChannel = channel),
                              onPlay: () => widget.onPlay(channel),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolbar() {
    return Row(
      children: [
        const Icon(Icons.live_tv_rounded, size: 21, color: tvFullCyan),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            widget.selectedCategory == null
                ? 'TV EN VIVO'
                : 'TV EN VIVO  ·  ${widget.selectedCategory}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: .35,
            ),
          ),
        ),
        if (widget.showSearchField)
          SizedBox(
            width: 250,
            height: 38,
            child: TextFormField(
              initialValue: widget.query,
              decoration: InputDecoration(
                hintText: 'Buscar canal…',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: .035),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .12),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .10),
                  ),
                ),
              ),
              onChanged: widget.onQueryChanged,
            ),
          ),
      ],
    );
  }

  Widget _hero(Channel channel) {
    final group = channel.group?.trim();
    return Container(
      height: 145,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xF0121D35),
            Color(0xF0091020),
            Color(0xF0040911),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -38,
            child: IgnorePointer(
              child: Icon(
                Icons.live_tv_rounded,
                size: 210,
                color: tvFullCyan.withValues(alpha: .035),
              ),
            ),
          ),
          Positioned(
            right: 34,
            bottom: -48,
            child: IgnorePointer(
              child: Container(
                width: 210,
                height: 105,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: tvFullViolet.withValues(alpha: .12),
                      blurRadius: 46,
                      spreadRadius: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: tvFullCyan.withValues(alpha: .38),
                    ),
                  ),
                  child: ChannelLogoImage(
                    channel: channel,
                    fit: BoxFit.contain,
                    cacheWidth: 184,
                    cacheHeight: 184,
                    priority: 110,
                    prefetchExtent: 0,
                    fallback: const Icon(
                      Icons.live_tv_rounded,
                      size: 40,
                      color: Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const TvFullLiveBadge(),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        group == null || group.isEmpty
                            ? 'Señal en vivo · navegación rápida'
                            : '$group · señal en vivo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () => widget.onPlay(channel),
                            icon:
                                const Icon(Icons.play_arrow_rounded, size: 20),
                            label: const Text('Ver ahora'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              widget.onFavoriteToggle(channel);
                              setState(() {});
                            },
                            icon: Icon(
                              widget.isFavorite(channel)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 18,
                            ),
                            label: Text(
                              widget.isFavorite(channel)
                                  ? 'Favorito'
                                  : 'Agregar a favoritos',
                            ),
                          ),
                        ],
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
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 16, color: tvFullCyan),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 10.5),
          ),
        ),
      ],
    );
  }
}

class _FeaturedChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onFocus;
  final VoidCallback onPlay;

  const _FeaturedChannelCard({
    required this.channel,
    required this.onFocus,
    required this.onPlay,
  });

  @override
  State<_FeaturedChannelCard> createState() => _FeaturedChannelCardState();
}

class _FeaturedChannelCardState extends State<_FeaturedChannelCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedContainer(
      duration: Duration(milliseconds: lowRam ? 60 : 100),
      width: 205,
      decoration: tvFullGlassDecoration(
        focused: _focused,
        radius: 12,
        accent: tvFullCyan,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onFocusChange: (value) {
            if (value) widget.onFocus();
            setState(() => _focused = value);
          },
          onTap: widget.onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: ChannelLogoImage(
                    channel: widget.channel,
                    fit: BoxFit.contain,
                    cacheWidth: 84,
                    cacheHeight: 84,
                    priority: _focused ? 100 : 50,
                    prefetchExtent: 0,
                    fallback: const Icon(Icons.live_tv_rounded, size: 22),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              _focused ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Row(
                        children: [
                          Icon(Icons.circle, size: 5, color: tvFullLiveRed),
                          SizedBox(width: 4),
                          Text(
                            'EN VIVO',
                            style: TextStyle(
                              color: Color(0xFFFF8998),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
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

class _LiveChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onFocus;
  final VoidCallback onPlay;

  const _LiveChannelCard({
    required this.channel,
    required this.onFocus,
    required this.onPlay,
  });

  @override
  State<_LiveChannelCard> createState() => _LiveChannelCardState();
}

class _LiveChannelCardState extends State<_LiveChannelCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lowRam = DevicePerformanceService.instance.lowRam;
    return AnimatedContainer(
      duration: Duration(milliseconds: lowRam ? 55 : 95),
      decoration: tvFullGlassDecoration(
        focused: _focused,
        radius: 11,
        accent: tvFullCyan,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onFocusChange: (value) {
            if (value) widget.onFocus();
            setState(() => _focused = value);
          },
          onTap: widget.onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ChannelLogoImage(
                    channel: widget.channel,
                    fit: BoxFit.contain,
                    cacheWidth: 80,
                    cacheHeight: 80,
                    priority: _focused ? 100 : 25,
                    prefetchExtent: 0,
                    fallback: const Icon(Icons.live_tv_rounded, size: 21),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              _focused ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            size: 5,
                            color: tvFullLiveRed,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'VIVO',
                            style: TextStyle(
                              color: Color(0xFFFF8998),
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((widget.channel.group ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                widget.channel.group!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 8.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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
