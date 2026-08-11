from pathlib import Path

path = Path('lib/screens/xtream_series_screen.dart')
text = path.read_text()

text = text.replace(
    "import 'package:provider/provider.dart';\n",
    "import 'package:provider/provider.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
    1,
)

old = '''class _XtreamSeriesScreenState extends State<XtreamSeriesScreen> {\n  late Future<_SeriesCatalogData> _future;\n  String _query = '';\n  String? _category;\n\n  @override\n  void initState() {\n    super.initState();\n    _future = _load();\n  }\n'''
new = '''class _XtreamSeriesScreenState extends State<XtreamSeriesScreen> {\n  late Future<_SeriesCatalogData> _future;\n  String _query = '';\n  String? _category;\n  double _sidebarWidth = 320;\n  bool _sidebarCollapsed = false;\n\n  static const double _sidebarMinWidth = 230;\n  static const double _sidebarMaxWidth = 480;\n  // Compartimos las mismas preferencias del catálogo general para que TV,\n  // Películas y Series mantengan exactamente el mismo ancho/estado.\n  static const String _sidebarWidthKey = 'catalog_sidebar_width_v1';\n  static const String _sidebarCollapsedKey = 'catalog_sidebar_collapsed_v1';\n\n  @override\n  void initState() {\n    super.initState();\n    _future = _load();\n    _loadSidebarPreferences();\n  }\n\n  Future<void> _loadSidebarPreferences() async {\n    final prefs = await SharedPreferences.getInstance();\n    if (!mounted) return;\n    final width = prefs.getDouble(_sidebarWidthKey) ?? 320;\n    setState(() {\n      _sidebarWidth = width.clamp(_sidebarMinWidth, _sidebarMaxWidth).toDouble();\n      _sidebarCollapsed = prefs.getBool(_sidebarCollapsedKey) ?? false;\n    });\n  }\n\n  Future<void> _persistSidebar() async {\n    final prefs = await SharedPreferences.getInstance();\n    await prefs.setDouble(_sidebarWidthKey, _sidebarWidth);\n    await prefs.setBool(_sidebarCollapsedKey, _sidebarCollapsed);\n  }\n\n  void _resizeSidebar(double delta) {\n    if (_sidebarCollapsed) return;\n    setState(() {\n      _sidebarWidth = (_sidebarWidth + delta)\n          .clamp(_sidebarMinWidth, _sidebarMaxWidth)\n          .toDouble();\n    });\n  }\n\n  void _toggleSidebar() {\n    setState(() => _sidebarCollapsed = !_sidebarCollapsed);\n    _persistSidebar();\n  }\n'''
if old not in text:
    raise SystemExit('state block not found')
text = text.replace(old, new, 1)

start = text.index('  Widget _buildCatalog(BuildContext context, _SeriesCatalogData data) {')
end = text.index('\n}\n\nclass XtreamSeriesDetailScreen', start)
old_block = text[start:end]
new_block = r'''  Widget _buildCatalog(BuildContext context, _SeriesCatalogData data) {
    final categories = data.series
        .map((item) => item.category)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final categoryCounts = <String, int>{};
    for (final item in data.series) {
      final category = item.category?.trim();
      if (category == null || category.isEmpty) continue;
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }

    final normalized = _query.trim().toLowerCase();
    final visible = data.series.where((item) {
      if (_category != null && item.category != _category) return false;
      if (normalized.isEmpty) return true;
      return item.name.toLowerCase().contains(normalized) ||
          (item.genre?.toLowerCase().contains(normalized) ?? false) ||
          (item.category?.toLowerCase().contains(normalized) ?? false);
    }).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gridColumns = width >= 1500
            ? 7
            : width >= 1200
                ? 6
                : width >= 950
                    ? 5
                    : width >= 700
                        ? 4
                        : width >= 480
                            ? 3
                            : 2;

        Widget grid() => visible.isEmpty
            ? const Center(child: Text('No hay resultados.'))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridColumns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.62,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final series = visible[index];
                  return _SeriesPosterCard(
                    series: series,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => XtreamSeriesDetailScreen(
                          connection: data.connection,
                          summary: series,
                        ),
                      ),
                    ),
                  );
                },
              );

        // En escritorio usamos exactamente el mismo patrón que TV/Películas:
        // categorías verticales, plegables y con borde redimensionable.
        if (width >= 760) {
          return Row(
            children: [
              SizedBox(
                width: _sidebarCollapsed ? 72 : _sidebarWidth,
                child: _SeriesCategorySidebar(
                  totalCount: data.series.length,
                  categories: categories,
                  categoryCounts: categoryCounts,
                  selectedCategory: _category,
                  collapsed: _sidebarCollapsed,
                  onToggleCollapsed: _toggleSidebar,
                  onCategorySelected: (value) =>
                      setState(() => _category = value),
                ),
              ),
              MouseRegion(
                cursor: _sidebarCollapsed
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _sidebarCollapsed
                      ? null
                      : (details) => _resizeSidebar(details.delta.dx),
                  onHorizontalDragEnd:
                      _sidebarCollapsed ? null : (_) => _persistSidebar(),
                  child: Container(
                    width: 9,
                    alignment: Alignment.center,
                    child: Container(width: 1, color: Colors.white12),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SeriesCatalogToolbar(
                      query: _query,
                      visibleCount: visible.length,
                      selectedCategory: _category,
                      onQueryChanged: (value) => setState(() => _query = value),
                    ),
                    Expanded(child: grid()),
                  ],
                ),
              ),
            ],
          );
        }

        // En tamaños angostos evitamos una barra lateral que quite demasiado
        // espacio al póster, pero mantenemos categorías legibles con un selector.
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar serie, género o categoría…',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.folder_rounded),
                      labelText: 'Categoría',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      ...categories.map(
                        (category) => DropdownMenuItem<String?>(
                          value: category,
                          child: Text(category, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _category = value),
                  ),
                ],
              ),
            ),
            Expanded(child: grid()),
          ],
        );
      },
    );
  }
'''
text = text[:start] + new_block + text[end:]

insert_at = text.index('\nclass XtreamSeriesDetailScreen')
helpers = r'''
class _SeriesCatalogToolbar extends StatelessWidget {
  final String query;
  final int visibleCount;
  final String? selectedCategory;
  final ValueChanged<String> onQueryChanged;

  const _SeriesCatalogToolbar({
    required this.query,
    required this.visibleCount,
    required this.selectedCategory,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedCategory ?? 'SERIES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$visibleCount series',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                      ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 360,
            child: TextFormField(
              initialValue: query,
              decoration: InputDecoration(
                hintText: 'Buscar en series…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.4,
                  ),
                ),
                isDense: true,
              ),
              onChanged: onQueryChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesCategorySidebar extends StatelessWidget {
  final int totalCount;
  final List<String> categories;
  final Map<String, int> categoryCounts;
  final String? selectedCategory;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String?> onCategorySelected;

  const _SeriesCategorySidebar({
    required this.totalCount,
    required this.categories,
    required this.categoryCounts,
    required this.selectedCategory,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF081728),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment:
              collapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 8 : 20,
                18,
                collapsed ? 8 : 10,
                8,
              ),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    Icons.video_library_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Series',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Achicar categorías',
                      onPressed: onToggleCollapsed,
                      icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                    ),
                  ],
                ],
              ),
            ),
            if (collapsed)
              IconButton(
                tooltip: 'Agrandar categorías',
                onPressed: onToggleCollapsed,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'CATEGORÍAS',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Colors.white54,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                      ),
                    ),
                    const Tooltip(
                      message: 'Arrastrá el borde derecho para cambiar el ancho',
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: Colors.white30,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 8 : 10,
                  0,
                  collapsed ? 8 : 10,
                  20,
                ),
                itemCount: categories.length + 1,
                itemBuilder: (context, index) {
                  final category = index == 0 ? null : categories[index - 1];
                  final label = category ?? 'Todos';
                  final selected = category == selectedCategory;
                  final count = category == null
                      ? totalCount
                      : (categoryCounts[category] ?? 0);

                  if (collapsed) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Tooltip(
                        message: '$label · $count',
                        child: Material(
                          color: selected
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.20)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onCategorySelected(category),
                            child: SizedBox(
                              height: 52,
                              child: Icon(
                                category == null
                                    ? Icons.grid_view_rounded
                                    : Icons.folder_rounded,
                                size: 25,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Tooltip(
                      message: label,
                      waitDuration: const Duration(milliseconds: 450),
                      child: ListTile(
                        minTileHeight: 54,
                        selected: selected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.20),
                        leading: Icon(
                          category == null
                              ? Icons.grid_view_rounded
                              : Icons.folder_rounded,
                          size: 24,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white70,
                        ),
                        title: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        onTap: () => onCategorySelected(category),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

'''
text = text[:insert_at] + '\n' + helpers + text[insert_at:]

path.write_text(text)
