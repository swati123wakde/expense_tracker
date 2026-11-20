import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/services/data_change_bus.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../local/sync_tables.dart';
import '../local/syncable_dao.dart';
import '../models/app_settings.dart';
import '../models/transaction_filter.dart';
import 'current_user.dart';
import 'settings_repository.dart';
import 'transaction_repository.dart';

class BackupValidationException implements Exception {
  BackupValidationException(this.errors);
  final List<String> errors;

  @override
  String toString() => 'Invalid backup:\n${errors.take(10).join('\n')}'
      '${errors.length > 10 ? '\n…and ${errors.length - 10} more' : ''}';
}

class ImportSummary {
  const ImportSummary(this.counts);
  final Map<String, int> counts;
  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// JSON backup/restore and CSV export.
class BackupRepository {
  BackupRepository(this._db, this._bus, this._user, this._clock, this._settings, this._transactions);

  final Database _db;
  final DataChangeBus _bus;
  final CurrentUser _user;
  final Clock _clock;
  final SettingsRepository _settings;
  final TransactionRepository _transactions;

  static const int formatVersion = 1;

  /// JSON section name for each synced table.
  static const Map<String, SyncTableSpec> sections = {
    'accounts': SyncTables.accounts,
    'categories': SyncTables.categories,
    'transactions': SyncTables.transactions,
    'budgets': SyncTables.budgets,
    'goals': SyncTables.goals,
    'recurring': SyncTables.recurringRules,
  };

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> exportData() async {
    final data = <String, Object?>{
      'version': formatVersion,
      'exportedAt': _clock.now().toUtc().toIso8601String(),
    };
    for (final entry in sections.entries) {
      final rows = await _db.query(entry.value.table, where: 'deleted_at IS NULL');
      data[entry.key] = [
        for (final r in rows)
          {
            for (final c in entry.value.columns)
              if (c != 'user_id' && c != 'deleted_at') c: r[c],
          },
      ];
    }
    data['settings'] = await _settings.exportable();
    return data;
  }

  Future<String> exportJson() async =>
      const JsonEncoder.withIndent('  ').convert(await exportData());

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  /// Validates the whole document first; the database is only touched when
  /// validation passes, and then inside a single SQL transaction.
  Future<ImportSummary> importJson(String json) async {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw BackupValidationException(['File is not valid JSON (${e.message}).']);
    }
    final existingAccounts = await _ids(SyncTables.accounts.table);
    final existingCategories = await _ids(SyncTables.categories.table);
    final errors = BackupValidator.validate(
      decoded,
      existingAccountIds: existingAccounts,
      existingCategoryIds: existingCategories,
    );
    if (errors.isNotEmpty) throw BackupValidationException(errors);

    final doc = decoded as Map<String, Object?>;
    final counts = <String, int>{};
    await _db.transaction((txn) async {
      for (final entry in sections.entries) {
        final list = doc[entry.key];
        if (list is! List) continue;
        final dao = SyncableDao(_db, entry.value, _clock);
        for (final raw in list) {
          final record = Map<String, Object?>.from(raw as Map);
          final row = <String, Object?>{
            for (final c in entry.value.columns) c: record[c],
            'user_id': _user.id,
            'deleted_at': null,
          };
          row['created_at'] ??= _clock.nowMs();
          await dao.saveLocal(_withDefaults(entry.key, row), exec: txn);
        }
        counts[entry.key] = list.length;
      }
    });

    final settings = doc['settings'];
    if (settings is Map) {
      for (final key in [SettingsKeys.themeMode, SettingsKeys.baseCurrency, SettingsKeys.notificationsEnabled]) {
        final v = settings[key];
        if (v is String) await _settings.set(key, v, notify: false);
      }
    }
    _bus.emit({...Tables.synced, Tables.settings});
    return ImportSummary(counts);
  }

  Map<String, Object?> _withDefaults(String section, Map<String, Object?> row) {
    switch (section) {
      case 'transactions':
        row['note'] ??= '';
        row['is_favorite'] ??= 0;
      case 'categories':
        row['is_custom'] ??= 1;
        row['archived'] ??= 0;
        row['sort_order'] ??= 1000;
        row['icon'] ??= 'other';
        row['color'] ??= 0xFF757575;
      case 'accounts':
        row['archived'] ??= 0;
        row['icon'] ??= 'wallet';
        row['color'] ??= 0xFF1E88E5;
      case 'goals':
        row['saved_minor'] ??= 0;
        row['icon'] ??= 'savings';
        row['color'] ??= 0xFF43A047;
      case 'recurring':
        row['note'] ??= '';
        row['occurrences_generated'] ??= 0;
        row['active'] ??= 1;
    }
    return row;
  }

  Future<Set<String>> _ids(String table) async {
    final rows = await _db.query(table, columns: ['id'], where: 'deleted_at IS NULL');
    return {for (final r in rows) r['id'] as String};
  }

  // ---------------------------------------------------------------------------
  // CSV
  // ---------------------------------------------------------------------------

  /// Exports transactions matching [filter] (or all) as CSV.
  Future<String> exportCsv(TransactionFilter filter, {String fallbackCurrency = 'USD'}) async {
    final buffer = StringBuffer('Date,Type,Category,Account,Amount,Note\n');
    await for (final v in _transactions.iterate(filter, fallbackCurrency: fallbackCurrency)) {
      final t = v.transaction;
      buffer.writeln([
        DateUtilsX.dayKey(t.occurredAt),
        t.type.label,
        v.categoryName,
        v.accountName,
        Money.toDecimalString(t.amountMinor),
        t.note,
      ].map(csvEscape).join(','));
    }
    return buffer.toString();
  }

  static String csvEscape(String value) {
    var v = value;
    // Neutralise spreadsheet formula injection.
    if (v.isNotEmpty && '=+-@'.contains(v[0]) && double.tryParse(v) == null) v = "'$v";
    if (v.contains(RegExp(r'[",\n\r]'))) return '"${v.replaceAll('"', '""')}"';
    return v;
  }
}

/// Pure structural + referential validation of a backup document.
class BackupValidator {
  BackupValidator._();

  static const _required = {
    'accounts': {'id': _Kind.string, 'name': _Kind.string, 'type': _Kind.string, 'currency': _Kind.string, 'updated_at': _Kind.integer},
    'categories': {'id': _Kind.string, 'name': _Kind.string, 'type': _Kind.txType, 'updated_at': _Kind.integer},
    'transactions': {
      'id': _Kind.string,
      'type': _Kind.txType,
      'amount_minor': _Kind.positiveInt,
      'category_id': _Kind.string,
      'account_id': _Kind.string,
      'occurred_at': _Kind.integer,
      'updated_at': _Kind.integer,
    },
    'budgets': {'id': _Kind.string, 'amount_minor': _Kind.positiveInt, 'updated_at': _Kind.integer},
    'goals': {'id': _Kind.string, 'name': _Kind.string, 'target_minor': _Kind.positiveInt, 'updated_at': _Kind.integer},
    'recurring': {
      'id': _Kind.string,
      'type': _Kind.txType,
      'amount_minor': _Kind.positiveInt,
      'category_id': _Kind.string,
      'account_id': _Kind.string,
      'frequency': _Kind.string,
      'start_at': _Kind.integer,
      'next_due_at': _Kind.integer,
      'updated_at': _Kind.integer,
    },
  };

  static List<String> validate(
    Object? doc, {
    Set<String> existingAccountIds = const {},
    Set<String> existingCategoryIds = const {},
  }) {
    final errors = <String>[];
    if (doc is! Map) return ['Backup root must be a JSON object.'];
    final version = doc['version'];
    if (version is! int) {
      errors.add('Missing or invalid "version".');
    } else if (version > BackupRepository.formatVersion || version < 1) {
      errors.add('Unsupported backup version $version.');
    }
    for (final key in ['transactions', 'categories', 'accounts', 'budgets', 'goals']) {
      if (doc[key] is! List) errors.add('"$key" must be a list.');
    }
    if (doc['recurring'] != null && doc['recurring'] is! List) errors.add('"recurring" must be a list.');
    if (doc['settings'] != null && doc['settings'] is! Map) errors.add('"settings" must be an object.');
    if (errors.isNotEmpty) return errors;

    final ids = <String, Set<String>>{};
    _required.forEach((section, fields) {
      final list = doc[section];
      if (list is! List) return;
      final seen = <String>{};
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! Map) {
          errors.add('$section[$i] must be an object.');
          continue;
        }
        fields.forEach((field, kind) {
          if (!_check(item[field], kind)) errors.add('$section[$i].$field is missing or invalid.');
        });
        final id = item['id'];
        if (id is String && !seen.add(id)) errors.add('$section has duplicate id "$id".');
      }
      ids[section] = seen;
    });

    final accounts = {...existingAccountIds, ...?ids['accounts']};
    final categories = {...existingCategoryIds, ...?ids['categories']};
    for (final section in ['transactions', 'recurring']) {
      final list = doc[section];
      if (list is! List) continue;
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! Map) continue;
        final acc = item['account_id'];
        final cat = item['category_id'];
        if (acc is String && !accounts.contains(acc)) errors.add('$section[$i] references unknown account "$acc".');
        if (cat is String && !categories.contains(cat)) errors.add('$section[$i] references unknown category "$cat".');
      }
    }
    return errors;
  }

  static bool _check(Object? v, _Kind kind) {
    switch (kind) {
      case _Kind.string:
        return v is String && v.isNotEmpty;
      case _Kind.integer:
        return v is int;
      case _Kind.positiveInt:
        return v is int && v > 0;
      case _Kind.txType:
        return v == 'income' || v == 'expense';
    }
  }
}

enum _Kind { string, integer, positiveInt, txType }
