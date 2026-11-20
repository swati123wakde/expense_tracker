import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/money.dart';

/// Prompts for a money amount; returns minor units or null if cancelled.
Future<int?> showAmountDialog(
  BuildContext context, {
  required String title,
  required String currency,
  int? initialMinor,
  String confirmLabel = 'Save',
  bool allowZero = false,
}) {
  // Not disposed explicitly: the dialog's exit animation still reads it.
  final controller = TextEditingController(text: initialMinor == null ? '' : Money.toDecimalString(initialMinor));
  final formKey = GlobalKey<FormState>();
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          key: const Key('amountDialogField'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(prefixText: '${Money.symbol(currency)} ', hintText: '0.00'),
          validator: (v) {
            final m = Money.parseToMinor(v ?? '');
            if (m == null) return 'Enter a valid amount';
            if (m < 0 || (!allowZero && m == 0)) return 'Enter an amount greater than zero';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          key: const Key('amountDialogConfirm'),
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(ctx, Money.parseToMinor(controller.text));
            }
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
