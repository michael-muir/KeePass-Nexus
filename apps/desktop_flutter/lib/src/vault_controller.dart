import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:keeppass_nexus/src/rust/api.dart' as rust_api;

class VaultController extends ChangeNotifier {
  rust_api.VaultSession? _session;
  String? _filePath;
  rust_api.VaultSnapshot? snapshot;
  String? selectedGroupId;
  String? selectedEntryId;
  String searchQuery = '';
  List<rust_api.EntrySummary> searchResults = const [];
  int _searchRequest = 0;

  bool get isOpen => _session != null;
  bool get isDirty => snapshot?.dirty ?? false;
  String? get filePath => _filePath;
  int revision = 0;

  List<rust_api.EntrySummary> get visibleEntries {
    final current = snapshot;
    if (current == null) return const [];
    if (searchQuery.isNotEmpty) return searchResults;
    final group = _findGroup(current.root, selectedGroupId);
    return group?.entries ?? const [];
  }

  Future<void> openVault({
    required String path,
    required String password,
    String? keyFilePath,
  }) async {
    final bytes = await File(path).readAsBytes();
    final keyFile =
        keyFilePath == null ? null : await File(keyFilePath).readAsBytes();
    final session = await rust_api.openVault(
      bytes: bytes,
      password: password.isEmpty ? null : password,
      keyFile: keyFile,
    );
    _session = session;
    _filePath = path;
    await _refresh();
    selectedGroupId = snapshot?.root.id;
    selectedEntryId = null;
    searchQuery = '';
    searchResults = const [];
    notifyListeners();
  }

  Future<void> createVault({
    required String path,
    required String name,
    required String password,
  }) async {
    final session = await rust_api.createVault(name: name, password: password);
    _session = session;
    _filePath = path;
    selectedEntryId = null;
    await _refresh();
    selectedGroupId = snapshot?.root.id;
    await save();
  }

  Future<void> lock() async {
    _session = null;
    _filePath = null;
    snapshot = null;
    selectedGroupId = null;
    selectedEntryId = null;
    searchQuery = '';
    searchResults = const [];
    notifyListeners();
  }

  Future<rust_api.EntryDetails> readEntry(String id) async {
    return rust_api.readEntry(session: _requireSession(), id: id);
  }

  Future<void> createEntry(String groupId, rust_api.EntryInput input) async {
    await rust_api.createEntry(
      session: _requireSession(),
      groupId: groupId,
      input: input,
    );
    await _refresh();
  }

  Future<void> updateEntry(String id, rust_api.EntryInput input) async {
    await rust_api.updateEntry(
        session: _requireSession(), id: id, input: input);
    await _refresh();
  }

  Future<void> moveEntry(String id, String groupId) async {
    await rust_api.moveEntry(
      session: _requireSession(),
      id: id,
      groupId: groupId,
    );
    selectedEntryId = null;
    await _refresh();
  }

  Future<void> deleteEntry(String id) async {
    await rust_api.deleteEntry(session: _requireSession(), id: id);
    selectedEntryId = null;
    await _refresh();
  }

  Future<void> createGroup(String parentId, String name) async {
    await rust_api.createGroup(
      session: _requireSession(),
      parentId: parentId,
      name: name,
    );
    await _refresh();
  }

  Future<void> search(String query) async {
    searchQuery = query.trim();
    final request = ++_searchRequest;
    if (searchQuery.isEmpty) {
      searchResults = const [];
    } else {
      searchResults = const [];
      notifyListeners();
      final results = await rust_api.searchEntries(
        session: _requireSession(),
        query: searchQuery,
      );
      if (request != _searchRequest) return;
      searchResults = results;
    }
    notifyListeners();
  }

  void selectGroup(String id) {
    selectedGroupId = id;
    selectedEntryId = null;
    searchQuery = '';
    searchResults = const [];
    _searchRequest++;
    notifyListeners();
  }

  void selectEntry(String? id) {
    selectedEntryId = id;
    notifyListeners();
  }

  Future<void> save() async {
    final path = _filePath;
    if (path == null) throw StateError('No vault file is open.');
    final bytes = await rust_api.saveVault(session: _requireSession());
    final destination = File(path);
    final temporary = File('$path.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    await rust_api.markVaultSaved(session: _requireSession());
    await _refresh();
  }

  Future<void> _refresh() async {
    snapshot = await rust_api.vaultSnapshot(session: _requireSession());
    revision++;
    if (searchQuery.isNotEmpty) {
      final request = ++_searchRequest;
      final results = await rust_api.searchEntries(
        session: _requireSession(),
        query: searchQuery,
      );
      if (request == _searchRequest) {
        searchResults = results;
      } else {
        notifyListeners();
        return;
      }
    }
    notifyListeners();
  }

  rust_api.VaultSession _requireSession() {
    final session = _session;
    if (session == null) throw StateError('The vault is locked.');
    return session;
  }

  rust_api.GroupNode? _findGroup(rust_api.GroupNode node, String? id) {
    if (node.id == id) return node;
    for (final child in node.groups) {
      final match = _findGroup(child, id);
      if (match != null) return match;
    }
    return null;
  }
}
