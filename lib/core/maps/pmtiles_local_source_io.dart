import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../offline/offline_package_verifier.dart';
import '../offline/pmtiles_archive_verifier.dart';

Future<String?> findLocalPmTiles({String? expectedFileName}) async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}offline_regions',
  );
  if (!await directory.exists()) return null;

  if (expectedFileName != null && expectedFileName.trim().isNotEmpty) {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${expectedFileName.trim()}',
    );
    try {
      if (await file.length() > 0) return file.path;
    } on FileSystemException {
      return null;
    }
    return null;
  }

  final candidates = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.pmtiles')) {
      candidates.add(entity);
    }
  }

  candidates.sort((a, b) => a.path.compareTo(b.path));
  for (final file in candidates) {
    try {
      if (await file.length() > 0) return file.path;
    } on FileSystemException {
      // A concurrently removed/incomplete download is simply skipped.
    }
  }
  return null;
}

Future<String?> findValidLocalPmTiles({
  required String expectedFileName,
  required String expectedSha256,
}) async {
  final path = await findLocalPmTiles(expectedFileName: expectedFileName);
  if (path == null) return null;

  final file = File(path);
  try {
    await const OfflinePackageVerifier().verifyFile(
      file,
      expectedSha256: expectedSha256,
    );
    return file.path;
  } on Object {
    return null;
  }
}

