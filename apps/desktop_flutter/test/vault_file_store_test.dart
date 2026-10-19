import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keeppass_nexus/src/vault_file_store.dart';

void main() {
  late Directory temporaryDirectory;
  late VaultFileStore store;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('keepass-nexus-save-test-');
    store = VaultFileStore();
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('creates and verifies an encrypted recovery copy before replacement',
      () async {
    final destination = File('${temporaryDirectory.path}\\vault.kdbx');
    final original = Uint8List.fromList([1, 2, 3, 4]);
    final updated = Uint8List.fromList([5, 6, 7, 8]);
    await destination.writeAsBytes(original);

    final backupPath = await store.save(
      path: destination.path,
      encryptedBytes: updated,
      expectedCurrentBytes: original,
    );

    expect(backupPath, '${destination.path}${VaultFileStore.backupSuffix}');
    expect(await destination.readAsBytes(), updated);
    expect(await File(backupPath!).readAsBytes(), original);
  });

  test('refuses to overwrite a database modified outside the app', () async {
    final destination = File('${temporaryDirectory.path}\\vault.kdbx');
    final expected = Uint8List.fromList([1, 2, 3]);
    final external = Uint8List.fromList([4, 5, 6]);
    await destination.writeAsBytes(external);

    await expectLater(
      store.save(
        path: destination.path,
        encryptedBytes: Uint8List.fromList([7, 8, 9]),
        expectedCurrentBytes: expected,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await destination.readAsBytes(), external);
  });

  test('refuses to overwrite an existing file when creating a new vault',
      () async {
    final destination = File('${temporaryDirectory.path}\\vault.kdbx');
    final existing = Uint8List.fromList([1, 2, 3]);
    await destination.writeAsBytes(existing);

    await expectLater(
      store.save(
        path: destination.path,
        encryptedBytes: Uint8List.fromList([4, 5, 6]),
        expectedCurrentBytes: null,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await destination.readAsBytes(), existing);
  });
}
