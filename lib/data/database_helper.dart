import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';

/// Opens and initializes `skill_tree_rpg.db`.
///
/// Tables and columns follow the Phase 7 schema. A few extra columns
/// (marked "extension" below) keep data the existing screens rely on:
/// ordering, archived habits, quest seasons, claim timestamps, season
/// summaries and per-season oaths.
class DatabaseHelper {
  DatabaseHelper({DatabaseFactory? factory, String? path})
    : _factory = factory ?? databaseFactory,
      _path = path;

  /// In-memory database for unit tests (pass as `path`).
  static const String inMemoryPath = inMemoryDatabasePath;
  static const String fileName = 'skill_tree_rpg.db';

  /// 1: Phase 7 schema. 2: `habits.keystone_periods`. 3: the current season
  /// is aligned to calendar quarters (no column changes).
  /// 4: `branch_configs.forged_node_count`.
  static const int schemaVersion = 4;

  /// All tables, in the order they are cleared.
  static const tables = [
    'characters',
    'seasons',
    'branch_configs',
    'habits',
    'daily_logs',
    'quests',
    'loot_items',
  ];

  final DatabaseFactory _factory;
  final String? _path;
  Future<Database>? _db;

  Future<Database> get database => _db ??= _open();

  Future<Database> _open() async {
    final path = _path ?? p.join(await _factory.getDatabasesPath(), fileName);
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final statement in _schema) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE habits ADD COLUMN keystone_periods TEXT',
            );
          }
          if (oldVersion < 3) await alignCurrentSeasonToQuarter(db);
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE branch_configs ADD COLUMN '
              'forged_node_count INTEGER NOT NULL DEFAULT 0',
            );
            await forgeEarnedNodes(db);
          }
        },
      ),
    );
  }

  /// Marks every node already earned this season as forged, so upgrading
  /// to node forging never lowers anyone's level. Nodes earned afterwards
  /// wait to be forged.
  static Future<void> forgeEarnedNodes(DatabaseExecutor db) async {
    final characters = await db.query(
      'characters',
      columns: ['current_season_id'],
    );
    if (characters.isEmpty) return;
    final seasons = await db.query(
      'seasons',
      where: 'id = ?',
      whereArgs: [characters.first['current_season_id']],
    );
    if (seasons.isEmpty) return;
    // Branch Active Days: distinct dates with any habit of the branch done.
    final rows = await db.rawQuery(
      'SELECT h.branch AS branch, COUNT(DISTINCT l.date_string) AS days '
      'FROM daily_logs l JOIN habits h ON h.id = l.habit_id '
      'WHERE l.date_string BETWEEN ? AND ? GROUP BY h.branch',
      [seasons.single['start_date'], seasons.single['end_date']],
    );
    for (final row in rows) {
      await db.update(
        'branch_configs',
        {
          'forged_node_count': RpgEngine.calculateUnlockedNodes(
            row['days']! as int,
          ),
        },
        where: 'branch = ?',
        whereArgs: [row['branch']],
      );
    }
  }

  /// Moves the current season onto the calendar quarter its start date falls
  /// in, so a season begun on Oct 10 becomes Oct 1–Dec 31. It never starts
  /// before the previous season's end, so no date counts toward two seasons.
  /// Logs after the new end date count toward the next season.
  static Future<void> alignCurrentSeasonToQuarter(DatabaseExecutor db) async {
    final characters = await db.query(
      'characters',
      columns: ['current_season_id'],
    );
    if (characters.isEmpty) return;
    final seasonId = characters.first['current_season_id']! as String;
    final rows = await db.query(
      'seasons',
      where: 'id = ?',
      whereArgs: [seasonId],
    );
    if (rows.isEmpty) return;
    final start = parseDateString(rows.single['start_date']! as String);

    final previous = await db.rawQuery(
      'SELECT MAX(end_date) AS end_date FROM seasons WHERE id != ?',
      [seasonId],
    );
    final previousEnd = previous.single['end_date'] as String?;
    var newStart = Season.quarterStartOf(start);
    if (previousEnd != null) {
      final dayAfter = parseDateString(
        previousEnd,
      ).add(const Duration(days: 1));
      if (dayAfter.isAfter(newStart)) newStart = dayAfter;
    }
    await db.update(
      'seasons',
      {
        'start_date': toDateString(newStart),
        'end_date': toDateString(Season.quarterEndOf(start)),
      },
      where: 'id = ?',
      whereArgs: [seasonId],
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }

  static const _schema = [
    // signature_data: the current season's drawn oath as JSON
    // ({"seasonId", "strokes", "signedAtDate"}), or null if unsigned.
    '''CREATE TABLE characters (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      class_title TEXT NOT NULL,
      signature_data TEXT,
      current_season_id TEXT NOT NULL,
      signature_text TEXT NOT NULL DEFAULT '' -- extension
    )''',
    // mid_month_notes: JSON map of month key ("2026-10") to
    // {"notes", "pivots"} for the months reflected on during this season.
    '''CREATE TABLE seasons (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      is_archived INTEGER NOT NULL DEFAULT 0,
      mid_month_notes TEXT,
      oath_data TEXT, -- extension: oath kept with archived seasons
      summary_data TEXT -- extension: SeasonSummary JSON once completed
    )''',
    // buff_text / debuff_text: JSON arrays of chip strings.
    '''CREATE TABLE branch_configs (
      branch TEXT PRIMARY KEY,
      base_level INTEGER NOT NULL DEFAULT 0,
      buff_text TEXT NOT NULL DEFAULT '[]',
      debuff_text TEXT NOT NULL DEFAULT '[]',
      forged_node_count INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE habits (
      id TEXT PRIMARY KEY,
      branch TEXT NOT NULL,
      title TEXT NOT NULL,
      target_criteria TEXT NOT NULL DEFAULT '',
      is_keystone INTEGER NOT NULL DEFAULT 0,
      active_half_month TEXT NOT NULL DEFAULT 'both',
      is_archived INTEGER NOT NULL DEFAULT 0, -- extension
      sort_order INTEGER NOT NULL DEFAULT 0, -- extension
      keystone_periods TEXT -- extension: JSON keystone history
    )''',
    '''CREATE TABLE daily_logs (
      date_string TEXT NOT NULL,
      habit_id TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0, -- extension
      PRIMARY KEY (date_string, habit_id)
    )''',
    '''CREATE TABLE quests (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      is_main_quest INTEGER NOT NULL DEFAULT 0,
      branch TEXT NOT NULL,
      difficulty INTEGER NOT NULL DEFAULT 1,
      is_completed INTEGER NOT NULL DEFAULT 0,
      month_index INTEGER NOT NULL DEFAULT 1,
      reward_text TEXT NOT NULL DEFAULT '',
      season_id TEXT, -- extension
      sort_order INTEGER NOT NULL DEFAULT 0 -- extension
    )''',
    '''CREATE TABLE loot_items (
      id TEXT PRIMARY KEY,
      tier TEXT NOT NULL,
      title TEXT NOT NULL,
      claimed_at_date TEXT,
      claimed_at TEXT, -- extension: exact claim time
      sort_order INTEGER NOT NULL DEFAULT 0 -- extension
    )''',
  ];
}
