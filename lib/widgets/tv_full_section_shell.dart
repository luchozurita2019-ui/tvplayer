import 'package:flutter/material.dart';

import 'tv_full_brand.dart';
import 'tv_full_premium_ui.dart';

enum TvFullSection { live, movies, series, sports, kids, adults }

class TvFullSectionShell extends StatelessWidget {
  final TvFullSection activeSection;
  final Widget child;
  final ValueChanged<TvFullSection>? onSectionSelected;
  final VoidCallback? onChangeList;
  final VoidCallback? onRefreshLists;
  final VoidCallback? onParentalControl;
  final Widget? trailingAction;

  const TvFullSectionShell({
    super.key,
    required this.activeSection,
    required this.child,
    this.onSectionSelected,
    this.onChangeList,
    this.onRefreshLists,
    this.onParentalControl,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    return TvFullPremiumBackground(
      compact: true,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          children: [
            _SectionTopBar(
              onChangeList: onChangeList,
              onRefreshLists: onRefreshLists,
              onParentalControl: onParentalControl,
              trailingAction: trailingAction,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionRail(
                    active: activeSection,
                    onSelected: onSectionSelected,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTopBar extends StatelessWidget {
  final VoidCallback? onChangeList;
  final VoidCallback? onRefreshLists;
  final VoidCallback? onParentalControl;
  final Widget? trailingAction;

  const _SectionTopBar({
    required this.onChangeList,
    required this.onRefreshLists,
    required this.onParentalControl,
    required this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          const TvFullBrand(iconSize: 36),
          const Spacer(),
          if (onChangeList != null)
            _UtilityAction(
              icon: Icons.swap_horiz_rounded,
              label: 'Cambio de lista',
              onPressed: onChangeList!,
            ),
          if (onRefreshLists != null) ...[
            const SizedBox(width: 7),
            _UtilityAction(
              icon: Icons.refresh_rounded,
              label: 'Actualizar lista',
              onPressed: onRefreshLists!,
            ),
          ],
          if (onParentalControl != null) ...[
            const SizedBox(width: 7),
            _UtilityAction(
              icon: Icons.shield_outlined,
              label: 'Control parental',
              onPressed: onParentalControl!,
            ),
          ],
          if (trailingAction != null) ...[
            const SizedBox(width: 7),
            trailingAction!,
          ],
          const SizedBox(width: 13),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .04),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withValues(alpha: .09)),
            ),
            child: const TvFullClock(),
          ),
        ],
      ),
    );
  }
}

class _UtilityAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _UtilityAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  State<_UtilityAction> createState() => _UtilityActionState();
}

class _UtilityActionState extends State<_UtilityAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1060;
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
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 17,
                  color: _focused ? tvFullCyan : Colors.white70,
                ),
                if (!compact) ...[
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white70,
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

class _SectionRail extends StatefulWidget {
  final TvFullSection active;
  final ValueChanged<TvFullSection>? onSelected;

  const _SectionRail({required this.active, required this.onSelected});

  @override
  State<_SectionRail> createState() => _SectionRailState();
}

class _SectionRailState extends State<_SectionRail> {
  bool _expanded = false;

  static const _entries = <(TvFullSection, String, IconData)>[
    (TvFullSection.live, 'TV en Vivo', Icons.live_tv_rounded),
    (TvFullSection.movies, 'Películas', Icons.movie_rounded),
    (TvFullSection.series, 'Series', Icons.video_library_rounded),
    (TvFullSection.sports, 'Deportes', Icons.sports_soccer_rounded),
    (TvFullSection.kids, 'Infantiles', Icons.child_care_rounded),
    (TvFullSection.adults, 'Adultos', Icons.lock_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        if (_expanded != focused) setState(() => _expanded = focused);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        width: _expanded ? 174 : 58,
        decoration: BoxDecoration(
          color: const Color(0x8A0D192A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(
            children: [
              for (final entry in _entries)
                _SectionRailItem(
                  icon: entry.$3,
                  label: entry.$2,
                  expanded: _expanded,
                  selected: entry.$1 == widget.active,
                  onPressed: entry.$1 == widget.active
                      ? () {}
                      : widget.onSelected == null
                          ? null
                          : () => widget.onSelected!(entry.$1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionRailItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback? onPressed;

  const _SectionRailItem({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.selected,
    required this.onPressed,
  });

  @override
  State<_SectionRailItem> createState() => _SectionRailItemState();
}

class _SectionRailItemState extends State<_SectionRailItem> {
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
                    ? tvFullCyan.withValues(alpha: .27)
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
