import 'dart:io';

/// Performs a lightweight structural check of a PMTiles v3 archive.
///
/// This complements SHA-256/size verification: a digest proves the downloaded
/// bytes match the catalog, but does not by itself prove the object is PMTiles.
final class PmtilesArchiveVerifier {
  const PmtilesArchiveVerifier();

  static const int headerLength = 127;
  static const List<int> _magic = <int>[0x50, 0x4d, 0x54, 0x69, 0x6c, 0x65, 0x73];

  Future<void> verifyFile(File file) async {
    if (!await file.exists()) {
      throw StateError('PMTiles archive does not exist.');
    }
    if (await file.length() < headerLength) {
      throw const FormatException('PMTiles archive is shorter than its v3 header.');
    }

    final bytes = await file.openRead(0, headerLength).fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (bytes.length < headerLength ||
        !_startsWithMagic(bytes) ||
        bytes[7] != 3) {
      throw const FormatException('Invalid PMTiles v3 archive header.');
    }
  }

  bool _startsWithMagic(List<int> bytes) {
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }
}
