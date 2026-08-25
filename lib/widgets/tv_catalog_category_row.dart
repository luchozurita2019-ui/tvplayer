import 'package:flutter/material.dart';

/// Category row tuned for Android TV remote navigation.
///
/// The focused row is always visible, while the selected row remains marked
/// after focus moves away. This mirrors the LIVE catalog behavior without
/// coupling catalog state to focus state.
class TvCatalogCategoryRow extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const TvCatalogCategoryRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<TvCatalogCategoryRow> createState() => _TvCatalogCategoryRowState();
}

class _TvCatalogCategoryRowState extends State<TvCatalogCategoryRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _focused || widget.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: highlighted ? const Color(0xFF12324A) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(9),
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _focused ? const Color(0xFF58B9FF) : Colors.transparent,
              ),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
