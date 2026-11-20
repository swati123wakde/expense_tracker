// Smoke test: the app boots offline from an empty local database straight
// into the dashboard (no login needed for local-only builds).

import 'package:flutter_test/flutter_test.dart';

import 'helpers/widget_harness.dart';

void main() {
  testWidgets('app boots into the dashboard from local data', (tester) async {
    await pumpExpenseApp(tester);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Local only'), findsWidgets);
  });
}
