import 'dart:io';

import 'package:flutter/foundation.dart';

class VaultFileStore {
  static const backupSuffix = '.nexus-backup';

  Future<String?> save({
    required String path,
    required Uint8List encryptedBytes,
    required Uint8List? expectedCurrentBytes,
  }) async {
    final destination = File(path);
    final exists = await destination.exists();
    if (expectedCurrentBytes == null) {
      if (exists) {
        throw StateError(
          'The destination already exists. Open it before saving over it.',
        );
      }
    } else {
      if (!exists) {
        throw StateError(
          'The database file was removed outside KeePass Nexus. No changes were saved.',
        );
      }
      final current = await destination.readAsBytes();
      if (!listEquals(current, expectedCurrentBytes)) {
        throw StateError(
          'The database changed outside KeePass Nexus. Reopen it before saving to avoid overwriting external changes.',
        );
      }
    }

    String? backupPath;
    if (expectedCurrentBytes != null) {
      final backup = File('$path$backupSuffix');
      final previousBackup =
          await backup.exists() ? await backup.readAsBytes() : null;
      final stagedBackup = await _stage(backup, expectedCurrentBytes, 'backup');
      try {
        await _replaceFromStage(
          staged: stagedBackup,
          destination: backup,
          expectedDestinationBytes: previousBackup,
          replacementBytes: expectedCurrentBytes,
        );
      } finally {
        if (await stagedBackup.exists()) await stagedBackup.delete();
      }
      backupPath = backup.path;
    }

    final stagedFile = await _stage(destination, encryptedBytes, 'save');
    try {
      final currentBeforeReplace =
          await destination.exists() ? await destination.readAsBytes() : null;
      if (expectedCurrentBytes == null) {
        if (currentBeforeReplace != null) {
          throw StateError(
            'The destination appeared outside KeePass Nexus. No changes were saved.',
          );
        }
      } else if (currentBeforeReplace == null ||
          !listEquals(currentBeforeReplace, expectedCurrentBytes)) {
        throw StateError(
          'The database changed outside KeePass Nexus. Reopen it before saving to avoid overwriting external changes.',
        );
      }

      await _replaceFromStage(
        staged: stagedFile,
        destination: destination,
        expectedDestinationBytes: expectedCurrentBytes,
        replacementBytes: encryptedBytes,
      );
    } finally {
      if (await stagedFile.exists()) await stagedFile.delete();
    }
    return backupPath;
  }

  Future<File> _stage(File destination, List<int> bytes, String label) async {
    final staged = File(
      '${destination.path}.nexus-$label-${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    if (await staged.exists()) {
      throw FileSystemException(
          'Temporary save file already exists.', staged.path);
    }
    try {
      await staged.writeAsBytes(bytes, flush: true);
      final written = await staged.readAsBytes();
      if (!listEquals(written, bytes)) {
        throw FileSystemException(
          'Temporary file verification failed.',
          staged.path,
        );
      }
    } on FileSystemException {
      if (await staged.exists()) await staged.delete();
      rethrow;
    }
    return staged;
  }

  Future<void> _replaceFromStage({
    required File staged,
    required File destination,
    required Uint8List? expectedDestinationBytes,
    required List<int> replacementBytes,
  }) async {
    final destinationExists = await destination.exists();
    final current = destinationExists ? await destination.readAsBytes() : null;
    if (expectedDestinationBytes == null) {
      if (current != null) {
        throw StateError(
          'A file appeared at ${destination.path}. No file was replaced.',
        );
      }
    } else if (current == null ||
        !listEquals(current, expectedDestinationBytes)) {
      throw StateError(
        'The file at ${destination.path} changed while saving. No file was replaced.',
      );
    }

    final rollback = destinationExists
        ? File(
            '${destination.path}.nexus-rollback-${DateTime.now().microsecondsSinceEpoch}-$pid',
          )
        : null;
    if (rollback != null) await destination.rename(rollback.path);

    try {
      await staged.rename(destination.path);
      final written = await destination.readAsBytes();
      if (!listEquals(written, replacementBytes)) {
        throw FileSystemException(
          'Saved file verification failed.',
          destination.path,
        );
      }
    } on FileSystemException catch (error) {
      try {
        if (await destination.exists()) await destination.delete();
        if (rollback != null && await rollback.exists()) {
          await rollback.rename(destination.path);
        }
      } on FileSystemException catch (restoreError) {
        throw FileSystemException(
          'Save failed ($error), and automatic restoration failed ($restoreError). '
          'The verified recovery backup, if created, is at ${destination.path}$backupSuffix.',
          destination.path,
        );
      }
      rethrow;
    }

    if (rollback != null && await rollback.exists()) await rollback.delete();
  }
}
