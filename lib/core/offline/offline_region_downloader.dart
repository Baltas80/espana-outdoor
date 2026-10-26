import 'dart:io';

import 'package:background_downloader/background_downloader.dart';

import 'offline_package_verifier.dart';
import 'pmtiles_archive_verifier.dart';
import 'offline_region.dart';

class OfflineRegionDownloader {
  const OfflineRegionDownloader();

  Future<Transfer> start(OfflineRegion region) async {
    final version = region.sha256.substring(0, 12);
    final taskId = 'offline-region-${region.id}-${version}';
    final task = DownloadTask(
      taskId: taskId,
      url: region.downloadUrl.toString(),
      filename: '${region.id}-${version}.pmtiles',
      directory: 'offline_regions',
      baseDirectory: BaseDirectory.applicationSupport,
      group: 'offline-regions',
      updates: Updates.statusAndProgress,
      retries: 5,
      allowPause: true,
      transferHints: const {TransferHint.largeFile},
      metaData:
          '${region.id}|sha256=${region.sha256}|provider=${region.providerId}',
      displayName: region.name,
    );
    return FileDownloader().transfers.getOrStart(task);
  }

  Future<File> startAndVerify(
    OfflineRegion region, {
    bool requireChecksum = true,
  }) async {
    final transfer = await start(region);
    final file = await transfer.file;
    await const OfflinePackageVerifier().verifyFile(
      file,
      expectedSha256: region.sha256,
      expectedBytes: region.sizeBytes,
      requireChecksum: requireChecksum,
    );
    await const PmtilesArchiveVerifier().verifyFile(file);
    return file;
  }

  Future<File> verifyExisting(
    OfflineRegion region,
    File file, {
    bool requireChecksum = true,
  }) async {
    await const OfflinePackageVerifier().verifyFile(
      file,
      expectedSha256: region.sha256,
      expectedBytes: region.sizeBytes,
      requireChecksum: requireChecksum,
    );
    await const PmtilesArchiveVerifier().verifyFile(file);
    return file;
  }

  Future<bool> pause(Transfer transfer) => transfer.pause();
  Future<bool> resume(Transfer transfer) => transfer.resume();
  Future<bool> cancel(Transfer transfer) => transfer.cancel();
}
