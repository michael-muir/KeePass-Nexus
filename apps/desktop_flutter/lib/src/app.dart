import 'dart:async';

import 'package:flutter/material.dart';
import 'package:keeppass_nexus/src/rust/api.dart' as rust_api;
import 'package:keeppass_nexus/src/screens/entry_editor_dialog.dart';
import 'package:keeppass_nexus/src/screens/settings_screen.dart';
import 'package:keeppass_nexus/src/screens/unlock_screen.dart';
import 'package:keeppass_nexus/src/theme.dart';
import 'package:keeppass_nexus/src/vault_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeePassNexusApp extends StatefulWidget {
  const KeePassNexusApp({super.key});

  @override
  State<KeePassNexusApp> createState() => _KeePassNexusAppState();
}

class _KeePassNexusAppState extends State<KeePassNexusApp> {
  final _vault = VaultController();
  ThemeMode _themeMode = ThemeMode.system;
  int _autoLockMinutes = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
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
      await widget.controller.save();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This entry will be removed from the database.'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.deleteEntry(id);
    } catch (error) {
      _showError(error);
    }
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
    required this.onLock,
    required this.onGroupSelected,
  });

  final VaultController controller;
  final bool settingsSelected;
  final VoidCallback onSettings;
  final VoidCallback onBrowse;
  final VoidCallback onNewGroup;
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
    required this.onSelect,
  });

  final rust_api.GroupNode group;
  final int depth;
  final String? selectedId;
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
            trailing: Text(
              '${group.entries.length}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            onTap: () => onSelect(group.id),
          ),
        ),
        for (final child in group.groups)
          _GroupTreeTile(
            group: child,
            depth: depth + 1,
            selectedId: selectedId,
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
  });

  final VaultController controller;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDelete;

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
                                      child: Icon(
                                        Icons.key_outlined,
                                        size: 19,
                                        color: theme
                                            .colorScheme.onSecondaryContainer,
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
    super.key,
  });

  final rust_api.EntrySummary entry;
  final VaultController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_EntryDetailsPanel> createState() => _EntryDetailsPanelState();
}

class _EntryDetailsPanelState extends State<_EntryDetailsPanel> {
  late Future<rust_api.EntryDetails> _details;
  bool _revealPassword = false;

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
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit entry')),
                    PopupMenuItem(value: 'delete', child: Text('Delete entry')),
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
            _DetailField(label: 'NOTES', value: details.notes),
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
  const _NewGroupDialog();

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create group'),
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
          child: const Text('Create group'),
        ),
      ],
    );
  }
}
