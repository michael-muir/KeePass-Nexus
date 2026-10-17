import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keeppass_nexus/src/screens/entry_editor_dialog.dart';
import 'package:keeppass_nexus/src/screens/password_generator_dialog.dart';

void main() {
  testWidgets(
      'shows password and passphrase tabs and returns a generated value',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => const PasswordGeneratorDialog(),
                ),
                child: const Text('Open generator'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open generator'));
    await tester.pumpAndSettle();

    expect(find.text('Password generator'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Passphrase'), findsOneWidget);
    expect(find.text('Password quality: Excellent'), findsOneWidget);

    await tester.tap(find.text('Passphrase'));
    await tester.pumpAndSettle();
    expect(find.text('Word count'), findsOneWidget);
    expect(find.text('Word separator'), findsOneWidget);

    await tester.tap(find.text('Use password'));
    await tester.pumpAndSettle();
    expect(find.text('Password generator'), findsNothing);
  });

  testWidgets('the entry password field opens the generator and uses its value',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const EntryEditorDialog(),
                ),
                child: const Text('Open entry'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generate password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use password'));
    await tester.pumpAndSettle();

    final passwordField = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .elementAt(2);
    expect(passwordField.controller!.text, hasLength(20));
  });
}
