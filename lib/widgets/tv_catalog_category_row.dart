import 'package:flutter/material.dart';

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
  static const Color _gold = Color(0xFFD7B45A);
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _focused || widget.selected;
    final borderColor = _focused
        ? _gold
        : widget.primary
            ? const Color(0x66D7B45A)
            : widget.selected
                ? const Color(0x88D7B45A)
                : Colors.transparent;

    final row = Material(
      color: highlighted ? const Color(0xFF252A2F) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(
          color: borderColor,
          width: _focused ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onTap,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _focused ? _gold : Colors.white,
                  fontSize: 14,
                  fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
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
                const Divider(height: 1, thickness: 1, color: Colors.white10),
              ],
            )
          : row,
    );
  }
}
