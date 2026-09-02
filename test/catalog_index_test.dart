import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/catalog_index.dart';

void main() {
  test('agrupa categorías y busca sólo elementos visibles', () {
    final items = <_Item>[
      const _Item('Canal Noticias', 'Noticias', true),
      const _Item('Película Acción', 'Cine', true),
      const _Item('Contenido bloqueado', 'Adultos', false),
    ];
    final index = CatalogIndex<_Item>.build(
      items: items,
      categoryOrder: const <String>['Cine', 'Noticias', 'Adultos'],
      nameOf: (item) => item.name,
      categoryOf: (item) => item.category,
      include: (item) => item.visible,
    );

    expect(index.categories, <String>['Cine', 'Noticias']);
    expect(index.forCategory('Noticias').single.name, 'Canal Noticias');
    expect(index.search('accion').single.name, 'Película Acción');
    expect(index.search('bloqueado'), isEmpty);
  });
}

class _Item {
  final String name;
  final String category;
  final bool visible;

  const _Item(this.name, this.category, this.visible);
}
