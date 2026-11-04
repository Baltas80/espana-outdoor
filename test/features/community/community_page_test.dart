import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:espana_outdoors/features/community/community_page.dart';

void main() {
  testWidgets('community exposes following and explore demo feeds', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CommunityPage()));
    await tester.pumpAndSettle();

    expect(find.text('Comunidad'), findsOneWidget);
    expect(find.text('Siguiendo'), findsOneWidget);
    expect(find.text('Explorar'), findsOneWidget);
    expect(find.textContaining('Vista previa'), findsWidgets);
    expect(find.text('Perfil de ejemplo'), findsWidgets);

    await tester.tap(find.text('Explorar'));
    await tester.pumpAndSettle();

    expect(find.text('Buscar experiencias y descubrimientos'), findsOneWidget);
  });

  testWidgets('community demo likes update locally and search filters posts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CommunityPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();
    expect(find.text('19'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'miradores que no existen',
    );
    await tester.pumpAndSettle();
    expect(find.text('No hay coincidencias para esta búsqueda.'), findsOneWidget);
  });
}
