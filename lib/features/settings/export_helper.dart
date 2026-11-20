import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/dependencies.dart';
import '../../data/models/transaction_filter.dart';
import '../common/common_widgets.dart';

/// Writes exports to a temporary file and opens the system share sheet.
class ExportHelper {
  ExportHelper._();

  static Future<File> _write(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    return file.writeAsString(content, flush: true);
  }

  static String _stamp() => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  static Future<void> exportCsv(BuildContext context, TransactionFilter filter) async {
    final deps = context.read<AppDependencies>();
    try {
      final base = await deps.currency.baseCurrency();
      final csv = await deps.backup.exportCsv(filter, fallbackCurrency: base);
      final file = await _write('transactions_${_stamp()}.csv', csv);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: 'Transactions export');
    } catch (e) {
      if (context.mounted) showSnack(context, 'CSV export failed', error: true);
    }
  }

  static Future<void> exportJson(BuildContext context) async {
    final deps = context.read<AppDependencies>();
    try {
      final json = await deps.backup.exportJson();
      final file = await _write('expense_backup_${_stamp()}.json', json);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')], subject: 'Expense Manager backup');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Backup export failed', error: true);
    }
  }
}
