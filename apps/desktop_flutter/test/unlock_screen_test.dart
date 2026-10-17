import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keeppass_nexus/src/screens/unlock_screen.dart';
import 'package:keeppass_nexus/src/vault_controller.dart';

void main() {
  testWidgets('shows the database unlock and create-vault actions',
      (tester) async {
    final controller = VaultController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: UnlockScreen(controller: controller)),
    );

    expect(find.text('KeePass Nexus'), findsOneWidget);
    expect(find.textContaining('Your passwords'), findsOneWidget);
    expect(find.text('Choose database file'), findsOneWidget);
    expect(find.text('Create a new database'), findsOneWidget);
  });
}
