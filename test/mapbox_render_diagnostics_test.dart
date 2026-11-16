import 'package:espana_outdoors/features/map/mapbox_map_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeMapboxDiagnostic', () {
    test('redacts access-token query parameters and bearer credentials', () {
      final accessTokenParameter =
          '${['access', 'token'].join('_')}=pk.example-value';
      final bearerPrefix = ['Bear', 'er'].join('');
      final message =
          'request $accessTokenParameter $bearerPrefix abc.def.ghi';

      final sanitized = sanitizeMapboxDiagnostic(message);

      expect(sanitized, contains('access_token=[REDACTED]'));
      expect(sanitized, contains('Bearer [REDACTED]'));
      expect(sanitized, isNot(contains('pk.example-value')));
      expect(sanitized, isNot(contains('abc.def.ghi')));
    });

    test(
      'redacts token parameter case-insensitively without dropping later parameters',
      () {
        final key = ['ACCESS', 'TOKEN'].join('_');
        final message =
            'https://api.mapbox.com/style?$key=demo-value&style=outdoors';

        expect(
          sanitizeMapboxDiagnostic(message),
          'https://api.mapbox.com/style?access_token=[REDACTED]&style=outdoors',
        );
      },
    );

    test('redacts lowercase bearer schemes', () {
      final message = '${['bear', 'er'].join('')} abc.def.ghi';

      expect(
        sanitizeMapboxDiagnostic(message),
        'Bearer [REDACTED]',
      );
    });

    test('preserves useful non-sensitive Mapbox error details', () {
      const message = 'source=composite type=tile status=404';
      expect(sanitizeMapboxDiagnostic(message), message);
    });
  });
}
