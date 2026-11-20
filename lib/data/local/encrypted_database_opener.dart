import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import 'app_database.dart';

/// SQLCipher-backed opener: the whole database file (data, indexes, WAL) is
/// AES-256 encrypted at rest. The passphrase comes from the platform keystore.
class EncryptedDatabaseOpener {
  EncryptedDatabaseOpener._();

  static const fileName = 'expense_manager.db';

  static Future<String> defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, fileName);
  }

  static DatabaseOpener withPassword(String password) {
    return (String path, OpenDatabaseOptions options) => cipher.openDatabase(
          path,
          password: password,
          version: options.version,
          onConfigure: options.onConfigure,
          onCreate: options.onCreate,
          onUpgrade: options.onUpgrade,
          onDowngrade: options.onDowngrade,
          onOpen: options.onOpen,
        );
  }
}
