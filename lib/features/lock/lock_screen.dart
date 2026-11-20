import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';

/// Full-screen lock shown instead of the app while locked. No financial data
/// is built underneath it.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    final lock = context.read<AppLockProvider>();
    if (lock.biometricEnabled) await lock.unlockWithBiometrics();
  }

  Future<void> _press(String digit) async {
    if (_checking || _pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 6) await _verify();
  }

  Future<void> _verify() async {
    final lock = context.read<AppLockProvider>();
    final remaining = lock.lockoutRemaining;
    if (remaining != null) {
      setState(() => _error = 'Too many attempts. Try again in ${remaining.inSeconds + 1}s');
      return;
    }
    setState(() => _checking = true);
    final ok = await lock.unlockWithPin(_pin);
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) return;
    unawaited(HapticFeedback.heavyImpact());
    setState(() {
      _pin = '';
      _error = 'Incorrect PIN';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lock = context.watch<AppLockProvider>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Icon(Icons.lock_outline, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Enter your PIN', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? scheme.primary : scheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 32,
              child: Center(
                child: Text(_error ?? '', style: TextStyle(color: scheme.error)),
              ),
            ),
            const Spacer(),
            _PinPad(
              onDigit: _press,
              onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
              onBiometric: lock.biometricEnabled ? lock.unlockWithBiometrics : null,
              onSubmit: _pin.length >= 4 ? () => _verify() : null,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onBackspace, this.onBiometric, this.onSubmit});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap, {String? semantics}) => SizedBox(
          width: 84,
          height: 72,
          child: Semantics(
            label: semantics,
            button: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(child: child),
            ),
          ),
        );
    final style = Theme.of(context).textTheme.headlineSmall;
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) key(Text(d, style: style), () => onDigit(d), semantics: d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key(
              onBiometric != null ? const Icon(Icons.fingerprint, size: 32) : const SizedBox.shrink(),
              onBiometric,
              semantics: 'Use biometrics',
            ),
            key(Text('0', style: style), () => onDigit('0'), semantics: '0'),
            key(const Icon(Icons.backspace_outlined), onBackspace, semantics: 'Delete'),
          ],
        ),
        if (onSubmit != null)
          TextButton(onPressed: onSubmit, child: const Text('Unlock')),
      ],
    );
  }
}

/// Dialog that asks for a new PIN twice. Returns the PIN or null.
Future<String?> showSetPinDialog(BuildContext context) async {
  final first = TextEditingController();
  final second = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Set a PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '4–6 digit PIN', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: second,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Confirm PIN', counterText: '', errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (first.text.length < 4) {
                setState(() => error = 'PIN must be at least 4 digits');
              } else if (first.text != second.text) {
                setState(() => error = 'PINs do not match');
              } else {
                Navigator.pop(ctx, first.text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Asks for the current PIN (e.g. before disabling the lock).
Future<String?> showVerifyPinDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enter current PIN'),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Confirm')),
      ],
    ),
  );
}
