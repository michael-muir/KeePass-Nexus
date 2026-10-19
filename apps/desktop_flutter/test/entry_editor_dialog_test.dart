import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keeppass_nexus/src/rust/api.dart';
import 'package:keeppass_nexus/src/screens/entry_editor_dialog.dart';

void main() {
  testWidgets('selects a built-in icon for a new entry', (tester) async {
    EntryInput? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<EntryInput>(
                  context: context,
                  builder: (_) => const EntryEditorDialog(),
                );
              },
              child: const Text('Open entry'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Icon'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('World'));
    await tester.tap(find.text('Entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Example');
    await tester.ensureVisible(find.byType(TextFormField).at(4));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(4),
      'work   email  personal',
    );
    await tester.tap(find.text('Create entry'));
    await tester.pumpAndSettle();

    expect(result?.iconId, 1);
    expect(result?.iconData, isEmpty);
    expect(result?.tags, ['work', 'email', 'personal']);
    expect(result?.expires, isFalse);
    expect(DateTime.tryParse(result?.expiresAt ?? ''), isNotNull);
  });

  testWidgets('expiration presets set an exact two-week expiry',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    EntryInput? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<EntryInput>(
                  context: context,
                  builder: (_) => const EntryEditorDialog(),
                );
              },
              child: const Text('Open entry'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Example');
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      200,
      scrollable: find
          .descendant(
              of: find.byType(Dialog), matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    final presets =
        find.byWidgetPredicate((widget) => widget is DropdownButtonFormField);
    await tester.ensureVisible(presets);
    await tester.pumpAndSettle();
    await tester.tap(presets);
    await tester.pumpAndSettle();
    final selectedAt = DateTime.now().toUtc();
    await tester.tap(find.text('2 weeks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create entry'));
    await tester.pumpAndSettle();

    expect(result?.expires, isTrue);
    final expiresAt = DateTime.parse(result!.expiresAt!).toUtc();
    expect(
      expiresAt.difference(selectedAt).inSeconds,
      closeTo(const Duration(days: 14).inSeconds, 2),
    );
  });
}
