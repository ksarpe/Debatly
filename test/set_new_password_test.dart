import 'package:debatly/features/account/screens/set_new_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The sheet that finishes a password recovery.
///
/// It is the last step of the only flow that can rescue an email/password
/// account, so what matters is that it renders its copy from ARB and that a
/// mistyped or too-short password is caught HERE — a failed `updateUser` burns
/// the one-time recovery session, and the link cannot be reused.
void main() {
  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SetNewPasswordCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the recovery copy and both password fields', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(find.text('USTAW NOWE HASŁO'), findsOneWidget);
    expect(find.text('NOWE HASŁO'), findsOneWidget);
    expect(find.text('POWTÓRZ HASŁO'), findsOneWidget);
    expect(find.text('ZAPISZ NOWE HASŁO'), findsOneWidget);
  });

  testWidgets('a mismatched confirmation is refused before any network call', (
    tester,
  ) async {
    await pumpCard(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'sekret123');
    await tester.enterText(fields.at(1), 'sekret124');
    await tester.tap(find.text('ZAPISZ NOWE HASŁO'));
    await tester.pumpAndSettle();

    expect(find.text('Hasła nie są takie same.'), findsOneWidget);
  });

  testWidgets('a password under six characters is refused', (tester) async {
    await pumpCard(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'krót');
    await tester.enterText(fields.at(1), 'krót');
    await tester.tap(find.text('ZAPISZ NOWE HASŁO'));
    await tester.pumpAndSettle();

    expect(find.text('Minimum 6 znaków.'), findsOneWidget);
  });
}
