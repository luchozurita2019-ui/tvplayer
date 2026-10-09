import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/device_performance_service.dart';
import '../services/live_epg_service.dart';
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
  final LiveProgramGuideLoader? programGuideLoader;

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
    this.programGuideLoader,
  });

  @override
  State<TvLivePremiumCatalog> createState() => _TvLivePremiumCatalogState();
}

class _TvLivePremiumCatalogState extends State<TvLivePremiumCatalog> {

  @override
  Widget build(BuildContext context) {
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
                          addAutomaticKeepAlives: false,
                          key: ValueKey<String>(
                            'premium-live:${widget.selectedCategory ?? 'all'}:${widget.query}',
                          ),
                          padding: const EdgeInsets.only(bottom: 8),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 310,
                            mainAxisExtent: 82,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: widget.channels.length,
                          itemBuilder: (context, index) {
                            final channel = widget.channels[index];
                            return _LiveChannelCard(
                              channel: channel,
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

class _LiveChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onPlay;

  const _LiveChannelCard({
    required this.channel,
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
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: ChannelLogoImage(
                    channel: widget.channel,
                    fit: BoxFit.contain,
                    cacheWidth: 112,
                    cacheHeight: 112,
                    priority: _focused ? 220 : 120,
                    prefetchExtent: 0,
                    fallback: const Icon(Icons.live_tv_rounded, size: 30),
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
                          fontSize: 14,
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
