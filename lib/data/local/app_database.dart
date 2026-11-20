import 'package:sqflite_common/sqlite_api.dart';

import '../../core/services/data_change_bus.dart';

/// Opens a SQLite database. Production uses SQLCipher (see
/// `encrypted_database_opener.dart`); tests use sqflite_common_ffi.
typedef DatabaseOpener = Future<Database> Function(String path, OpenDatabaseOptions options);

class AppDatabase {
  AppDatabase(this.db);

  static const int schemaVersion = 1;

  final Database db;

  static Future<AppDatabase> open(DatabaseOpener opener, String path) async {
    final db = await opener(
      path,
      OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => createSchema(db),
        onUpgrade: (db, from, to) => migrate(db, from, to),
      ),
    );
    return AppDatabase(db);
  }

  Future<void> close() => db.close();

  /// Sync bookkeeping columns appended to every synced table.
  /// - sync_status: synced | pendingCreate | pendingUpdate | pendingDelete | failed
  /// - sync_base: JSON of the record as last agreed with the cloud. It is the
  ///   common ancestor used for field-level three-way merges.
  static const _syncCols = '''
    user_id TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    sync_status TEXT NOT NULL DEFAULT 'pendingCreate',
    sync_base TEXT''';

  static Future<void> createSchema(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE ${Tables.accounts} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        $_syncCols
      )''');
    batch.execute('''
      CREATE TABLE ${Tables.categories} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        $_syncCols
      )''');
    batch.execute('''
      CREATE TABLE ${Tables.transactions} (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        category_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        occurred_at INTEGER NOT NULL,
        attachment_path TEXT,
        recurring_rule_id TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        $_syncCols
      )''');
    batch.execute('''
      CREATE TABLE ${Tables.budgets} (
        id TEXT PRIMARY KEY,
        category_id TEXT,
        amount_minor INTEGER NOT NULL,
        $_syncCols
      )''');
    batch.execute('''
      CREATE TABLE ${Tables.goals} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        target_minor INTEGER NOT NULL,
        saved_minor INTEGER NOT NULL DEFAULT 0,
        target_date INTEGER,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        $_syncCols
      )''');
    batch.execute('''
      CREATE TABLE ${Tables.recurringRules} (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        category_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        frequency TEXT NOT NULL,
        start_at INTEGER NOT NULL,
        end_at INTEGER,
        occurrences_generated INTEGER NOT NULL DEFAULT 0,
        next_due_at INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        $_syncCols
      )''');
    batch.execute('''
      CREATE TABLE ${Tables.settings} (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    batch.execute('''
      CREATE TABLE ${Tables.exchangeRates} (
        currency TEXT PRIMARY KEY,
        rate_per_usd REAL NOT NULL,
        fetched_at INTEGER NOT NULL
      )''');

    // History list: keyset pagination over live rows ordered by date.
    batch.execute(
      'CREATE INDEX idx_tx_live_date ON ${Tables.transactions}(deleted_at, occurred_at DESC, id DESC)',
    );
    batch.execute('CREATE INDEX idx_tx_category ON ${Tables.transactions}(category_id)');
    batch.execute('CREATE INDEX idx_tx_account ON ${Tables.transactions}(account_id)');
    for (final t in Tables.synced) {
      batch.execute('CREATE INDEX idx_${t}_sync ON $t(sync_status)');
    }
    await batch.commit(noResult: true);
  }

  /// Forward-only migrations. Add `if (from < N)` blocks as the schema grows.
  static Future<void> migrate(Database db, int from, int to) async {
    // Version 1 is the initial schema.
  }

  /// Removes every row (used by "Reset local data" and logout).
  Future<void> clearAll() async {
    await db.transaction((txn) async {
      for (final t in [...Tables.synced, Tables.settings]) {
        await txn.delete(t);
      }
    });
  }
}
