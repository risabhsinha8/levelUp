import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import 'database_helper.dart';
import 'rpg_repository.dart';

/// [RpgRepository] backed by the local SQLite database.
class RpgSqliteRepository implements RpgRepository {
  RpgSqliteRepository([DatabaseHelper? helper])
    : helper = helper ?? DatabaseHelper();

  /// The single character row's id.
  static const characterId = 'main';

  final DatabaseHelper helper;

  Future<Database> get _db => helper.database;

  Future<void> close() => helper.close();

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  @override
  Future<bool> hasCharacter() async {
    final db = await _db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM characters'),
    );
    return (count ?? 0) > 0;
  }

  @override
  Future<RpgState?> loadFullState() async {
    final db = await _db;
    final characters = await db.query('characters', limit: 1);
    if (characters.isEmpty) return null;
    final c = characters.single;
    final currentSeasonId = c['current_season_id']! as String;
    final currentOath = _decodeOath(c['signature_data'] as String?);

    final logs = <String, List<String>>{};
    for (final row in await db.query(
      'daily_logs',
      orderBy: 'date_string, sort_order',
    )) {
      logs
          .putIfAbsent(row['date_string']! as String, () => [])
          .add(row['habit_id']! as String);
    }

    final seasonRows = await db.query('seasons', orderBy: 'start_date, rowid');
    final reflections = <String, MonthReflection>{};
    for (final row in seasonRows) {
      reflections.addAll(_decodeReflections(row['mid_month_notes'] as String?));
    }

    return RpgState(
      character: Character(
        name: c['name']! as String,
        classTitle: c['class_title']! as String,
        signatureText: c['signature_text']! as String,
        currentSeasonId: currentSeasonId,
      ),
      branchConfigs: [
        for (final row in await db.query('branch_configs'))
          BranchConfig(
            branch: BranchType.values.byName(row['branch']! as String),
            baseLevel: row['base_level']! as int,
            buffs: _decodeStrings(row['buff_text'] as String?),
            debuffs: _decodeStrings(row['debuff_text'] as String?),
            forgedNodeCount: row['forged_node_count']! as int,
          ),
      ]..sort((a, b) => a.branch.index.compareTo(b.branch.index)),
      habits: [
        for (final row in await db.query('habits', orderBy: 'sort_order'))
          Habit(
            id: row['id']! as String,
            branch: BranchType.values.byName(row['branch']! as String),
            title: row['title']! as String,
            targetCriteria: row['target_criteria']! as String,
            isKeystone: row['is_keystone'] == 1,
            activeHalfMonth: ActiveHalfMonth.values.byName(
              row['active_half_month']! as String,
            ),
            isArchived: row['is_archived'] == 1,
            keystonePeriods: [
              if (row['keystone_periods'] != null)
                for (final p
                    in jsonDecode(row['keystone_periods']! as String) as List)
                  KeystonePeriod.fromJson(p as Map<String, dynamic>),
            ],
          ),
      ],
      logs: [
        for (final entry in logs.entries)
          DailyLog(dateString: entry.key, completedHabitIds: entry.value),
      ],
      quests: [
        for (final row in await db.query('quests', orderBy: 'sort_order'))
          Quest(
            id: row['id']! as String,
            title: row['title']! as String,
            isMainQuest: row['is_main_quest'] == 1,
            branch: BranchType.values.byName(row['branch']! as String),
            difficulty: row['difficulty']! as int,
            isCompleted: row['is_completed'] == 1,
            monthIndex: row['month_index']! as int,
            rewardText: row['reward_text']! as String,
            seasonId: row['season_id'] as String?,
          ),
      ],
      loot: [
        for (final row in await db.query('loot_items', orderBy: 'sort_order'))
          LootItem(
            id: row['id']! as String,
            tier: LootTier.values.byName(row['tier']! as String),
            title: row['title']! as String,
            claimedAtDate: row['claimed_at_date'] as String?,
            claimedAt: row['claimed_at'] == null
                ? null
                : DateTime.parse(row['claimed_at']! as String),
          ),
      ],
      seasons: [
        for (final row in seasonRows)
          Season(
            id: row['id']! as String,
            name: row['name']! as String,
            startDate: parseDateString(row['start_date']! as String),
            endDate: parseDateString(row['end_date']! as String),
            isArchived: row['is_archived'] == 1,
            oath: row['id'] == currentSeasonId
                ? currentOath?.oath
                : _decodeOath(row['oath_data'] as String?)?.oath,
            summary: row['summary_data'] == null
                ? null
                : SeasonSummary.fromJson(
                    jsonDecode(row['summary_data']! as String)
                        as Map<String, dynamic>,
                  ),
          ),
      ],
      reflections: reflections.values.toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Whole-state writes
  // ---------------------------------------------------------------------------

  @override
  Future<void> initializeFromOnboarding(RpgState initial) async {
    final db = await _db;
    await db.transaction((txn) async {
      final existing = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT COUNT(*) FROM characters'),
      );
      if ((existing ?? 0) > 0) {
        throw StateError('A character already exists.');
      }
      await _insertAll(txn, initial);
    });
  }

  @override
  Future<void> replaceAllData(RpgState state) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _deleteAll(txn);
      await _insertAll(txn, state);
    });
  }

  @override
  Future<void> wipeAllData() async {
    final db = await _db;
    await db.transaction(_deleteAll);
  }

  // ---------------------------------------------------------------------------
  // Granular writes
  // ---------------------------------------------------------------------------

  @override
  Future<bool> toggleHabitForDate(String habitId, String dateString) async {
    final db = await _db;
    return db.transaction((txn) async {
      final deleted = await txn.delete(
        'daily_logs',
        where: 'date_string = ? AND habit_id = ?',
        whereArgs: [dateString, habitId],
      );
      if (deleted > 0) return false;
      await txn.rawInsert(
        'INSERT INTO daily_logs (date_string, habit_id, sort_order) '
        'VALUES (?, ?, (SELECT COALESCE(MAX(sort_order), -1) + 1 '
        'FROM daily_logs WHERE date_string = ?))',
        [dateString, habitId, dateString],
      );
      return true;
    });
  }

  @override
  Future<void> upsertHabit(Habit habit) => upsertHabits([habit]);

  @override
  Future<void> upsertHabits(List<Habit> habits) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final habit in habits) {
        if (habit.isKeystone && !habit.isArchived) {
          // Safety net for the one-keystone rule. The store also sends the
          // unstarred habit (with its keystone history) in the same batch.
          await txn.update(
            'habits',
            {'is_keystone': 0},
            where:
                'branch = ? AND id != ? AND is_keystone = 1 AND is_archived = 0',
            whereArgs: [habit.branch.name, habit.id],
          );
        }
        await _upsert(txn, 'habits', _habitRow(habit));
      }
    });
  }

  @override
  Future<void> deleteHabit(String habitId) async {
    final db = await _db;
    await db.delete('habits', where: 'id = ?', whereArgs: [habitId]);
  }

  @override
  Future<void> updateBranchBuffDebuff(BranchConfig config) async {
    final db = await _db;
    await db.insert(
      'branch_configs',
      _branchRow(config),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> updateForgedNodes(BranchConfig config) async {
    final db = await _db;
    // A full row, so a branch with no stored row still gets its count.
    await db.insert(
      'branch_configs',
      _branchRow(config),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> upsertQuest(Quest quest) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (quest.isMainQuest) {
        await txn.rawUpdate(
          'UPDATE quests SET is_main_quest = 0 '
          'WHERE id != ? AND is_main_quest = 1 AND month_index = ? '
          // Quests without a season id belong to the current season.
          'AND (season_id IS NULL OR season_id = ?)',
          [quest.id, quest.monthIndex, quest.seasonId],
        );
      }
      await _upsert(txn, 'quests', _questRow(quest));
    });
  }

  @override
  Future<void> completeQuest(String questId, {bool completed = true}) async {
    final db = await _db;
    await db.update(
      'quests',
      {'is_completed': completed ? 1 : 0},
      where: 'id = ?',
      whereArgs: [questId],
    );
  }

  @override
  Future<void> upsertLootItem(LootItem item) async {
    final db = await _db;
    await db.transaction((txn) => _upsert(txn, 'loot_items', _lootRow(item)));
  }

  @override
  Future<void> claimLootItem(LootItem claim) async {
    if (!claim.isClaimed) {
      throw ArgumentError.value(claim, 'claim', 'must have a claim date');
    }
    final db = await _db;
    await db.transaction((txn) => _upsert(txn, 'loot_items', _lootRow(claim)));
  }

  @override
  Future<void> saveSignature(String seasonId, SeasonOath? oath) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'characters',
        columns: ['current_season_id'],
      );
      final isCurrent =
          rows.isNotEmpty && rows.single['current_season_id'] == seasonId;
      final data = _encodeOath(seasonId, oath);
      if (isCurrent) {
        await txn.update('characters', {'signature_data': data});
      } else {
        await txn.update(
          'seasons',
          {'oath_data': data},
          where: 'id = ?',
          whereArgs: [seasonId],
        );
      }
    });
  }

  @override
  Future<void> saveReflection(MonthReflection reflection) async {
    final db = await _db;
    await db.transaction((txn) => _saveReflection(txn, reflection));
  }

  @override
  Future<void> pivotHabit({
    required Habit old,
    required Habit replacement,
    required MonthReflection reflection,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _upsert(txn, 'habits', _habitRow(old));
      await _upsert(txn, 'habits', _habitRow(replacement));
      await _saveReflection(txn, reflection);
    });
  }

  @override
  Future<void> updateCharacter(Character character) async {
    final db = await _db;
    await db.update('characters', {
      'name': character.name,
      'class_title': character.classTitle,
      'signature_text': character.signatureText,
      'current_season_id': character.currentSeasonId,
    });
  }

  @override
  Future<void> prestigeSeason({
    required Season completed,
    required RpgState next,
  }) async {
    final db = await _db;
    final newSeason = next.currentSeason;
    await db.transaction((txn) async {
      final rows = await txn.query('characters', columns: ['signature_data']);
      final oathData = rows.isEmpty
          ? null
          : rows.single['signature_data'] as String?;

      // Archive the completed season, keeping its oath and final tally.
      await txn.update(
        'seasons',
        {
          'end_date': toDateString(completed.endDate),
          'is_archived': 1,
          'oath_data': oathData,
          'summary_data': completed.summary == null
              ? null
              : jsonEncode(completed.summary!.toJson()),
        },
        where: 'id = ?',
        whereArgs: [completed.id],
      );
      await txn.insert('seasons', _seasonRow(newSeason, isCurrent: true));

      // Full rows, inserted or replaced: a branch with no stored row (e.g.
      // from an old backup) must still get its new base level.
      for (final config in next.branchConfigs) {
        await txn.insert(
          'branch_configs',
          _branchRow(config),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.update('quests', {
        'season_id': completed.id,
      }, where: 'season_id IS NULL');
      await txn.update('characters', {
        'current_season_id': newSeason.id,
        'signature_data': null,
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Future<void> _deleteAll(Transaction txn) async {
    final batch = txn.batch();
    for (final table in DatabaseHelper.tables) {
      batch.delete(table);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _insertAll(Transaction txn, RpgState state) async {
    final batch = txn.batch();
    final c = state.character;
    final currentOath = state.seasons
        .where((s) => s.id == c.currentSeasonId)
        .firstOrNull
        ?.oath;
    batch.insert('characters', {
      'id': characterId,
      'name': c.name,
      'class_title': c.classTitle,
      'signature_data': _encodeOath(c.currentSeasonId, currentOath),
      'current_season_id': c.currentSeasonId,
      'signature_text': c.signatureText,
    });

    for (final s in state.seasons) {
      batch.insert('seasons', {
        ..._seasonRow(s, isCurrent: s.id == c.currentSeasonId),
        'mid_month_notes': _encodeReflections([
          for (final r in state.reflections)
            if (_seasonForReflection(state.seasons, c.currentSeasonId, r) ==
                s.id)
              r,
        ]),
      });
    }
    for (final config in state.branchConfigs) {
      batch.insert('branch_configs', _branchRow(config));
    }
    for (final (i, h) in state.habits.indexed) {
      batch.insert('habits', {..._habitRow(h), 'sort_order': i});
    }
    final seen = <String>{};
    final positions = <String, int>{};
    for (final log in state.logs) {
      for (final habitId in log.completedHabitIds) {
        if (!seen.add('${log.dateString}|$habitId')) continue;
        final position = positions.update(
          log.dateString,
          (p) => p + 1,
          ifAbsent: () => 0,
        );
        batch.insert('daily_logs', {
          'date_string': log.dateString,
          'habit_id': habitId,
          'sort_order': position,
        });
      }
    }
    for (final (i, q) in state.quests.indexed) {
      batch.insert('quests', {..._questRow(q), 'sort_order': i});
    }
    for (final (i, l) in state.loot.indexed) {
      batch.insert('loot_items', {..._lootRow(l), 'sort_order': i});
    }
    await batch.commit(noResult: true);
  }

  /// Insert-or-update by `id`, appending new rows at the end of the list
  /// and keeping an existing row's position.
  ///
  /// Written as UPDATE-then-INSERT rather than `INSERT ... ON CONFLICT DO
  /// UPDATE`: that UPSERT syntax needs SQLite 3.24, but Android 10 and older
  /// ship 3.22. Call inside a transaction so the two steps are atomic.
  static Future<void> _upsert(
    Transaction txn,
    String table,
    Map<String, Object?> row,
  ) async {
    final updated = await txn.update(
      table,
      {
        for (final entry in row.entries)
          if (entry.key != 'id') entry.key: entry.value,
      },
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    if (updated > 0) return;
    final columns = row.keys.toList();
    await txn.rawInsert(
      'INSERT INTO $table (${columns.join(', ')}, sort_order) '
      'VALUES (${List.filled(columns.length, '?').join(', ')}, '
      '(SELECT COALESCE(MAX(sort_order), -1) + 1 FROM $table))',
      row.values.toList(),
    );
  }

  /// Stores [reflection] in the `mid_month_notes` of the season containing
  /// the month's mid-point (the 15th), or the current season otherwise.
  static Future<void> _saveReflection(
    Transaction txn,
    MonthReflection reflection,
  ) async {
    final seasonRows = await txn.query('seasons');
    final seasons = [
      for (final row in seasonRows)
        Season(
          id: row['id']! as String,
          name: row['name']! as String,
          startDate: parseDateString(row['start_date']! as String),
          endDate: parseDateString(row['end_date']! as String),
        ),
    ];
    final character = await txn.query(
      'characters',
      columns: ['current_season_id'],
    );
    if (character.isEmpty) throw StateError('No character yet.');
    final seasonId = _seasonForReflection(
      seasons,
      character.single['current_season_id']! as String,
      reflection,
    );

    // Remove the month from wherever it was, then write it to its season.
    for (final row in seasonRows) {
      final map = _decodeReflections(row['mid_month_notes'] as String?);
      final hadMonth = map.remove(reflection.monthKey) != null;
      if (row['id'] == seasonId) map[reflection.monthKey] = reflection;
      if (hadMonth || row['id'] == seasonId) {
        await txn.update(
          'seasons',
          {'mid_month_notes': _encodeReflections(map.values)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  static String _seasonForReflection(
    List<Season> seasons,
    String currentSeasonId,
    MonthReflection reflection,
  ) {
    final midMonth = '${reflection.monthKey}-15';
    return seasons.where((s) => s.containsDate(midMonth)).lastOrNull?.id ??
        currentSeasonId;
  }

  static Map<String, Object?> _seasonRow(
    Season s, {
    required bool isCurrent,
  }) => {
    'id': s.id,
    'name': s.name,
    'start_date': toDateString(s.startDate),
    'end_date': toDateString(s.endDate),
    'is_archived': s.isArchived ? 1 : 0,
    // The current season's oath lives in characters.signature_data.
    'oath_data': isCurrent ? null : _encodeOath(s.id, s.oath),
    'summary_data': s.summary == null ? null : jsonEncode(s.summary!.toJson()),
  };

  static Map<String, Object?> _branchRow(BranchConfig c) => {
    'branch': c.branch.name,
    'base_level': c.baseLevel,
    'buff_text': jsonEncode(c.buffs),
    'debuff_text': jsonEncode(c.debuffs),
    'forged_node_count': c.forgedNodeCount,
  };

  static Map<String, Object?> _habitRow(Habit h) => {
    'id': h.id,
    'branch': h.branch.name,
    'title': h.title,
    'target_criteria': h.targetCriteria,
    'is_keystone': h.isKeystone ? 1 : 0,
    'active_half_month': h.activeHalfMonth.name,
    'is_archived': h.isArchived ? 1 : 0,
    'keystone_periods': h.keystonePeriods.isEmpty
        ? null
        : jsonEncode([for (final p in h.keystonePeriods) p.toJson()]),
  };

  static Map<String, Object?> _questRow(Quest q) => {
    'id': q.id,
    'title': q.title,
    'is_main_quest': q.isMainQuest ? 1 : 0,
    'branch': q.branch.name,
    'difficulty': q.difficulty,
    'is_completed': q.isCompleted ? 1 : 0,
    'month_index': q.monthIndex,
    'reward_text': q.rewardText,
    'season_id': q.seasonId,
  };

  static Map<String, Object?> _lootRow(LootItem l) => {
    'id': l.id,
    'tier': l.tier.name,
    'title': l.title,
    'claimed_at_date': l.claimedAtDate,
    'claimed_at': l.claimedAt?.toIso8601String(),
  };

  static List<String> _decodeStrings(String? json) =>
      json == null ? const [] : (jsonDecode(json) as List).cast<String>();

  static String? _encodeOath(String seasonId, SeasonOath? oath) => oath == null
      ? null
      : jsonEncode({'seasonId': seasonId, ...oath.toJson()});

  static ({String seasonId, SeasonOath oath})? _decodeOath(String? json) {
    if (json == null) return null;
    final map = jsonDecode(json) as Map<String, dynamic>;
    return (
      seasonId: map['seasonId'] as String,
      oath: SeasonOath.fromJson(map),
    );
  }

  static String? _encodeReflections(Iterable<MonthReflection> reflections) =>
      reflections.isEmpty
      ? null
      : jsonEncode({
          for (final r in reflections)
            r.monthKey: {'notes': r.notes, 'pivots': r.pivots},
        });

  static Map<String, MonthReflection> _decodeReflections(String? json) {
    if (json == null) return {};
    final map = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final entry in map.entries)
        entry.key: MonthReflection(
          monthKey: entry.key,
          notes: (entry.value as Map)['notes'] as String? ?? '',
          pivots: ((entry.value as Map)['pivots'] as List? ?? const [])
              .cast<String>(),
        ),
    };
  }
}
