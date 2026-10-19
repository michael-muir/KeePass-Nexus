import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:keeppass_nexus/src/entry_icons.dart';
import 'package:keeppass_nexus/src/rust/api.dart' as rust_api;
import 'package:keeppass_nexus/src/screens/entry_editor_dialog.dart';
import 'package:keeppass_nexus/src/screens/settings_screen.dart';
import 'package:keeppass_nexus/src/screens/unlock_screen.dart';
import 'package:keeppass_nexus/src/theme.dart';
import 'package:keeppass_nexus/src/vault_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class KeePassNexusApp extends StatefulWidget {
  const KeePassNexusApp({super.key});

  @override
  State<KeePassNexusApp> createState() => _KeePassNexusAppState();
}

class _KeePassNexusAppState extends State<KeePassNexusApp> with WindowListener {
  final _vault = VaultController();
  final _workspaceKey = GlobalKey<_VaultWorkspaceState>();
  ThemeMode _themeMode = ThemeMode.system;
  int _autoLockMinutes = 5;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadSettings();
  }

  @override
  void onWindowClose() {
    final workspace = _workspaceKey.currentState;
    if (workspace == null) {
      windowManager.destroy();
    } else {
      workspace._handleWindowClose();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _vault.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _themeMode = switch (preferences.getString('themeMode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _autoLockMinutes = preferences.getInt('autoLockMinutes') ?? 5;
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('themeMode', mode.name);
    if (mounted) setState(() => _themeMode = mode);
  }

  Future<void> _setAutoLock(int minutes) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('autoLockMinutes', minutes);
    if (mounted) setState(() => _autoLockMinutes = minutes);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeePass Nexus',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: AnimatedBuilder(
        animation: _vault,
        builder: (context, _) {
          if (!_vault.isOpen) return UnlockScreen(controller: _vault);
          return VaultWorkspace(
            key: _workspaceKey,
            controller: _vault,
            themeMode: _themeMode,
            onThemeModeChanged: _setThemeMode,
            autoLockMinutes: _autoLockMinutes,
            onAutoLockChanged: _setAutoLock,
          );
        },
      ),
    );
  }
}

class VaultWorkspace extends StatefulWidget {
  const VaultWorkspace({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.autoLockMinutes,
    required this.onAutoLockChanged,
    super.key,
  });

  final VaultController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int autoLockMinutes;
  final ValueChanged<int> onAutoLockChanged;

  @override
  State<VaultWorkspace> createState() => _VaultWorkspaceState();
}

class _VaultWorkspaceState extends State<VaultWorkspace> {
  bool _showSettings = false;
  bool _handlingWindowClose = false;
  final _search = TextEditingController();
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _scheduleIdleLock();
  }

  @override
  void didUpdateWidget(covariant VaultWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoLockMinutes != widget.autoLockMinutes) {
      _scheduleIdleLock();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleIdleLock() {
    _idleTimer?.cancel();
    if (widget.autoLockMinutes > 0) {
      _idleTimer = Timer(
        Duration(minutes: widget.autoLockMinutes),
        () => _lock().catchError(_showError),
      );
    }
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent __) {
    _scheduleIdleLock();
    return KeyEventResult.ignored;
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _save() async {
    try {
      var allowKdbxFormatUpgrade = false;
      if (widget.controller.requiresKdbxFormatUpgrade) {
        final path = widget.controller.filePath!;
        final sourceVersion = widget.controller.sourceKdbxVersion;
        final upgradeDescription = sourceVersion?.startsWith('3.') == true
            ? 'convert it from KDBX $sourceVersion to KDBX 4.1'
            : 'upgrade it from KDBX 4.0 to KDBX 4.1';
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Upgrade database format?'),
            content: Text(
              'Saving will $upgradeDescription and create a verified encrypted '
              'recovery backup at "$path.nexus-backup" before replacing the '
              'original. The recovery backup is updated on each later save.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Back up and upgrade'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        allowKdbxFormatUpgrade = true;
      }
      await widget.controller
          .save(allowKdbxFormatUpgrade: allowKdbxFormatUpgrade);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database saved securely.')),
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _lock() async {
    if (widget.controller.isDirty) {
      final action = await showDialog<_LockAction>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text(
            'Save your changes before locking this database?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _LockAction.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _LockAction.discard),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _LockAction.save),
              child: const Text('Save and lock'),
            ),
          ],
        ),
      );
      if (!mounted || action == null || action == _LockAction.cancel) return;
      if (action == _LockAction.save) {
        await _save();
        if (widget.controller.isDirty) return;
      }
    }
    await widget.controller.lock();
  }

  Future<void> _handleWindowClose() async {
    if (_handlingWindowClose) return;
    _handlingWindowClose = true;
    try {
      if (widget.controller.isDirty) {
        final action = await showDialog<_LockAction>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text(
              'Save your changes before closing KeePass Nexus?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, _LockAction.cancel),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _LockAction.discard),
                child: const Text('Discard changes'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, _LockAction.save),
                child: const Text('Save and close'),
              ),
            ],
          ),
        );
        if (!mounted || action == null || action == _LockAction.cancel) return;
        if (action == _LockAction.save) {
          await _save();
          if (widget.controller.isDirty) return;
        }
      }
      await windowManager.destroy();
    } finally {
      _handlingWindowClose = false;
    }
  }

  Future<void> _newEntry() async {
    final groupId = widget.controller.selectedGroupId;
    if (groupId == null) return;
    final input = await showDialog<rust_api.EntryInput>(
      context: context,
      builder: (context) => const EntryEditorDialog(),
    );
    if (input == null) return;
    try {
      await widget.controller.createEntry(groupId, input);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editEntry(String id) async {
    try {
      final initial = await widget.controller.readEntry(id);
      if (!mounted) return;
      final input = await showDialog<rust_api.EntryInput>(
        context: context,
        builder: (context) => EntryEditorDialog(initial: initial),
      );
      if (input != null) await widget.controller.updateEntry(id, input);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteEntry(String id) async {
    final entry = await widget.controller.readEntry(id);
    if (!mounted) return;
    final inRecycleBin =
        widget.controller.isGroupDirectlyInRecycleBin(entry.groupId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(inRecycleBin
            ? 'Permanently delete entry?'
            : 'Move entry to recycle bin?'),
        content: Text(
          inRecycleBin
              ? 'This entry and its attachments will be permanently removed.'
              : 'The entry can be restored from the database recycle bin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
                inRecycleBin ? 'Delete permanently' : 'Move to recycle bin'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (inRecycleBin) {
        await widget.controller.permanentlyDeleteEntry(id);
      } else {
        await widget.controller.deleteEntry(id);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _restoreEntry(String id) async {
    try {
      await widget.controller.restoreEntry(id);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _cloneEntry(String id) async {
    try {
      await widget.controller.cloneEntry(id);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _toggleFavorite(String id, bool favorite) async {
    try {
      await widget.controller.toggleFavorite(id, favorite);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showHistory(String id) async {
    try {
      final history = await widget.controller.entryHistory(id);
      if (!mounted) return;
      final selected = await showDialog<BigInt>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Entry history'),
          content: SizedBox(
            width: 460,
            height: 360,
            child: history.isEmpty
                ? const Center(child: Text('No previous revisions.'))
                : ListView(
                    children: [
                      for (final item in history)
                        ListTile(
                          title: Text(
                            item.title.isEmpty ? 'Untitled' : item.title,
                          ),
                          subtitle: Text([
                            item.username,
                            if (item.modifiedAt != null) item.modifiedAt!,
                          ].where((text) => text.isNotEmpty).join(' · ')),
                          trailing: const Icon(Icons.restore),
                          onTap: () => Navigator.pop(context, item.index),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore this revision?'),
          content: const Text(
            'The current entry will be saved as a new history revision.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.controller.restoreEntryHistory(id, selected);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _renameGroup(String id, String currentName) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NewGroupDialog(
        title: 'Rename group',
        actionLabel: 'Save',
        initialName: currentName,
      ),
    );
    if (name == null) return;
    try {
      await widget.controller.renameGroup(id, name);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _moveGroup(String id) async {
    final groups = _flattenGroups(widget.controller.snapshot?.root)
        .where((group) => !group.isRecycleBin && group.id != id)
        .toList();
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => _GroupDestinationDialog(groups: groups),
    );
    if (destination == null) return;
    try {
      await widget.controller.moveGroup(id, destination);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteGroup(String id, {required bool permanent}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(permanent
            ? 'Permanently delete group?'
            : 'Move group to recycle bin?'),
        content: Text(
          permanent
              ? 'This group and all of its contents will be permanently deleted.'
              : 'The group and all nested contents will move to the recycle bin and can be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child:
                Text(permanent ? 'Delete permanently' : 'Move to recycle bin'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (permanent) {
        await widget.controller.permanentlyDeleteGroup(id);
      } else {
        await widget.controller.deleteGroup(id);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _restoreGroup(String id) async {
    try {
      await widget.controller.restoreGroup(id);
    } catch (error) {
      _showError(error);
    }
  }

  List<rust_api.GroupNode> _flattenGroups(rust_api.GroupNode? group) {
    if (group == null) return const [];
    return [
      group,
      for (final child in group.groups) ..._flattenGroups(child),
    ];
  }

  Future<void> _newGroup() async {
    final parentId = widget.controller.selectedGroupId;
    if (parentId == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewGroupDialog(),
    );
    if (name == null) return;
    try {
      await widget.controller.createGroup(parentId, name);
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        onPointerDown: (_) => _scheduleIdleLock(),
        onPointerMove: (_) => _scheduleIdleLock(),
        child: Focus(
          onKeyEvent: _onKeyEvent,
          child: SafeArea(
            child: Row(
              children: [
                SizedBox(
                  width: 270,
                  child: _VaultSidebar(
                    controller: widget.controller,
                    settingsSelected: _showSettings,
                    onSettings: () => setState(() => _showSettings = true),
                    onBrowse: () => setState(() => _showSettings = false),
                    onNewGroup: _newGroup,
                    onRenameGroup: _renameGroup,
                    onMoveGroup: _moveGroup,
                    onDeleteGroup: (id, permanent) =>
                        _deleteGroup(id, permanent: permanent),
                    onRestoreGroup: _restoreGroup,
                    onLock: _lock,
                    onGroupSelected: _search.clear,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      _WorkspaceHeader(
                        controller: widget.controller,
                        search: _search,
                        settingsSelected: _showSettings,
                        onSearch: (query) {
                          widget.controller
                              .search(query)
                              .catchError(_showError);
                        },
                        onNewEntry: _newEntry,
                        onSave: _save,
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _showSettings
                            ? SettingsScreen(
                                themeMode: widget.themeMode,
                                onThemeModeChanged: widget.onThemeModeChanged,
                                autoLockMinutes: widget.autoLockMinutes,
                                onAutoLockChanged: widget.onAutoLockChanged,
                              )
                            : _EntryBrowser(
                                controller: widget.controller,
                                onEdit: _editEntry,
                                onDelete: _deleteEntry,
                                onClone: _cloneEntry,
                                onToggleFavorite: _toggleFavorite,
                                onHistory: _showHistory,
                                onRestore: _restoreEntry,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _LockAction { save, discard, cancel }

class _VaultSidebar extends StatelessWidget {
  const _VaultSidebar({
    required this.controller,
    required this.settingsSelected,
    required this.onSettings,
    required this.onBrowse,
    required this.onNewGroup,
    required this.onRenameGroup,
    required this.onMoveGroup,
    required this.onDeleteGroup,
    required this.onRestoreGroup,
    required this.onLock,
    required this.onGroupSelected,
  });

  final VaultController controller;
  final bool settingsSelected;
  final VoidCallback onSettings;
  final VoidCallback onBrowse;
  final VoidCallback onNewGroup;
  final void Function(String id, String currentName) onRenameGroup;
  final ValueChanged<String> onMoveGroup;
  final void Function(String id, bool permanent) onDeleteGroup;
  final ValueChanged<String> onRestoreGroup;
  final VoidCallback onLock;
  final VoidCallback onGroupSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = controller.snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 16, 20),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'KeePass Nexus',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'DATABASE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (snapshot != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.storage_outlined, size: 20),
              title: Text(snapshot.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${snapshot.entryCount} entries'),
              onTap: onBrowse,
            ),
          ),
        if (controller.requiresKdbxFormatUpgrade)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Material(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.sourceKdbxVersion?.startsWith('3.') == true
                            ? 'Saving upgrades KDBX ${controller.sourceKdbxVersion} to KDBX 4.1.'
                            : 'Saving upgrades KDBX 4.0 to KDBX 4.1.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ListTile(
          dense: true,
          selected: controller.showFavorites,
          leading: const Icon(Icons.star_outline, size: 19),
          title: const Text('Favorites'),
          onTap: () {
            onBrowse();
            controller.selectFavorites();
          },
        ),
        ListTile(
          dense: true,
          selected: controller.showRecent,
          leading: const Icon(Icons.history, size: 19),
          title: const Text('Recently viewed'),
          onTap: () {
            onBrowse();
            controller.selectRecent();
          },
        ),
        if (controller.availableTags.isNotEmpty)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            leading: const Icon(Icons.sell_outlined, size: 19),
            title: const Text('Tags'),
            children: [
              for (final tag in controller.availableTags)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 48, right: 12),
                  selected: controller.selectedTag == tag,
                  title: Text(tag),
                  onTap: () {
                    onBrowse();
                    controller.selectTag(tag);
                  },
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'GROUPS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'New group',
                visualDensity: VisualDensity.compact,
                onPressed: onNewGroup,
                icon: const Icon(Icons.create_new_folder_outlined, size: 19),
              ),
            ],
          ),
        ),
        if (snapshot != null)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _GroupTreeTile(
                  group: snapshot.root,
                  depth: 0,
                  selectedId: controller.selectedGroupId,
                  onRename: onRenameGroup,
                  onMove: onMoveGroup,
                  onDelete: onDeleteGroup,
                  onRestore: onRestoreGroup,
                  inRecycleBin: false,
                  isRoot: true,
                  onSelect: (id) {
                    onBrowse();
                    onGroupSelected();
                    controller.selectGroup(id);
                  },
                ),
              ],
            ),
          )
        else
          const Spacer(),
        const Divider(height: 1),
        ListTile(
          selected: settingsSelected,
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: onSettings,
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Lock database'),
          onTap: onLock,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
          child: Text(
            controller.filePath?.split(r'\').last ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupTreeTile extends StatelessWidget {
  const _GroupTreeTile({
    required this.group,
    required this.depth,
    required this.selectedId,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    required this.onRestore,
    required this.inRecycleBin,
    required this.isRoot,
    required this.onSelect,
  });

  final rust_api.GroupNode group;
  final int depth;
  final String? selectedId;
  final void Function(String id, String currentName) onRename;
  final ValueChanged<String> onMove;
  final void Function(String id, bool permanent) onDelete;
  final ValueChanged<String> onRestore;
  final bool inRecycleBin;
  final bool isRoot;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = selectedId == group.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 14.0),
          child: ListTile(
            dense: true,
            selected: selected,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            leading: Icon(
              selected ? Icons.folder_open_outlined : Icons.folder_outlined,
              size: 19,
            ),
            title: Text(group.name.isEmpty ? 'Root' : group.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${group.entries.length}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (!isRoot && !group.isRecycleBin)
                  PopupMenuButton<String>(
                    tooltip: 'Group actions',
                    onSelected: (action) {
                      if (action == 'rename') onRename(group.id, group.name);
                      if (action == 'move') onMove(group.id);
                      if (action == 'restore') onRestore(group.id);
                      if (action == 'trash') onDelete(group.id, false);
                      if (action == 'permanent') onDelete(group.id, true);
                    },
                    itemBuilder: (_) => [
                      if (inRecycleBin) ...[
                        if (group.parentIsRecycleBin)
                          const PopupMenuItem(
                            value: 'restore',
                            child: Text('Restore'),
                          ),
                        const PopupMenuItem(
                          value: 'permanent',
                          child: Text('Delete permanently'),
                        ),
                      ] else ...[
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        const PopupMenuItem(value: 'move', child: Text('Move')),
                        const PopupMenuItem(
                          value: 'trash',
                          child: Text('Move to recycle bin'),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
            onTap: () => onSelect(group.id),
          ),
        ),
        for (final child in group.groups)
          _GroupTreeTile(
            group: child,
            depth: depth + 1,
            selectedId: selectedId,
            onRename: onRename,
            onMove: onMove,
            onDelete: onDelete,
            onRestore: onRestore,
            inRecycleBin: inRecycleBin || group.isRecycleBin,
            isRoot: false,
            onSelect: onSelect,
          ),
      ],
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.controller,
    required this.search,
    required this.settingsSelected,
    required this.onSearch,
    required this.onNewEntry,
    required this.onSave,
  });

  final VaultController controller;
  final TextEditingController search;
  final bool settingsSelected;
  final ValueChanged<String> onSearch;
  final VoidCallback onNewEntry;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 15, 24, 15),
      child: Row(
        children: [
          Text(
            settingsSelected
                ? 'Settings'
                : controller.searchQuery.isNotEmpty
                    ? 'Search results'
                    : controller.showFavorites
                        ? 'Favorites'
                        : controller.showRecent
                            ? 'Recently viewed'
                            : controller.selectedTag != null
                                ? 'Tag: ${controller.selectedTag}'
                                : controller.snapshot?.name ?? 'Database',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: search,
                onChanged: onSearch,
                decoration: InputDecoration(
                  hintText: 'Search passwords and notes',
                  prefixIcon: const Icon(Icons.search, size: 21),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            search.clear();
                            onSearch('');
                          },
                          icon: const Icon(Icons.close, size: 18),
                        ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          if (controller.isDirty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'Unsaved changes',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: controller.isDirty ? onSave : null,
            icon: const Icon(Icons.save_outlined, size: 19),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: settingsSelected ? null : onNewEntry,
            icon: const Icon(Icons.add, size: 19),
            label: const Text('New entry'),
          ),
        ],
      ),
    );
  }
}

class _EntryBrowser extends StatelessWidget {
  const _EntryBrowser({
    required this.controller,
    required this.onEdit,
    required this.onDelete,
    required this.onClone,
    required this.onToggleFavorite,
    required this.onHistory,
    required this.onRestore,
  });

  final VaultController controller;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onClone;
  final void Function(String id, bool favorite) onToggleFavorite;
  final ValueChanged<String> onHistory;
  final ValueChanged<String> onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = controller.visibleEntries;
    final selected =
        entries.where((entry) => entry.id == controller.selectedEntryId);
    final selectedEntry = selected.isEmpty ? null : selected.first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 20, 26, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.searchQuery.isEmpty
                            ? '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}'
                            : '${entries.length} results for "${controller.searchQuery}"',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Icon(Icons.sort, size: 18),
                    const SizedBox(width: 6),
                    Text('Title', style: theme.textTheme.labelLarge),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? _EmptyEntries(
                        searching: controller.searchQuery.isNotEmpty)
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          indent: 26,
                          endIndent: 20,
                        ),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final isSelected =
                              entry.id == controller.selectedEntryId;
                          return Material(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.5)
                                : Colors.transparent,
                            child: InkWell(
                              onTap: () => controller.selectEntry(entry.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 26,
                                  vertical: 13,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme.secondaryContainer,
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: _entryIcon(
                                        context,
                                        iconData: entry.iconData,
                                        iconId: entry.iconId,
                                        size: 21,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.title.isEmpty
                                                ? 'Untitled'
                                                : entry.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            entry.username.isEmpty
                                                ? entry.url
                                                : entry.username,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        entry.url,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: entry.favorite
                                          ? 'Remove from favorites'
                                          : 'Add to favorites',
                                      onPressed: () => onToggleFavorite(
                                        entry.id,
                                        !entry.favorite,
                                      ),
                                      icon: Icon(
                                        entry.favorite
                                            ? Icons.star
                                            : Icons.star_outline,
                                        size: 19,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 330,
          child: selectedEntry == null
              ? _EntryPlaceholder()
              : _EntryDetailsPanel(
                  key: ValueKey('${selectedEntry.id}:${controller.revision}'),
                  entry: selectedEntry,
                  controller: controller,
                  onEdit: () => onEdit(selectedEntry.id),
                  onDelete: () => onDelete(selectedEntry.id),
                  onClone: () => onClone(selectedEntry.id),
                  onToggleFavorite: (favorite) =>
                      onToggleFavorite(selectedEntry.id, favorite),
                  onHistory: () => onHistory(selectedEntry.id),
                  onRestore: () => onRestore(selectedEntry.id),
                  inRecycleBin: controller
                      .isGroupDirectlyInRecycleBin(selectedEntry.groupId),
                ),
        ),
      ],
    );
  }
}

class _EntryDetailsPanel extends StatefulWidget {
  const _EntryDetailsPanel({
    required this.entry,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
    required this.onClone,
    required this.onToggleFavorite,
    required this.onHistory,
    required this.onRestore,
    required this.inRecycleBin,
    super.key,
  });

  final rust_api.EntrySummary entry;
  final VaultController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClone;
  final ValueChanged<bool> onToggleFavorite;
  final VoidCallback onHistory;
  final VoidCallback onRestore;
  final bool inRecycleBin;

  @override
  State<_EntryDetailsPanel> createState() => _EntryDetailsPanelState();
}

class _EntryDetailsPanelState extends State<_EntryDetailsPanel> {
  late Future<rust_api.EntryDetails> _details;
  bool _revealPassword = false;
  final Set<String> _revealedCustomFields = {};

  @override
  void initState() {
    super.initState();
    _details = widget.controller.readEntry(widget.entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<rust_api.EntryDetails>(
      future: _details,
      builder: (context, snapshot) {
        final details = snapshot.data;
        if (snapshot.hasError) {
          return Center(child: Text('Unable to read entry: ${snapshot.error}'));
        }
        if (details == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 25, 22, 22),
          children: [
            Row(
              children: [
                _entryIcon(
                  context,
                  iconData: details.iconData,
                  iconId: details.iconId,
                  size: 27,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    details.title.isEmpty ? 'Untitled' : details.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Entry actions',
                  onSelected: (action) {
                    if (action == 'edit') widget.onEdit();
                    if (action == 'delete') widget.onDelete();
                    if (action == 'clone') widget.onClone();
                    if (action == 'history') widget.onHistory();
                    if (action == 'restore') widget.onRestore();
                    if (action == 'favorite') {
                      widget.onToggleFavorite(!details.favorite);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'edit', child: Text('Edit entry')),
                    const PopupMenuItem(
                        value: 'clone', child: Text('Duplicate entry')),
                    PopupMenuItem(
                      value: 'favorite',
                      child: Text(details.favorite
                          ? 'Remove from favorites'
                          : 'Add to favorites'),
                    ),
                    if (details.historyCount > BigInt.zero)
                      const PopupMenuItem(
                        value: 'history',
                        child: Text('View history'),
                      ),
                    if (widget.inRecycleBin)
                      const PopupMenuItem(
                          value: 'restore', child: Text('Restore')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(widget.inRecycleBin
                          ? 'Delete permanently'
                          : 'Move to recycle bin'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _DetailField(label: 'USERNAME', value: details.username),
            _DetailField(
              label: 'PASSWORD',
              value: _revealPassword ? details.password : '••••••••••••',
              trailing: IconButton(
                tooltip: _revealPassword ? 'Hide password' : 'Reveal password',
                onPressed: () =>
                    setState(() => _revealPassword = !_revealPassword),
                icon: Icon(
                  _revealPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
              ),
            ),
            _DetailField(label: 'URL', value: details.url),
            if (details.tags.isNotEmpty)
              _DetailField(label: 'TAGS', value: details.tags.join(' ')),
            if (details.expires || details.expiresAt != null)
              _DetailField(
                label: 'EXPIRES',
                value: details.expiresAt == null
                    ? (details.expires ? 'Enabled' : 'Disabled')
                    : _formatEntryExpiry(
                        context,
                        details.expiresAt!,
                        enabled: details.expires,
                      ),
              ),
            _DetailField(label: 'NOTES', value: details.notes),
            for (final field in details.customFields)
              _DetailField(
                label: field.name.toUpperCase(),
                value: field.protected &&
                        !_revealedCustomFields.contains(field.name)
                    ? '••••••••••'
                    : field.value,
                trailing: field.protected
                    ? IconButton(
                        tooltip: _revealedCustomFields.contains(field.name)
                            ? 'Hide value'
                            : 'Reveal value',
                        onPressed: () => setState(() {
                          if (!_revealedCustomFields.add(field.name)) {
                            _revealedCustomFields.remove(field.name);
                          }
                        }),
                        icon: Icon(
                          _revealedCustomFields.contains(field.name)
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                      )
                    : null,
              ),
            if (details.attachments.isNotEmpty) ...[
              const Divider(),
              Text('ATTACHMENTS', style: theme.textTheme.labelSmall),
              for (final attachment in details.attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(attachment.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${attachment.data.length} bytes'),
                  trailing: IconButton(
                    tooltip: 'Save attachment',
                    onPressed: () => _saveAttachment(context, attachment),
                    icon: const Icon(Icons.download_outlined),
                  ),
                ),
            ],
            if (details.historyCount > BigInt.zero)
              OutlinedButton.icon(
                onPressed: widget.onHistory,
                icon: const Icon(Icons.history),
                label: Text('History (${details.historyCount})'),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit entry'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveAttachment(
    BuildContext context,
    rust_api.EntryAttachment attachment,
  ) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save attachment',
      fileName: attachment.name,
    );
    if (path == null) return;
    try {
      await File(path).writeAsBytes(attachment.data, flush: true);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save attachment: $error')),
      );
    }
  }
}

String _formatEntryExpiry(
  BuildContext context,
  String timestamp, {
  required bool enabled,
}) {
  final expiry = DateTime.tryParse(timestamp);
  if (expiry == null) return timestamp;
  final localizations = MaterialLocalizations.of(context);
  return '${enabled ? '' : 'Disabled · '}${localizations.formatMediumDate(expiry.toLocal())} · '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(expiry.toLocal()))}';
}

Widget _entryIcon(
  BuildContext context, {
  required List<int> iconData,
  required int? iconId,
  required double size,
}) {
  final theme = Theme.of(context);
  if (iconData.isNotEmpty) {
    return Image.memory(
      Uint8List.fromList(iconData),
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: 128,
      cacheHeight: 128,
      errorBuilder: (_, __, ___) => Icon(
        entryIconPreset(iconId).icon,
        size: size,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    );
  }
  return Icon(
    entryIconPreset(iconId).icon,
    size: size,
    color: theme.colorScheme.onSecondaryContainer,
  );
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.9,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value.isEmpty ? '—' : value,
                  maxLines: label == 'NOTES' ? 5 : 2,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.password_outlined,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text('Select an entry', style: theme.textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              'Choose an item to view its details.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.search_off : Icons.key_off_outlined,
            size: 42,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            searching ? 'No matching entries' : 'This group is empty',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            searching
                ? 'Try another title, username, URL, or note.'
                : 'Add an entry to keep your credentials organized.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog({
    this.title = 'Create group',
    this.actionLabel = 'Create group',
    this.initialName = '',
  });

  final String title;
  final String actionLabel;
  final String initialName;

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _name,
          autofocus: true,
          onSubmitted: (_) {
            if (_name.text.trim().isNotEmpty) {
              Navigator.pop(context, _name.text.trim());
            }
          },
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _name.text.trim()),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _GroupDestinationDialog extends StatelessWidget {
  const _GroupDestinationDialog({required this.groups});

  final List<rust_api.GroupNode> groups;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Move group'),
      content: SizedBox(
        width: 360,
        height: 360,
        child: ListView(
          children: [
            for (final group in groups)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(group.name.isEmpty ? 'Root' : group.name),
                onTap: () => Navigator.pop(context, group.id),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
