import 'package:espana_outdoors/features/offline/offline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offline page does not claim offline maps are available', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: OfflinePage()));

    expect(find.text('Cartografía offline no disponible'), findsOneWidget);
    expect(find.textContaining('El mapa requiere conexión'), findsOneWidget);
    expect(find.text('Volver al mapa'), findsOneWidget);
  });
}
