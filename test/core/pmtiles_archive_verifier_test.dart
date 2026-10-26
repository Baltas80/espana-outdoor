import 'dart:io';

import 'package:espana_outdoors/core/offline/pmtiles_archive_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const verifier = PmtilesArchiveVerifier();
  final tempDirectory = Directory.systemTemp;

  test('accepts a PMTiles v3 header', () async {
    final file = File(
      '${tempDirectory.path}/espana-outdoor-valid-${DateTime.now().microsecondsSinceEpoch}.pmtiles',
    );
    final bytes = List<int>.filled(PmtilesArchiveVerifier.headerLength, 0)
      ..setRange(0, 7, <int>[0x50, 0x4d, 0x54, 0x69, 0x6c, 0x65, 0x73])
      ..[7] = 3;
    await file.writeAsBytes(bytes);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    await expectLater(verifier.verifyFile(file), completes);
  });

  test('rejects a file shorter than the PMTiles header', () async {
    final file = File(
      '${tempDirectory.path}/espana-outdoor-short-${DateTime.now().microsecondsSinceEpoch}.pmtiles',
    );
    await file.writeAsBytes(<int>[0x50, 0x4d, 0x54, 0x69, 0x6c, 0x65, 0x73, 3]);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    await expectLater(verifier.verifyFile(file), throwsA(isA<FormatException>()));
  });

  test('rejects a non-PMTiles signature', () async {
    final file = File(
      '${tempDirectory.path}/espana-outdoor-signature-${DateTime.now().microsecondsSinceEpoch}.pmtiles',
    );
    final bytes = List<int>.filled(PmtilesArchiveVerifier.headerLength, 0)
      ..[7] = 3;
    await file.writeAsBytes(bytes);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    await expectLater(verifier.verifyFile(file), throwsA(isA<FormatException>()));
  });

  test('rejects unsupported PMTiles versions', () async {
    final file = File(
      '${tempDirectory.path}/espana-outdoor-version-${DateTime.now().microsecondsSinceEpoch}.pmtiles',
    );
    final bytes = List<int>.filled(PmtilesArchiveVerifier.headerLength, 0)
      ..setRange(0, 7, <int>[0x50, 0x4d, 0x54, 0x69, 0x6c, 0x65, 0x73])
      ..[7] = 2;
    await file.writeAsBytes(bytes);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    await expectLater(verifier.verifyFile(file), throwsA(isA<FormatException>()));
  });
}
