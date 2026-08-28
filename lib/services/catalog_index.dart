class CatalogIndex<T> {
  final List<T> all;
  final List<String> categories;
  final Map<String, List<T>> _byCategory;
  final List<_CatalogSearchEntry<T>> _searchEntries;

  const CatalogIndex._(
    this.all,
    this.categories,
    this._byCategory,
    this._searchEntries,
  );

  factory CatalogIndex.build({
    required Iterable<T> items,
    required String Function(T item) nameOf,
    required String? Function(T item) categoryOf,
    required bool Function(T item) include,
    Iterable<String> categoryOrder = const <String>[],
  }) {
    final visible = <T>[];
    final buckets = <String, List<T>>{};
    final searchEntries = <_CatalogSearchEntry<T>>[];
    final discovered = <String>[];
    final discoveredSet = <String>{};

    for (final item in items) {
      if (!include(item)) continue;
      visible.add(item);
      final category = categoryOf(item)?.trim();
      if (category != null && category.isNotEmpty) {
        buckets.putIfAbsent(category, () => <T>[]).add(item);
        if (discoveredSet.add(category)) discovered.add(category);
      }
      final searchText = _normalizeCatalogSearch(
        '${nameOf(item)} ${category ?? ''}',
      );
      searchEntries.add(_CatalogSearchEntry(item, searchText));
    }

    final orderedCategories = <String>[];
    final added = <String>{};
    for (final raw in categoryOrder) {
      final category = raw.trim();
      if (category.isEmpty || !buckets.containsKey(category)) continue;
      if (added.add(category)) orderedCategories.add(category);
    }
    for (final category in discovered) {
      if (added.add(category)) orderedCategories.add(category);
    }

    return CatalogIndex._(
      List<T>.unmodifiable(visible),
      List<String>.unmodifiable(orderedCategories),
      Map<String, List<T>>.unmodifiable(
        buckets.map(
          (key, value) => MapEntry(key, List<T>.unmodifiable(value)),
        ),
      ),
      List<_CatalogSearchEntry<T>>.unmodifiable(searchEntries),
    );
  }

  List<T> forCategory(String? category) {
    if (category == null) return all;
    return _byCategory[category] ?? const <T>[];
  }

  List<T> search(String rawQuery) {
    final query = _normalizeCatalogSearch(rawQuery);
    if (query.isEmpty) return all;
    final result = <T>[];
    for (final entry in _searchEntries) {
      if (entry.searchText.contains(query)) result.add(entry.item);
    }
    return result;
  }
}

class _CatalogSearchEntry<T> {
  final T item;
  final String searchText;
  const _CatalogSearchEntry(this.item, this.searchText);
}

String _normalizeCatalogSearch(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
