import 'dart:async';
import 'dart:convert';

import 'package:espana_outdoors/core/offline/offline_region.dart';
import 'package:espana_outdoors/core/offline/offline_region_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Map<String, Object?> _validRegion() => {
      'id': 'madrid-2026-09',
      'name': 'Madrid',
      'description': 'Paquete cartográfico regional',
      'providerId': 'approved-pmtiles-catalog',
      'licenseUrl': 'https://maps.example.com/license',
      'attribution': 'Proveedor cartográfico',
      'downloadUrl': 'https://maps.example.com/madrid.pmtiles',
      'sizeBytes': 1024,
      'updatedAt': '2026-09-23T10:00:00Z',
      'sha256': List.filled(64, 'a').join(),
    };

class _FakeClient extends http.BaseClient {
  _FakeClient(
    this.payload, {
    this.statusCode = 200,
    this.delay = Duration.zero,
  });

  final Object payload;
  final int statusCode;
  final Duration delay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      statusCode,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  test('offline region metadata is parsed and normalized', () {
    final region = OfflineRegion.fromJson(_validRegion());

    expect(region.id, 'madrid-2026-09');
    expect(region.providerId, 'approved-pmtiles-catalog');
    expect(region.downloadUrl.isScheme('https'), isTrue);
    expect(region.licenseUrl.isScheme('https'), isTrue);
    expect(region.attribution, 'Proveedor cartográfico');
    expect(region.sizeBytes, 1024);
    expect(region.updatedAt.isUtc, isTrue);
  });

  test('offline region metadata rejects malformed input', () {
    expect(
      () => OfflineRegion.fromJson({'id': 'broken'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('offline region metadata rejects non-HTTPS downloads', () {
    final invalid = _validRegion()..['downloadUrl'] = 'http://maps.example.com/dev.pmtiles';

    expect(
      () => OfflineRegion.fromJson(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('offline region metadata rejects non-HTTPS licence URLs', () {
    final invalid = _validRegion()..['licenseUrl'] = 'http://maps.example.com/license';

    expect(
      () => OfflineRegion.fromJson(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('offline region metadata rejects missing attribution', () {
    final invalid = _validRegion()..remove('attribution');

    expect(
      () => OfflineRegion.fromJson(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('offline region metadata rejects fractional size', () {
    final invalid = _validRegion()..['sizeBytes'] = 1024.5;

    expect(
      () => OfflineRegion.fromJson(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('offline catalog requires HTTPS', () {
    expect(
      () => OfflineRegionCatalog(endpoint: Uri.parse('http://maps.example.com/catalog')),
      throwsArgumentError,
    );
  });

  test('offline catalog accepts the published single-region object', () async {
    final region = _validRegion();
    final catalog = OfflineRegionCatalog(
      endpoint: Uri.parse('https://maps.example.com/catalog/spain.json'),
      client: _FakeClient(region),
    );

    final entries = await catalog.fetch();

    expect(entries, hasLength(1));
    expect(entries.single.id, 'madrid-2026-09');
    expect(entries.single.sha256, region['sha256']);
  });

  test('offline catalog rejects non-success HTTP status', () async {
    final catalog = OfflineRegionCatalog(
      endpoint: Uri.parse('https://maps.example.com/catalog.json'),
      client: _FakeClient({'error': 'unavailable'}, statusCode: 503),
    );

    await expectLater(catalog.fetch(), throwsA(isA<StateError>()));
  });

  test('offline catalog rejects non-object entries instead of skipping them', () async {
    final catalog = OfflineRegionCatalog(
      endpoint: Uri.parse('https://maps.example.com/catalog.json'),
      client: _FakeClient([_validRegion(), 'invalid-entry']),
    );

    await expectLater(catalog.fetch(), throwsA(isA<FormatException>()));
  });

  test('offline catalog rejects duplicate region identifiers', () async {
    final region = _validRegion();
    final catalog = OfflineRegionCatalog(
      endpoint: Uri.parse('https://maps.example.com/catalog.json'),
      client: _FakeClient([region, Map<String, Object?>.from(region)]),
    );

    await expectLater(catalog.fetch(), throwsA(isA<FormatException>()));
  });

  test('offline catalog rejects an empty array', () async {
    final catalog = OfflineRegionCatalog(
      endpoint: Uri.parse('https://maps.example.com/catalog.json'),
      client: _FakeClient([]),
    );

    await expectLater(catalog.fetch(), throwsA(isA<FormatException>()));
  });

  test('offline catalog times out using its configured timeout', () async {
    final catalog = OfflineRegionCatalog(
      endpoint: Uri.parse('https://maps.example.com/catalog.json'),
      client: _FakeClient(
        [_validRegion()],
        delay: const Duration(milliseconds: 100),
      ),
      requestTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(catalog.fetch(), throwsA(isA<TimeoutException>()));
  });

}
