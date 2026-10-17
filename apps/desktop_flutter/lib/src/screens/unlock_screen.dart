import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:keeppass_nexus/src/theme.dart';
import 'package:keeppass_nexus/src/vault_controller.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({required this.controller, super.key});

  final VaultController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  String? _databasePath;
  String? _keyFilePath;
  String? _error;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _chooseDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['kdbx'],
      allowMultiple: false,
    );
    if (!mounted || result == null || result.files.single.path == null) return;
    setState(() {
      _databasePath = result.files.single.path;
      _error = null;
    });
  }

  Future<void> _chooseKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['key', 'keyx', 'xml'],
      allowMultiple: false,
    );
    if (!mounted || result == null || result.files.single.path == null) return;
    setState(() {
      _keyFilePath = result.files.single.path;
      _error = null;
    });
  }

  Future<void> _unlock() async {
    final path = _databasePath;
    if (path == null) {
      setState(() => _error = 'Choose a KDBX database to continue.');
      return;
    }
    if (_password.text.isEmpty && _keyFilePath == null) {
      setState(() => _error = 'Enter a master password or select a key file.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.openVault(
        path: path,
        password: _password.text,
        keyFilePath: _keyFilePath,
      );
      _password.clear();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createVault() async {
    final values = await showDialog<({String name, String password})>(
      context: context,
      builder: (context) => const _CreateVaultDialog(),
    );
    if (!mounted || values == null) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Create a KeePass database',
      fileName: '${values.name}.kdbx',
      type: FileType.custom,
      allowedExtensions: const ['kdbx'],
    );
    if (!mounted || path == null) return;
    final databasePath =
        path.toLowerCase().endsWith('.kdbx') ? path : '$path.kdbx';

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.createVault(
        path: databasePath,
        name: values.name,
        password: values.password,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.toLowerCase().contains('password') ||
        message.toLowerCase().contains('key')) {
      return 'The database could not be unlocked. Check the password and key file.';
    }
    return message.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -130,
            left: -120,
            child: _GlowCircle(color: accentColor.withValues(alpha: 0.09)),
          ),
          Positioned(
            bottom: -190,
            right: -120,
            child: _GlowCircle(
                color: theme.colorScheme.primary.withValues(alpha: 0.06)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BrandMark(large: true),
                    const SizedBox(height: 34),
                    Text(
                      'Your passwords,\\nyour control.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Open your KeePass database to get started.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _chooseDatabase,
                              icon: const Icon(Icons.folder_open_outlined),
                              label: Text(
                                _databasePath == null
                                    ? 'Choose database file'
                                    : _databasePath!.split(r'\').last,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                            if (_databasePath != null) ...[
                              const SizedBox(height: 16),
                              TextField(
                                controller: _password,
                                obscureText: !_showPassword,
                                autofocus: true,
                                onSubmitted: (_) => _unlock(),
                                decoration: InputDecoration(
                                  labelText: 'Master password',
                                  prefixIcon: const Icon(Icons.key_outlined),
                                  suffixIcon: IconButton(
                                    tooltip: _showPassword
                                        ? 'Hide password'
                                        : 'Show password',
                                    onPressed: () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _busy ? null : _chooseKeyFile,
                                  icon: const Icon(Icons.attach_file, size: 18),
                                  label: Text(
                                    _keyFilePath == null
                                        ? 'Add a key file (optional)'
                                        : 'Key file selected',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _busy ? null : _unlock,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: _busy
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Unlock database'),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: _busy ? null : _createVault,
                      icon: const Icon(Icons.add),
                      label: const Text('Create a new database'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your vault stays encrypted on your device.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateVaultDialog extends StatefulWidget {
  const _CreateVaultDialog();

  @override
  State<_CreateVaultDialog> createState() => _CreateVaultDialogState();
}

class _CreateVaultDialogState extends State<_CreateVaultDialog> {
  final _name = TextEditingController(text: 'My Passwords');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _visible = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _continue() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name for your database.');
      return;
    }
    if (_password.text.length < 8) {
      setState(() =>
          _error = 'Choose a master password with at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    Navigator.of(context).pop((
      name: _name.text.trim(),
      password: _password.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a database'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Database name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_visible,
              decoration: InputDecoration(
                labelText: 'Master password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _visible = !_visible),
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: !_visible,
              onSubmitted: (_) => _continue(),
              decoration: const InputDecoration(labelText: 'Confirm password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _continue,
          child: const Text('Choose file location'),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 38.0;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(large ? 18 : 12),
            ),
            child: Icon(
              Icons.shield_outlined,
              size: large ? 36 : 22,
              color: Colors.white,
            ),
          ),
          SizedBox(width: large ? 14 : 12),
          Text(
            'KeePass Nexus',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: large ? 24 : 18,
                ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 420,
        height: 420,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      );
}
