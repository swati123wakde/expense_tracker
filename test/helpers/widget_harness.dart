import 'package:expense_manager/app/expense_app.dart';
import 'package:expense_manager/features/common/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_harness.dart';

/// Boots the real app (all providers, real SQLite) inside a widget test.
Future<TestEnv> pumpExpenseApp(
  WidgetTester tester, {
  Future<void> Function(TestEnv env)? seed,
}) async {
  Skeleton.animate = false;
  tester.view.physicalSize = const Size(480, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late TestEnv env;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    if (seed != null) await seed(env);
  });
  final settings = (await tester.runAsync(() => env.deps.settings.load()))!;

  await tester.pumpWidget(
    ExpenseApp(deps: env.deps, initialSettings: settings, startBackgroundServices: false),
  );
  await settle(tester);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(env.dispose);
  });
  return env;
}

/// Lets database futures and animations complete.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
