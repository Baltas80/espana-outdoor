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
}
