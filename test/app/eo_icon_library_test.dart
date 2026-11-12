import 'package:espana_outdoors/app/design_system/eo_icon_library.dart';
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

  testWidgets('premium icons use a contrasting theme or inherited icon color', (
    tester,
  ) async {
    const lightIconColor = Color(0xFF102326);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          colorScheme: ThemeData.light().colorScheme.copyWith(
                onSurface: lightIconColor,
              ),
          iconTheme: const IconThemeData(color: lightIconColor),
        ),
        home: const Scaffold(body: EOIcon(EOIconName.compass)),
      ),
    );

    var image = tester.widget<Image>(find.byType(Image));
    expect(image.color, lightIconColor);
    expect(image.colorBlendMode, BlendMode.srcIn);

    const inheritedColor = Color(0xFFFFFFFF);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const Scaffold(
          body: IconTheme(
            data: IconThemeData(color: inheritedColor),
            child: EOIcon(EOIconName.compass),
          ),
        ),
      ),
    );

    image = tester.widget<Image>(find.byType(Image));
    expect(image.color, inheritedColor);
  });
}
