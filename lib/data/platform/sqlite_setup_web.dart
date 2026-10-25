import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Runs SQLite as WASM in a shared worker, persisted to IndexedDB. Needs
/// `web/sqlite3.wasm` and `web/sqflite_sw.js`; regenerate them with
/// `dart run sqflite_common_ffi_web:setup` after upgrading the package.
void configureSqlite() {
  databaseFactory = databaseFactoryFfiWeb;
}
