import 'package:flutter/material.dart';

import 'app/dependencies.dart';
import 'app/expense_app.dart';

/// Startup flow (offline-first):
/// open encrypted local DB → load settings → render dashboard from local data
/// → (after first frame) check connectivity → background sync → merge → refresh.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final deps = await AppDependencies.production();
    final settings = await deps.settings.load();
    runApp(ExpenseApp(deps: deps, initialSettings: settings));
  } catch (e, st) {
    debugPrint('Fatal startup error: $e\n$st');
    runApp(StartupErrorApp(error: e.toString()));
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text('The local database could not be opened.', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
}
