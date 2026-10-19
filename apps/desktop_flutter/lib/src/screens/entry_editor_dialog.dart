import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:keeppass_nexus/src/entry_icons.dart';
import 'package:keeppass_nexus/src/rust/api.dart';
import 'package:keeppass_nexus/src/screens/password_generator_dialog.dart';

const _maxIconBytes = 1024 * 1024;

enum _ExpirationUnit { hours, days, weeks, months, years }

class _ExpirationPreset {
  const _ExpirationPreset(this.label, this.amount, this.unit);

  final String label;
  final int amount;
  final _ExpirationUnit unit;
}

class _CustomFieldDraft {
  _CustomFieldDraft({
    String name = '',
    String value = '',
    this.protected = false,
  })  : name = TextEditingController(text: name),
        value = TextEditingController(text: value);

  final TextEditingController name;
  final TextEditingController value;
  bool protected;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

const _expirationPresets = [
  _ExpirationPreset('12 hours', 12, _ExpirationUnit.hours),
  _ExpirationPreset('24 hours', 24, _ExpirationUnit.hours),
  _ExpirationPreset('1 week', 1, _ExpirationUnit.weeks),
  _ExpirationPreset('2 weeks', 2, _ExpirationUnit.weeks),
  _ExpirationPreset('3 weeks', 3, _ExpirationUnit.weeks),
  _ExpirationPreset('1 month', 1, _ExpirationUnit.months),
  _ExpirationPreset('2 months', 2, _ExpirationUnit.months),
  _ExpirationPreset('3 months', 3, _ExpirationUnit.months),
  _ExpirationPreset('4 months', 4, _ExpirationUnit.months),
  _ExpirationPreset('5 months', 5, _ExpirationUnit.months),
  _ExpirationPreset('6 months', 6, _ExpirationUnit.months),
  _ExpirationPreset('1 year', 1, _ExpirationUnit.years),
  _ExpirationPreset('2 years', 2, _ExpirationUnit.years),
  _ExpirationPreset('3 years', 3, _ExpirationUnit.years),
];

class EntryEditorDialog extends StatefulWidget {
  const EntryEditorDialog({this.initial, super.key});

  final EntryDetails? initial;

  @override
  State<EntryEditorDialog> createState() => _EntryEditorDialogState();
}

class _EntryEditorDialogState extends State<EntryEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  late final TextEditingController _tags;
  final _formKey = GlobalKey<FormState>();
  final List<_CustomFieldDraft> _customFields = [];
  final List<EntryAttachment> _attachments = [];
  final Set<String> _existingAttachmentNames = {};
  bool _showPassword = false;
  bool _loadingFavicon = false;
  bool _favorite = false;
  int _selectedSection = 0;
  int? _builtinIconId;
  Uint8List? _customIcon;
  bool _expires = false;
  late DateTime _expiresAt;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _username = TextEditingController(text: initial?.username ?? '');
    _password = TextEditingController(text: initial?.password ?? '');
    _url = TextEditingController(text: initial?.url ?? '');
    _notes = TextEditingController(text: initial?.notes ?? '');
    _tags = TextEditingController(text: initial?.tags.join(' ') ?? '');
    _favorite = initial?.favorite ?? false;
    for (final field in initial?.customFields ?? const <CustomField>[]) {
      _customFields.add(_CustomFieldDraft(
        name: field.name,
        value: field.value,
        protected: field.protected,
      ));
    }
    _attachments.addAll(initial?.attachments ?? const <EntryAttachment>[]);
    _existingAttachmentNames.addAll(
      _attachments.map((attachment) => attachment.name.toLowerCase()),
    );
    _expires = initial?.expires ?? false;
    _expiresAt = DateTime.tryParse(initial?.expiresAt ?? '')?.toLocal() ??
        DateTime.now();
    if (initial != null && initial.iconData.isNotEmpty) {
      _customIcon = Uint8List.fromList(initial.iconData);
    } else {
      _builtinIconId = initial?.iconId ?? 0;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    _notes.dispose();
    _tags.dispose();
    for (final field in _customFields) {
      field.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      setState(() => _selectedSection = 0);
      return;
    }
    Navigator.of(context).pop(
      EntryInput(
        title: _title.text.trim(),
        username: _username.text,
        password: _password.text,
        url: _url.text.trim(),
        notes: _notes.text,
        tags: _tags.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((tag) => tag.isNotEmpty)
            .toList(),
        favorite: _favorite,
        expires: _expires,
        expiresAt: _expiresAt.toUtc().toIso8601String(),
        iconId: _customIcon == null ? _builtinIconId : null,
        iconData: _customIcon ?? Uint8List(0),
        customFields: _customFields
            .where((field) => field.name.text.trim().isNotEmpty)
            .map((field) => CustomField(
                  name: field.name.text.trim(),
                  value: field.value.text,
                  protected: field.protected,
                ))
            .toList(),
        attachments: _attachments,
      ),
    );
  }

  Future<void> _generatePassword() async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const PasswordGeneratorDialog(),
    );
    if (password != null && mounted) {
      setState(() => _password.text = password);
    }
  }

  Future<void> _selectExpiry() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _expiresAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _applyExpiryPreset(_ExpirationPreset preset) {
    final now = DateTime.now();
    setState(() {
      _expires = true;
      _expiresAt = switch (preset.unit) {
        _ExpirationUnit.hours => now.add(Duration(hours: preset.amount)),
        _ExpirationUnit.days => now.add(Duration(days: preset.amount)),
        _ExpirationUnit.weeks => now.add(Duration(days: preset.amount * 7)),
        _ExpirationUnit.months => _addCalendarMonths(now, preset.amount),
        _ExpirationUnit.years => _addCalendarMonths(now, preset.amount * 12),
      };
    });
  }

  DateTime _addCalendarMonths(DateTime date, int months) {
    final firstOfMonth = DateTime(
      date.year,
      date.month + months,
      1,
      date.hour,
      date.minute,
      date.second,
    );
    final lastDay = DateTime(
      firstOfMonth.year,
      firstOfMonth.month + 1,
      0,
    ).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(
      firstOfMonth.year,
      firstOfMonth.month,
      day,
      date.hour,
      date.minute,
      date.second,
    );
  }

  Future<void> _pickCustomIcon() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'bmp',
        'ico'
      ],
      withData: true,
    );
    if (selection == null || selection.files.isEmpty) return;

    try {
      final file = selection.files.single;
      final data = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (data == null) {
        throw const FormatException('The selected icon could not be read.');
      }

      final normalized = await _normalizeIcon(Uint8List.fromList(data));
      if (mounted) setState(() => _setCustomIcon(normalized));
    } on Exception catch (error) {
      _showIconError('Unable to use that image: $error');
    }
  }

  Future<void> _pickAttachment() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (selection == null || selection.files.isEmpty) return;
    final file = selection.files.single;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      _showIconError('The selected attachment could not be read.');
      return;
    }
    if (bytes.length > 25 * 1024 * 1024) {
      _showIconError('Attachments must be 25 MB or smaller.');
      return;
    }
    if (_attachments.any(
      (attachment) => attachment.name.toLowerCase() == file.name.toLowerCase(),
    )) {
      _showIconError('An attachment with that filename already exists.');
      return;
    }
    setState(() => _attachments.add(
          EntryAttachment(name: file.name, data: Uint8List.fromList(bytes)),
        ));
  }

  Future<void> _downloadFavicon() async {
    final url = Uri.tryParse(_url.text.trim());
    if (url == null ||
        !url.hasAuthority ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        !const {'http', 'https'}.contains(url.scheme.toLowerCase())) {
      _showIconError('Enter a valid website URL first.');
      return;
    }

    setState(() => _loadingFavicon = true);
    try {
      Uint8List? normalized;
      Exception? lastError;
      for (final path in const [
        '/favicon.ico',
        '/favicon.png',
        '/apple-touch-icon.png',
      ]) {
        try {
          final iconUrl = url.replace(path: path, query: null, fragment: null);
          normalized = await _normalizeIcon(await _fetchFavicon(iconUrl));
          break;
        } on Exception catch (error) {
          lastError = error;
        }
      }
      if (normalized == null) {
        throw lastError ??
            const HttpException('The website does not provide a favicon.');
      }
      final icon = normalized;
      if (mounted) {
        setState(() => _setCustomIcon(icon));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favicon added as the entry icon.')),
        );
      }
    } on Exception catch (error) {
      _showIconError('Unable to download the favicon: $error');
    } finally {
      if (mounted) setState(() => _loadingFavicon = false);
    }
  }

  void _setCustomIcon(Uint8List icon) {
    _customIcon = icon;
    _builtinIconId = null;
  }

  Future<Uint8List> _fetchFavicon(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    client.autoUncompress = true;
    try {
      for (var redirects = 0; redirects <= 3; redirects++) {
        final request = await client.getUrl(uri).timeout(
              const Duration(seconds: 8),
            );
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'image/*');
        final response = await request.close().timeout(
              const Duration(seconds: 8),
            );

        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null || redirects == 3) {
            throw const HttpException(
                'The favicon URL redirected too many times.');
          }
          final redirected = uri.resolve(location);
          if (!redirected.hasAuthority ||
              redirected.host.isEmpty ||
              redirected.userInfo.isNotEmpty ||
              !const {'http', 'https'}
                  .contains(redirected.scheme.toLowerCase())) {
            throw const HttpException('The favicon redirect URL is invalid.');
          }
          uri = redirected;
          continue;
        }

        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw HttpException(
            'The server returned HTTP ${response.statusCode}.',
          );
        }
        final contentType = response.headers.contentType?.mimeType ?? '';
        if (!contentType.startsWith('image/') &&
            !const {
              'application/octet-stream',
              'application/x-icon',
              'application/vnd.microsoft.icon',
            }.contains(contentType)) {
          await response.drain<void>();
          throw const HttpException('The website did not return an image.');
        }
        final length = response.contentLength;
        if (length > _maxIconBytes) {
          await response.drain<void>();
          throw const HttpException('The favicon is larger than 1 MB.');
        }
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk
            in response.timeout(const Duration(seconds: 8))) {
          received += chunk.length;
          if (received > _maxIconBytes) {
            throw const HttpException('The favicon is larger than 1 MB.');
          }
          builder.add(chunk);
        }
        if (received == 0) {
          throw const HttpException('The website returned an empty favicon.');
        }
        return builder.takeBytes();
      }
      throw const HttpException('Unable to follow the favicon redirect.');
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _normalizeIcon(Uint8List data) async {
    if (data.isEmpty || data.lengthInBytes > _maxIconBytes) {
      throw const FormatException('Choose an image smaller than 1 MB.');
    }
    data = _pngFromIco(data) ?? data;
    final codec = await ui.instantiateImageCodec(
      data,
      targetWidth: 256,
      targetHeight: 256,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final png =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null || png.lengthInBytes > _maxIconBytes) {
          throw const FormatException('The image could not be converted.');
        }
        return Uint8List.view(
          png.buffer,
          png.offsetInBytes,
          png.lengthInBytes,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Uint8List? _pngFromIco(Uint8List data) {
    if (data.lengthInBytes < 6) return null;
    final header = ByteData.sublistView(data);
    if (header.getUint16(0, Endian.little) != 0 ||
        header.getUint16(2, Endian.little) != 1) {
      return null;
    }

    final count = header.getUint16(4, Endian.little);
    for (var index = 0; index < count; index++) {
      final entryOffset = 6 + index * 16;
      if (entryOffset + 16 > data.lengthInBytes) break;
      final imageLength = header.getUint32(entryOffset + 8, Endian.little);
      final imageOffset = header.getUint32(entryOffset + 12, Endian.little);
      if (imageLength < 8 || imageOffset + imageLength > data.lengthInBytes) {
        continue;
      }
      final image = Uint8List.sublistView(
        data,
        imageOffset,
        imageOffset + imageLength,
      );
      if (image[0] == 0x89 &&
          image[1] == 0x50 &&
          image[2] == 0x4e &&
          image[3] == 0x47) {
        return image;
      }
    }
    return null;
  }

  void _showIconError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      child: SizedBox(
        width: screen.width < 880 ? screen.width - 40 : 840,
        height: screen.height < 680
            ? screen.height - 40
            : screen.height > 900
                ? 820
                : 640,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      editing ? 'Edit entry' : 'New entry',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 144,
                    child: Column(
                      children: [
                        _sectionButton(
                          index: 0,
                          label: 'Entry',
                          icon: Icons.edit_outlined,
                        ),
                        _sectionButton(
                          index: 1,
                          label: 'Icon',
                          icon: Icons.insert_emoticon_outlined,
                        ),
                        _sectionButton(
                          index: 2,
                          label: 'Advanced',
                          icon: Icons.tune_outlined,
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedSection,
                      children: [
                        _entryFields(),
                        _iconPicker(),
                        _advancedFields(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: Text(editing ? 'Save changes' : 'Create entry'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionButton({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final selected = index == _selectedSection;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
      child: Material(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _selectedSection = index),
          child: SizedBox(
            height: 76,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon),
                const SizedBox(height: 6),
                Text(label, style: theme.textTheme.labelLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryFields() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Title is required'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Generate password',
                      onPressed: _generatePassword,
                      icon: const Icon(Icons.auto_awesome_outlined),
                    ),
                    IconButton(
                      tooltip:
                          _showPassword ? 'Hide password' : 'Show password',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ],
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 96,
                  minHeight: 48,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: _loadingFavicon ? null : _downloadFavicon,
                  icon: _loadingFavicon
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(_loadingFavicon ? 'Downloading' : 'Favicon'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'Separate tags with spaces',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Favorite'),
              secondary: const Icon(Icons.star_outline),
              value: _favorite,
              onChanged: (value) => setState(() => _favorite = value),
            ),
            const SizedBox(height: 12),
            _expirationFields(),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedFields() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Custom fields',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _customFields.add(_CustomFieldDraft());
              }),
              icon: const Icon(Icons.add),
              label: const Text('Add field'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_customFields.isEmpty)
          Text(
            'Add KeePass-compatible custom fields for this entry.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (var index = 0; index < _customFields.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _customFields[index].name,
                    decoration: const InputDecoration(labelText: 'Field name'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _customFields[index].value,
                    obscureText: _customFields[index].protected,
                    decoration: const InputDecoration(labelText: 'Value'),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Protect value in the database',
                  child: Checkbox(
                    value: _customFields[index].protected,
                    onChanged: (value) => setState(
                      () => _customFields[index].protected = value ?? false,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove custom field',
                  onPressed: () => setState(
                    () => _customFields.removeAt(index).dispose(),
                  ),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(
              child: Text(
                'Attachments',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickAttachment,
              icon: const Icon(Icons.attach_file),
              label: const Text('Add file'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_attachments.isEmpty)
          Text(
            'Files are encrypted inside this database.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (var index = 0; index < _attachments.length; index++)
          ListTile(
            dense: true,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(_attachments[index].name),
            subtitle: Text(
              '${_attachments[index].data.length} bytes',
            ),
            trailing: _existingAttachmentNames
                    .contains(_attachments[index].name.toLowerCase())
                ? const Tooltip(
                    message:
                        'Existing attachments cannot be removed while keeping entry history.',
                    child: Icon(Icons.lock_outline),
                  )
                : IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: () =>
                        setState(() => _attachments.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
          ),
      ],
    );
  }

  Widget _expirationFields() {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final formattedExpiry = '${localizations.formatMediumDate(_expiresAt)} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(_expiresAt))}';
    final menuItems = <DropdownMenuItem<_ExpirationPreset?>>[];
    for (var index = 0; index < _expirationPresets.length; index++) {
      final preset = _expirationPresets[index];
      menuItems.add(
        DropdownMenuItem(
          value: preset,
          child: Text(preset.label),
        ),
      );
      if (index == 1 || index == 4 || index == 10) {
        menuItems.add(
          const DropdownMenuItem<_ExpirationPreset?>(
            value: null,
            enabled: false,
            child: Divider(height: 1),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Expires'),
          value: _expires,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (value) => setState(() => _expires = value ?? false),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _expires ? _selectExpiry : null,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  formattedExpiry,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 155,
              child: DropdownButtonFormField<_ExpirationPreset?>(
                initialValue: null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Presets',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                hint: Text(
                  'Choose',
                  style: theme.textTheme.bodyMedium,
                ),
                items: menuItems,
                onChanged: _expires
                    ? (preset) {
                        if (preset != null) _applyExpiryPreset(preset);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconPicker() {
    final theme = Theme.of(context);
    final selectedIcon = entryIconPreset(_builtinIconId);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose an icon', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              _iconPreview(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _customIcon == null ? selectedIcon.label : 'Custom icon',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickCustomIcon,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Upload'),
              ),
              if (_customIcon != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Remove custom icon',
                  onPressed: () => setState(() {
                    _customIcon = null;
                    _builtinIconId = 0;
                  }),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text('Preselected icons', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              itemCount: entryIconPresets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.12,
              ),
              itemBuilder: (context, index) {
                final preset = entryIconPresets[index];
                final selected =
                    _customIcon == null && _builtinIconId == preset.id;
                return Tooltip(
                  message: preset.label,
                  child: Material(
                    color: selected
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() {
                        _builtinIconId = preset.id;
                        _customIcon = null;
                      }),
                      child: Icon(
                        preset.icon,
                        color: selected
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconPreview({required double size}) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
    );
    if (_customIcon != null) {
      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(5),
        decoration: decoration,
        child: Image.memory(
          _customIcon!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.broken_image_outlined, color: theme.colorScheme.error),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: decoration,
      child: Icon(
        entryIconPreset(_builtinIconId).icon,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    );
  }
}
