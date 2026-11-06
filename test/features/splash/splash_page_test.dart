import 'package:espana_outdoors/features/splash/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the España Outdoor splash hero and loading indicator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: SplashPage()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('splash-hero-background')), findsOneWidget);
    expect(find.text('España Outdoor'), findsOneWidget);
    expect(
      find.text('SENDERISMO  •  BTT  •  NATURALEZA  •  RUTAS'),
      findsOneWidget,
    );
    expect(find.text('Cargando España Outdoor…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the hero content visible on a compact screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: SplashPage()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('España Outdoor'), findsOneWidget);
    expect(find.text('Cargando España Outdoor…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
