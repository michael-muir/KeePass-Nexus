import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keeppass_nexus/src/password_generator.dart';

class PasswordGeneratorDialog extends StatefulWidget {
  const PasswordGeneratorDialog({super.key});

  @override
  State<PasswordGeneratorDialog> createState() =>
      _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _length;
  late final TextEditingController _wordCount;
  late final TextEditingController _separator;
  late final TextEditingController _customCharacters;
  late final TextEditingController _excludedCharacters;
  late final TextEditingController _generatedText;

  final Set<String> _enabledGroups = {
    'Uppercase',
    'Lowercase',
    'Numbers',
    'Common symbols',
  };
  GeneratedPassword? _generated;
  PassphraseWordCase _wordCase = PassphraseWordCase.lowercase;
  bool _excludeLookAlikes = false;
  bool _requireEachGroup = true;
  bool _showPassword = true;
  String? _error;

  int get _passwordLength => int.tryParse(_length.text) ?? 20;
  int get _passphraseWordCount => int.tryParse(_wordCount.text) ?? 13;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    _length = TextEditingController(text: '20');
    _wordCount = TextEditingController(text: '13');
    _separator = TextEditingController(text: '-');
    _customCharacters = TextEditingController();
    _excludedCharacters = TextEditingController();
    _generatedText = TextEditingController();
    _generate();
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    _length.dispose();
    _wordCount.dispose();
    _separator.dispose();
    _customCharacters.dispose();
    _excludedCharacters.dispose();
    _generatedText.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) _generate();
  }

  void _generate() {
    try {
      final generated = _tabs.index == 0
          ? generateCharacterPassword(
              length: _passwordLength,
              enabledGroups: _enabledGroups,
              customCharacters: _customCharacters.text,
              excludedCharacters: _excludedCharacters.text,
              excludeLookAlikes: _excludeLookAlikes,
              requireEachGroup: _requireEachGroup,
            )
          : generatePassphrase(
              wordCount: _passphraseWordCount,
              separator: _separator.text,
              wordCase: _wordCase,
            );
      setState(() {
        _generated = generated;
        _generatedText.text = generated.value;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _generated = null;
        _generatedText.clear();
        _error = error.message;
      });
    }
  }

  void _setLength(String value, {bool fromSlider = false}) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 128) return;
    if (fromSlider) _length.text = value;
    _generate();
  }

  void _setWordCount(String value, {bool fromSlider = false}) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 32) return;
    if (fromSlider) _wordCount.text = value;
    _generate();
  }

  Future<void> _copyPassword() async {
    final generated = _generated;
    if (generated == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: generated.value));
    } on PlatformException catch (error) {
      _showClipboardError(error.message ?? error.code);
      return;
    } on MissingPluginException {
      _showClipboardError('Clipboard support is unavailable.');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generated password copied.')),
    );
  }

  Future<void> _clearClipboard() async {
    final generated = _generated;
    if (generated == null) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == generated.value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            current?.text == generated.value
                ? 'Clipboard cleared.'
                : 'Clipboard was not changed because it no longer contains this password.',
          ),
        ),
      );
    } on PlatformException catch (error) {
      _showClipboardError(error.message ?? error.code);
    } on MissingPluginException {
      _showClipboardError('Clipboard support is unavailable.');
    }
  }

  void _showClipboardError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Clipboard operation failed: $message')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final generated = _generated;
    final height = MediaQuery.sizeOf(context).height;
    return AlertDialog(
      title: const Text('Password generator'),
      content: SizedBox(
        width: 700,
        height: height.clamp(420, 720).toDouble() * 0.78,
        child: Column(
          children: [
            _buildGeneratedPassword(generated),
            const SizedBox(height: 12),
            _buildPasswordFeedback(generated),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabs,
              onTap: (_) => _generate(),
              tabs: const [
                Tab(text: 'Password'),
                Tab(text: 'Passphrase'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildCharacterOptions(),
                  _buildPassphraseOptions(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: generated == null
              ? null
              : () => Navigator.of(context).pop(generated.value),
          icon: const Icon(Icons.check),
          label: const Text('Use password'),
        ),
      ],
    );
  }

  Widget _buildGeneratedPassword(GeneratedPassword? generated) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _generatedText,
            readOnly: true,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Generated password',
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Generate another password',
          onPressed: _generate,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Copy password',
          onPressed: generated == null ? null : _copyPassword,
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          tooltip: 'Clear clipboard',
          onPressed: generated == null ? null : _clearClipboard,
          icon: const Icon(Icons.cleaning_services_outlined),
        ),
      ],
    );
  }

  Widget _buildPasswordFeedback(GeneratedPassword? generated) {
    final entropy = generated?.entropyBits ?? 0;
    final quality = generated?.quality ?? PasswordQuality.weak;
    final fraction = (entropy / 128).clamp(0.0, 1.0);
    final color = switch (quality) {
      PasswordQuality.weak => Theme.of(context).colorScheme.error,
      PasswordQuality.fair => Colors.orange,
      PasswordQuality.good => Colors.amber.shade800,
      PasswordQuality.strong => Colors.lightGreen.shade700,
      PasswordQuality.excellent => Colors.green.shade700,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: fraction,
          color: color,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              'Password quality: ${_qualityLabel(quality)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            Text('Characters: ${generated?.characterCount ?? 0}'),
            Text('Entropy: ${entropy.toStringAsFixed(2)} bit'),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _buildCharacterOptions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCountControl(
            label: 'Length',
            controller: _length,
            value: _passwordLength.clamp(4, 128).toDouble(),
            min: 4,
            max: 128,
            onChanged: (value) =>
                _setLength(value.round().toString(), fromSlider: true),
            onSubmitted: _setLength,
          ),
          const SizedBox(height: 8),
          Text(
            'Character types',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final name in passwordCharacterGroups.keys)
                FilterChip(
                  label: Text(_characterGroupLabel(name)),
                  selected: _enabledGroups.contains(name),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _enabledGroups.add(name);
                      } else {
                        _enabledGroups.remove(name);
                      }
                    });
                    _generate();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customCharacters,
            onChanged: (_) => _generate(),
            decoration: const InputDecoration(
              labelText: 'Also choose from',
              hintText: 'Additional characters',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _excludedCharacters,
            onChanged: (_) => _generate(),
            decoration: const InputDecoration(
              labelText: 'Do not include',
              hintText: 'Characters to exclude',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exclude look-alike characters (0, O, 1, l, I)'),
            value: _excludeLookAlikes,
            onChanged: (value) {
              setState(() => _excludeLookAlikes = value ?? false);
              _generate();
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pick at least one character from every group'),
            value: _requireEachGroup,
            onChanged: (value) {
              setState(() => _requireEachGroup = value ?? false);
              _generate();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPassphraseOptions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Word list'),
            child: Text('Built-in English words ($passphraseWordListSize)'),
          ),
          const SizedBox(height: 12),
          _buildCountControl(
            label: 'Word count',
            controller: _wordCount,
            value: _passphraseWordCount.clamp(3, 32).toDouble(),
            min: 3,
            max: 32,
            onChanged: (value) =>
                _setWordCount(value.round().toString(), fromSlider: true),
            onSubmitted: _setWordCount,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _separator,
            onChanged: (_) => _generate(),
            decoration: const InputDecoration(
              labelText: 'Word separator',
              hintText: 'For example: -',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PassphraseWordCase>(
            initialValue: _wordCase,
            decoration: const InputDecoration(labelText: 'Word case'),
            items: const [
              DropdownMenuItem(
                value: PassphraseWordCase.lowercase,
                child: Text('lowercase'),
              ),
              DropdownMenuItem(
                value: PassphraseWordCase.uppercase,
                child: Text('UPPERCASE'),
              ),
              DropdownMenuItem(
                value: PassphraseWordCase.titleCase,
                child: Text('Title Case'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _wordCase = value);
              _generate();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCountControl({
    required String label,
    required TextEditingController controller,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<String> onSubmitted,
  }) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 78,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: onSubmitted,
            onSubmitted: onSubmitted,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  String _qualityLabel(PasswordQuality quality) => switch (quality) {
        PasswordQuality.weak => 'Weak',
        PasswordQuality.fair => 'Fair',
        PasswordQuality.good => 'Good',
        PasswordQuality.strong => 'Strong',
        PasswordQuality.excellent => 'Excellent',
      };

  String _characterGroupLabel(String name) => switch (name) {
        'Uppercase' => 'A-Z',
        'Lowercase' => 'a-z',
        'Numbers' => '0-9',
        _ => passwordCharacterGroups[name]!,
      };
}
