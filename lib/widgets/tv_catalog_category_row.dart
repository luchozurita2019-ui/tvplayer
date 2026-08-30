import 'package:flutter/material.dart';

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
                      color: _focused
                          ? Colors.white
                          : Colors.white.withValues(alpha: .86),
                      fontSize: 14,
                      fontWeight:
                          highlighted ? FontWeight.w800 : FontWeight.w600,
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
