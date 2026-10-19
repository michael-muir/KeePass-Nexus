import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:keeppass_nexus/src/rust/api.dart' as rust_api;
import 'package:keeppass_nexus/src/vault_file_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VaultController extends ChangeNotifier {
  final VaultFileStore _fileStore = VaultFileStore();
  rust_api.VaultSession? _session;
  String? _filePath;
  Uint8List? _lastSavedBytes;
  int? _sourceKdbxMajorVersion;
  int? _sourceKdbxMinorVersion;
  rust_api.VaultSnapshot? snapshot;
  String? selectedGroupId;
  String? selectedEntryId;
  String searchQuery = '';
  List<rust_api.EntrySummary> searchResults = const [];
  List<rust_api.EntrySummary> favoriteResults = const [];
  String? selectedTag;
  final List<String> _recentEntryIds = [];
  int _searchRequest = 0;

  bool get isOpen => _session != null;
  bool get isDirty => snapshot?.dirty ?? false;
  String? get filePath => _filePath;
  bool get requiresKdbxFormatUpgrade =>
      _sourceKdbxMajorVersion == 3 ||
      (_sourceKdbxMajorVersion == 4 && _sourceKdbxMinorVersion == 0);
  String? get sourceKdbxVersion => _sourceKdbxMajorVersion == null
      ? null
      : '$_sourceKdbxMajorVersion.$_sourceKdbxMinorVersion';
  bool get selectedGroupIsRecycleBin =>
      _findGroup(snapshot?.root, selectedGroupId)?.isRecycleBin ?? false;

  bool isGroupInRecycleBin(String id) {
    final bin = _findRecycleBin(snapshot?.root);
    final target = _findGroup(snapshot?.root, id);
    if (bin == null || target == null) return false;
    return _containsGroup(bin, id);
  }

  bool isGroupDirectlyInRecycleBin(String id) =>
      _findGroup(snapshot?.root, id)?.parentIsRecycleBin ?? false;
  int revision = 0;

  List<rust_api.EntrySummary> get visibleEntries {
    final current = snapshot;
    if (current == null) return const [];
    if (searchQuery.isNotEmpty) return searchResults;
    if (selectedTag != null) {
      return _allEntries(current.root)
          .where((entry) => entry.tags.any((tag) => tag == selectedTag))
          .toList();
    }
    if (showFavorites) return favoriteResults;
    if (showRecent) {
      final entries = _allEntries(current.root).asMap();
      return _recentEntryIds
          .map((id) => entries.values.where((entry) => entry.id == id))
          .where((matches) => matches.isNotEmpty)
          .map((matches) => matches.first)
          .toList();
    }
    final group = _findGroup(current.root, selectedGroupId);
    final entries = [...?group?.entries];
    entries
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return entries;
  }

  bool showFavorites = false;
  bool showRecent = false;

  List<String> get availableTags =>
      _allEntries(snapshot?.root).expand((entry) => entry.tags).toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

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
    final preferences = await SharedPreferences.getInstance();
    final recent = preferences.getStringList('recentVaultFiles') ?? [];
    recent.remove(path);
    recent.insert(0, path);
    await preferences.setStringList(
      'recentVaultFiles',
      recent.take(10).toList(),
    );
    _session = session;
    _filePath = path;
    _lastSavedBytes = Uint8List.fromList(bytes);
    final sourceVersion = _kdbxVersion(bytes);
    _sourceKdbxMajorVersion = sourceVersion?.major;
    _sourceKdbxMinorVersion = sourceVersion?.minor;
    await _refresh();
    selectedGroupId = snapshot?.root.id;
    selectedEntryId = null;
    searchQuery = '';
    showFavorites = false;
    showRecent = false;
    selectedTag = null;
    searchResults = const [];
    favoriteResults =
        await rust_api.favoriteEntries(session: _requireSession());
    _recentEntryIds.clear();
    notifyListeners();
  }

  Future<void> createVault({
    required String path,
    required String name,
    required String password,
  }) async {
    final session = await rust_api.createVault(name: name, password: password);
    final preferences = await SharedPreferences.getInstance();
    final recent = preferences.getStringList('recentVaultFiles') ?? [];
    recent.remove(path);
    recent.insert(0, path);
    await preferences.setStringList(
      'recentVaultFiles',
      recent.take(10).toList(),
    );
    _session = session;
    _filePath = path;
    _lastSavedBytes = null;
    _sourceKdbxMajorVersion = 4;
    _sourceKdbxMinorVersion = 1;
    selectedEntryId = null;
    await _refresh();
    selectedGroupId = snapshot?.root.id;
    await save();
  }

  Future<void> lock() async {
    _session = null;
    _filePath = null;
    _lastSavedBytes = null;
    _sourceKdbxMajorVersion = null;
    _sourceKdbxMinorVersion = null;
    snapshot = null;
    selectedGroupId = null;
    selectedEntryId = null;
    searchQuery = '';
    showFavorites = false;
    showRecent = false;
    selectedTag = null;
    searchResults = const [];
    favoriteResults = const [];
    _recentEntryIds.clear();
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

  Future<void> permanentlyDeleteEntry(String id) async {
    await rust_api.permanentlyDeleteEntry(session: _requireSession(), id: id);
    selectedEntryId = null;
    await _refresh();
  }

  Future<void> restoreEntry(String id) async {
    await rust_api.restoreEntry(session: _requireSession(), id: id);
    selectedEntryId = null;
    await _refresh();
  }

  Future<void> cloneEntry(String id) async {
    final clonedId =
        await rust_api.cloneEntry(session: _requireSession(), id: id);
    await _refresh();
    selectEntry(clonedId);
  }

  Future<void> toggleFavorite(String id, bool favorite) async {
    await rust_api.setEntryFavorite(
      session: _requireSession(),
      id: id,
      favorite: favorite,
    );
    await _refresh();
  }

  Future<List<rust_api.EntryHistoryItem>> entryHistory(String id) =>
      rust_api.entryHistory(session: _requireSession(), id: id);

  Future<void> restoreEntryHistory(String id, BigInt index) async {
    await rust_api.restoreEntryHistory(
      session: _requireSession(),
      id: id,
      historyIndex: index,
    );
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

  Future<void> renameGroup(String id, String name) async {
    await rust_api.renameGroup(session: _requireSession(), id: id, name: name);
    await _refresh();
  }

  Future<void> moveGroup(String id, String parentId) async {
    await rust_api.moveGroup(
        session: _requireSession(), id: id, parentId: parentId);
    await _refresh();
  }

  Future<void> deleteGroup(String id) async {
    await rust_api.deleteGroup(session: _requireSession(), id: id);
    selectedGroupId = snapshot?.root.id;
    await _refresh();
  }

  Future<void> restoreGroup(String id) async {
    await rust_api.restoreGroup(session: _requireSession(), id: id);
    await _refresh();
  }

  Future<void> permanentlyDeleteGroup(String id) async {
    await rust_api.permanentlyDeleteGroup(session: _requireSession(), id: id);
    selectedGroupId = snapshot?.root.id;
    await _refresh();
  }

  void selectFavorites() {
    showFavorites = true;
    showRecent = false;
    selectedTag = null;
    selectedEntryId = null;
    selectedGroupId = null;
    searchQuery = '';
    searchResults = const [];
    notifyListeners();
  }

  void selectRecent() {
    showRecent = true;
    showFavorites = false;
    selectedTag = null;
    selectedEntryId = null;
    selectedGroupId = null;
    searchQuery = '';
    searchResults = const [];
    notifyListeners();
  }

  void selectTag(String tag) {
    selectedTag = tag;
    showRecent = false;
    showFavorites = false;
    selectedEntryId = null;
    selectedGroupId = null;
    searchQuery = '';
    searchResults = const [];
    notifyListeners();
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
    showFavorites = false;
    showRecent = false;
    selectedTag = null;
    searchQuery = '';
    searchResults = const [];
    _searchRequest++;
    notifyListeners();
  }

  void selectEntry(String? id) {
    selectedEntryId = id;
    if (id != null) {
      _recentEntryIds.remove(id);
      _recentEntryIds.insert(0, id);
      if (_recentEntryIds.length > 20) _recentEntryIds.removeLast();
    }
    notifyListeners();
  }

  Future<void> save({bool allowKdbxFormatUpgrade = false}) async {
    final path = _filePath;
    if (path == null) throw StateError('No vault file is open.');
    final bytes = await rust_api.saveVault(
      session: _requireSession(),
      allowKdbxFormatUpgrade: allowKdbxFormatUpgrade,
    );
    await _fileStore.save(
      path: path,
      encryptedBytes: bytes,
      expectedCurrentBytes: _lastSavedBytes,
    );
    _lastSavedBytes = Uint8List.fromList(bytes);
    _sourceKdbxMajorVersion = 4;
    _sourceKdbxMinorVersion = 1;
    await rust_api.markVaultSaved(session: _requireSession());
    await _refresh();
  }

  Future<void> _refresh() async {
    snapshot = await rust_api.vaultSnapshot(session: _requireSession());
    favoriteResults =
        await rust_api.favoriteEntries(session: _requireSession());
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

  ({int major, int minor})? _kdbxVersion(List<int> bytes) {
    if (bytes.length < 12 ||
        bytes[0] != 0x03 ||
        bytes[1] != 0xD9 ||
        bytes[2] != 0xA2 ||
        bytes[3] != 0x9A) {
      return null;
    }
    return (
      major: bytes[10] | (bytes[11] << 8),
      minor: bytes[8] | (bytes[9] << 8),
    );
  }

  rust_api.GroupNode? _findGroup(rust_api.GroupNode? node, String? id) {
    if (node == null) return null;
    if (node.id == id) return node;
    for (final child in node.groups) {
      final match = _findGroup(child, id);
      if (match != null) return match;
    }
    return null;
  }

  rust_api.GroupNode? _findRecycleBin(rust_api.GroupNode? node) {
    if (node == null) return null;
    if (node.isRecycleBin) return node;
    for (final child in node.groups) {
      final found = _findRecycleBin(child);
      if (found != null) return found;
    }
    return null;
  }

  bool _containsGroup(rust_api.GroupNode node, String id) =>
      node.id == id || node.groups.any((group) => _containsGroup(group, id));

  List<rust_api.EntrySummary> _allEntries(rust_api.GroupNode? node) {
    if (node == null) return const [];
    return [
      ...node.entries,
      for (final group in node.groups) ..._allEntries(group),
    ];
  }
}
