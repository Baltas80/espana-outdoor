import 'package:espana_outdoors/app/design_system/eo_icon_library.dart';
import 'package:espana_outdoors/app/eo_components.dart';
import 'package:espana_outdoors/app/outdoor_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all 27 premium icon assets are included in the Flutter bundle', () async {
    expect(EOIconName.values, hasLength(27));

    for (final icon in EOIconName.values) {
      final asset =
          'assets/visuals/icons/library/premium/${icon.name}.webp';
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0), reason: asset);
    }
  });

  testWidgets('premium artwork is not flattened by inherited theme colors', (
    tester,
  ) async {
    const lightIconColor = Color(0xFF102326);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          iconTheme: const IconThemeData(color: lightIconColor),
        ),
        home: const Scaffold(body: EOIcon(EOIconName.compass)),
      ),
    );

    var image = tester.widget<Image>(find.byType(Image));
    expect(image.color, isNull);
    expect(image.colorBlendMode, isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: IconTheme(
            data: IconThemeData(color: Colors.white),
            child: EOIcon(EOIconName.compass),
          ),
        ),
      ),
    );

    image = tester.widget<Image>(find.byType(Image));
    expect(image.color, isNull);
    expect(image.colorBlendMode, isNull);
  });

  testWidgets('navigation and outdoor asset icons preserve source artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Center(
            child: OutdoorAssetIcon(
              asset: 'assets/visuals/icons/library/premium/compass.webp',
            ),
          ),
          bottomNavigationBar: EONavigationBar(
            currentIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images, hasLength(6));
    for (final image in images) {
      expect(image.color, isNull);
      expect(image.colorBlendMode, isNull);
    }
  });
}
