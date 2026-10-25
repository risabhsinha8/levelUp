/// Configures sqflite for the current platform before the database opens.
///
/// sqflite works out of the box on Android, iOS and macOS. Windows and Linux
/// need its FFI implementation; the web has no dart:ffi, so it runs SQLite
/// as WASM via `sqflite_common_ffi_web`.
library;

export 'sqlite_setup_stub.dart'
    if (dart.library.ffi) 'sqlite_setup_ffi.dart'
    if (dart.library.js_interop) 'sqlite_setup_web.dart';
