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
    await tester.tap(find.text('Create entry'));
    await tester.pumpAndSettle();

    expect(result?.iconId, 1);
    expect(result?.iconData, isEmpty);
  });
}
