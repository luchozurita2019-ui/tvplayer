import 'package:flutter/material.dart';

import 'tv_full_brand.dart';
import 'tv_full_premium_ui.dart';

/// Pantalla principal de TV en vivo.
///
/// Es solamente presentación: reutiliza la textura Media3 y la lista real de
/// canales entregadas por el reproductor. No toca buffers, red ni decodificación.
class TvLiveTheater extends StatelessWidget {
  final Widget video;
  final Widget channels;
  final String channelName;
  final String? channelGroup;
  final VoidCallback onFullscreen;
  final VoidCallback onCategories;
  final VoidCallback onHome;
  final VoidCallback? onAudio;
  final VoidCallback? onChangeList;
  final VoidCallback? onRefreshLists;
  final VoidCallback? onParentalControl;
  final ValueChanged<String>? onSectionRequested;

  const TvLiveTheater({
    super.key,
    required this.video,
    required this.channels,
    required this.channelName,
    required this.onFullscreen,
    required this.onCategories,
    required this.onHome,
    this.channelGroup,
    this.onAudio,
    this.onChangeList,
    this.onRefreshLists,
    this.onParentalControl,
    this.onSectionRequested,
  });

  @override
  Widget build(BuildContext context) {
    return TvFullPremiumBackground(
      compact: true,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1080;
            final channelsWidth = compact ? 236.0 : 292.0;
            return Column(
              children: [
                _TopBar(
                  compact: compact,
                  onChangeList: onChangeList,
                  onRefreshLists: onRefreshLists,
                  onParentalControl: onParentalControl,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AutoNavigationRail(
                        compact: compact,
                        onSectionRequested: onSectionRequested,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _VideoColumn(
                          video: video,
                          channelName: channelName,
                          channelGroup: channelGroup,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: channelsWidth,
                        child: _ChannelPanel(channels: channels),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool compact;
  final VoidCallback? onChangeList;
  final VoidCallback? onRefreshLists;
  final VoidCallback? onParentalControl;

  const _TopBar({
    required this.compact,
    required this.onChangeList,
    required this.onRefreshLists,
    required this.onParentalControl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 50 : 56,
      child: Row(
        children: [
          TvFullBrand(iconSize: compact ? 35 : 40),
          const Spacer(),
          if (onChangeList != null)
            _TopAction(
              icon: Icons.swap_horiz_rounded,
              label: 'Cambio de lista',
              onPressed: onChangeList!,
              compact: compact,
            ),
          if (onRefreshLists != null) ...[
            const SizedBox(width: 7),
            _TopAction(
              icon: Icons.refresh_rounded,
              label: 'Actualizar lista',
              onPressed: onRefreshLists!,
              compact: compact,
            ),
          ],
          if (onParentalControl != null) ...[
            const SizedBox(width: 7),
            _TopAction(
              icon: Icons.shield_outlined,
              label: 'Control parental',
              onPressed: onParentalControl!,
              compact: compact,
            ),
          ],
          const SizedBox(width: 14),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
            ),
            child: const TvFullClock(),
          ),
        ],
      ),
    );
  }
}

class _TopAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool compact;

  const _TopAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.compact,
  });

  @override
  State<_TopAction> createState() => _TopActionState();
}

class _TopActionState extends State<_TopAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      height: 36,
      decoration: BoxDecoration(
        color: _focused
            ? tvFullBlue.withValues(alpha: .23)
            : Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: _focused ? tvFullCyan : Colors.white.withValues(alpha: .09),
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: tvFullCyan.withValues(alpha: .16),
                  blurRadius: 15,
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 9 : 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 17,
                  color: _focused ? tvFullCyan : Colors.white70,
                ),
                if (!widget.compact) ...[
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: _focused ? Colors.white : Colors.white70,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoNavigationRail extends StatefulWidget {
  final bool compact;
  final ValueChanged<String>? onSectionRequested;

  const _AutoNavigationRail({
    required this.compact,
    required this.onSectionRequested,
  });

  @override
  State<_AutoNavigationRail> createState() => _AutoNavigationRailState();
}

class _AutoNavigationRailState extends State<_AutoNavigationRail> {
  bool _expanded = false;

  static const _items = <(String, String, IconData)>[
    ('live', 'TV en Vivo', Icons.live_tv_rounded),
    ('movies', 'Películas', Icons.movie_rounded),
    ('series', 'Series', Icons.video_library_rounded),
    ('sports', 'Deportes', Icons.sports_soccer_rounded),
    ('kids', 'Infantiles', Icons.child_care_rounded),
    ('adults', 'Adultos', Icons.lock_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final width = _expanded ? (widget.compact ? 156.0 : 178.0) : 58.0;
    return Focus(
      onFocusChange: (value) {
        if (_expanded != value) setState(() => _expanded = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        width: width,
        decoration: BoxDecoration(
          color: const Color(0x8A0D192A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(
            children: [
              for (final item in _items)
                _RailItem(
                  icon: item.$3,
                  label: item.$2,
                  expanded: _expanded,
                  selected: item.$1 == 'live',
                  onPressed: item.$1 == 'live'
                      ? () {}
                      : widget.onSectionRequested == null
                          ? null
                          : () => widget.onSectionRequested!(item.$1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback? onPressed;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.selected,
    required this.onPressed,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 46,
        decoration: BoxDecoration(
          color: _focused
              ? tvFullBlue.withValues(alpha: .24)
              : widget.selected
                  ? tvFullCyan.withValues(alpha: .10)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused
                ? tvFullCyan
                : widget.selected
                    ? tvFullCyan.withValues(alpha: .28)
                    : Colors.transparent,
            width: _focused ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            canRequestFocus: widget.onPressed != null || widget.selected,
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: widget.expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    size: 21,
                    color: active ? tvFullCyan : Colors.white54,
                  ),
                  if (widget.expanded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white60,
                          fontSize: 12,
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoColumn extends StatelessWidget {
  final Widget video;
  final String channelName;
  final String? channelGroup;

  const _VideoColumn({
    required this.video,
    required this.channelName,
    required this.channelGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: tvFullCyan.withValues(alpha: .28),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: tvFullCyan.withValues(alpha: .08),
                  blurRadius: 22,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: ColoredBox(color: Colors.black, child: video),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: const Color(0x90101C2D),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .09)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tvFullCyan.withValues(alpha: .12),
                  border: Border.all(color: tvFullCyan.withValues(alpha: .28)),
                ),
                child: const Icon(
                  Icons.live_tv_rounded,
                  size: 18,
                  color: tvFullCyan,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((channelGroup ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        channelGroup!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: tvFullMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const TvFullLiveBadge(compact: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelPanel extends StatelessWidget {
  final Widget channels;

  const _ChannelPanel({required this.channels});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x8A0D192A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(15, 14, 15, 10),
            child: Text(
              'Canales en Vivo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: .07)),
          Expanded(child: channels),
        ],
      ),
    );
  }
}
