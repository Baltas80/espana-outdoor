import 'package:espana_outdoors/features/splash/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('shows the complete brand lockup for at least two seconds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          builder: (_, __) => const SplashPage(),
        ),
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('Inicio de prueba')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('España Outdoor'), findsOneWidget);
    expect(
      find.text('SENDERISMO · BTT · NATURALEZA · RUTAS'),
      findsOneWidget,
    );
    expect(find.text('Preparando tu próxima aventura…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 1899));
    expect(find.text('España Outdoor'), findsOneWidget);
    expect(find.text('Inicio de prueba'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Inicio de prueba'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
