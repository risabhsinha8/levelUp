/// Regression tests for bugs found in the full-project review.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/data/database_helper.dart';
import 'package:level_up/data/rpg_sqlite_repository.dart';
import 'package:level_up/domain/rpg_engine.dart';
import 'package:level_up/domain/season_rollover.dart';
import 'package:level_up/main.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/providers/rpg_store_provider.dart';
import 'package:level_up/screens/home_shell.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24, 9);

ProviderContainer containerFor(
  InMemoryRepository repo, {
  DateTime Function()? clock,
}) {
  final container = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(clock ?? () => today),
      rpgRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

int commonEarned(ProviderContainer c) =>
    c.read(characterSheetProvider).value!.lootKeys[LootTier.common]!.earned;

void main() {
  setUpAll(sqfliteFfiInit);

  group('moving the keystone star keeps earned Common Keys', () {
    test('engine: only days as keystone count', () {
      const id = 'h';
      List<DailyLog> run(int from, int days) => [
        for (var d = from; d < from + days; d++)
          DailyLog(
            dateString: '2026-10-${d.toString().padLeft(2, '0')}',
            completedHabitIds: [id],
          ),
      ];
      // Keystone Oct 1–7 (one key), then unstarred.
      const formerKeystone = Habit(
        id: id,
        branch: BranchType.body,
        title: 'Walk',
        keystonePeriods: [KeystonePeriod(to: '2026-10-07')],
      );
      expect(
        RpgEngine.calculateKeystoneCommonKeys(formerKeystone, run(1, 14)),
        1,
      );
      // Starred on Oct 8: the run before doesn't count retroactively.
      const newKeystone = Habit(
        id: id,
        branch: BranchType.body,
        title: 'Walk',
        isKeystone: true,
        keystonePeriods: [KeystonePeriod(from: '2026-10-08')],
      );
      expect(RpgEngine.calculateKeystoneCommonKeys(newKeystone, run(1, 10)), 0);
      expect(RpgEngine.calculateKeystoneCommonKeys(newKeystone, run(1, 14)), 1);
    });

    test('store: moving the Body star keeps the key Exercise earned', () async {
      final repo = InMemoryRepository(buildDemoState(today));
      final c = containerFor(repo);
      await c.read(rpgStoreProvider.future);
      expect(commonEarned(c), 2);

      await c
          .read(rpgStoreProvider.notifier)
          .setKeystone('habit-sleep', isKeystone: true);
      expect(commonEarned(c), 2); // was 1 before the fix
      final habits = repo.saved!.habits;
      expect(
        habits.firstWhere((h) => h.id == 'habit-exercise').keystonePeriods,
        [const KeystonePeriod(to: '2026-10-24')],
      );
      expect(habits.firstWhere((h) => h.id == 'habit-sleep').keystonePeriods, [
        const KeystonePeriod(from: '2026-10-24'),
      ]);
    });

    test('keystone history round-trips through JSON and SQLite', () async {
      const habit = Habit(
        id: 'h',
        branch: BranchType.mind,
        title: 'Read',
        isKeystone: true,
        keystonePeriods: [
          KeystonePeriod(to: '2026-10-01'),
          KeystonePeriod(from: '2026-10-10'),
        ],
      );
      expect(Habit.fromJson(habit.toJson()), habit);

      final repo = RpgSqliteRepository(
        DatabaseHelper(
          factory: databaseFactoryFfi,
          path: DatabaseHelper.inMemoryPath,
        ),
      );
      addTearDown(repo.close);
      final demo = buildDemoState(today);
      await repo.replaceAllData(demo.copyWith(habits: [habit]));
      expect((await repo.loadFullState())!.habits.single, habit);
    });
  });

  group('habits with check-ins keep their branch', () {
    test('store refuses to move them', () async {
      final repo = InMemoryRepository(buildDemoState(today));
      final c = containerFor(repo);
      await c.read(rpgStoreProvider.future);
      final store = c.read(rpgStoreProvider.notifier);

      await expectLater(
        store.addOrUpdateHabit(
          id: 'habit-water',
          branch: BranchType.mind,
          title: 'Water',
        ),
        throwsArgumentError,
      );
      expect(
        repo.saved!.habits.firstWhere((h) => h.id == 'habit-water').branch,
        BranchType.body,
      );

      // A habit without check-ins can still move.
      final id = await store.addOrUpdateHabit(
        branch: BranchType.bond,
        title: 'Letters',
      );
      await store.addOrUpdateHabit(
        id: id,
        branch: BranchType.craft,
        title: 'Letters',
      );
      expect(
        repo.saved!.habits.firstWhere((h) => h.id == id).branch,
        BranchType.craft,
      );
    });

    testWidgets('editor locks the branch selector', (tester) async {
      await pumpLevelUp(tester, now: today, state: buildDemoState(today));
      await tester.tap(find.byTooltip('Edit Water'));
      await tester.pumpAndSettle();
      expect(
        find.text('Branch locked: past check-ins count toward Body.'),
        findsOneWidget,
      );
      final mind = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Mind'),
      );
      expect(mind.onSelected, isNull);
    });
  });

  group('the date rolls over while the app is open', () {
    test('todayProvider and the character sheet follow the clock', () async {
      var now = DateTime(2026, 10, 24, 23, 59);
      final c = containerFor(
        InMemoryRepository(buildDemoState(DateTime(2026, 10, 24))),
        clock: () => now,
      );
      await c.read(rpgStoreProvider.future);
      expect(c.read(todayProvider), DateTime(2026, 10, 24));
      expect(c.read(characterSheetProvider).value!.seasonDay, 18);

      now = DateTime(2026, 10, 25, 0, 1);
      c.read(todayProvider.notifier).refresh();
      expect(c.read(todayProvider), DateTime(2026, 10, 25));
      expect(c.read(characterSheetProvider).value!.seasonDay, 19);
    });

    testWidgets('resuming the app next morning logs to the new day', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 24, 22);
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = InMemoryRepository(buildDemoState(DateTime(2026, 10, 24)));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            rpgRepositoryProvider.overrideWithValue(repo),
          ],
          child: const LevelUpApp(useGoogleFonts: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Season 1 • Day 18/86'), findsOneWidget);

      // Backgrounded overnight, resumed the next morning.
      now = DateTime(2026, 10, 25, 7);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Season 1 • Day 19/86'), findsOneWidget);

      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      expect(readState(tester).completedOn(DateTime(2026, 10, 25)), {
        'habit-exercise',
      });
      expect(readState(tester).completedOn(DateTime(2026, 10, 24)), isEmpty);
    });

    testWidgets('a day picked in the week strip stays picked', (tester) async {
      var now = DateTime(2026, 10, 24, 22);
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            rpgRepositoryProvider.overrideWithValue(
              InMemoryRepository(buildDemoState(DateTime(2026, 10, 24))),
            ),
          ],
          child: const LevelUpApp(useGoogleFonts: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Wed, Oct 21'));
      await tester.pumpAndSettle();

      now = DateTime(2026, 10, 25, 7);
      ProviderScope.containerOf(
        tester.element(find.byType(HomeShell)),
      ).read(todayProvider.notifier).refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sleep'));
      await tester.pumpAndSettle();
      expect(
        readState(tester).completedOn(DateTime(2026, 10, 21)),
        isNot(contains('habit-sleep')), // demo had it done: toggled off
      );
      expect(readState(tester).completedOn(DateTime(2026, 10, 25)), isEmpty);
    });
  });

  group('backup import', () {
    test('duplicate ids are rejected up front', () async {
      final repo = InMemoryRepository(buildDemoState(today));
      final c = containerFor(repo);
      await c.read(rpgStoreProvider.future);
      final store = c.read(rpgStoreProvider.notifier);
      final demo = buildDemoState(today);
      final broken = demo.copyWith(habits: [...demo.habits, demo.habits.first]);
      final json = const JsonEncoderHelper().encode(broken.toJson());

      await expectLater(store.importBackup(json), throwsFormatException);
      expect(repo.saved!.habits, hasLength(9));
    });

    testWidgets('the import dialog shows storage errors', (tester) async {
      final repo = FailingImportRepository(buildDemoState(today));
      await pumpLevelUp(tester, now: today, repository: repo);
      await tester.tap(find.text('Season Tally').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Backup JSON'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        const JsonEncoderHelper().encode(buildDemoState(today).toJson()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not restore this backup'),
        findsOneWidget,
      );
      expect(find.text('Import Backup'), findsOneWidget); // still open
    });

    testWidgets('restored notes replace stale ones in the reflection card', (
      tester,
    ) async {
      await pumpLevelUp(tester, now: today, state: buildDemoState(today));
      await tester.tap(find.text('Monthly Matrix'));
      await tester.pumpAndSettle();
      final notesField = find.widgetWithText(
        TextField,
        'What worked? What felt like burnout?',
      );
      expect(tester.widget<TextField>(notesField).controller!.text, isEmpty);

      final backup = buildDemoState(today).copyWith(
        reflections: [
          MonthReflection(monthKey: '2026-10', notes: 'Restored notes'),
        ],
      );
      await ProviderScope.containerOf(tester.element(find.byType(HomeShell)))
          .read(rpgStoreProvider.notifier)
          .importBackup(const JsonEncoderHelper().encode(backup.toJson()));
      await tester.pumpAndSettle();
      expect(find.text('Restored notes'), findsOneWidget);
    });
  });

  group('completing a season', () {
    test('is refused while the quarter is running', () async {
      final repo = InMemoryRepository(buildFreshState(today));
      final c = containerFor(repo);
      await c.read(rpgStoreProvider.future);
      await expectLater(
        c.read(rpgStoreProvider.notifier).completeSeason(),
        throwsStateError,
      );
      expect(repo.saved!.seasons, hasLength(1));
    });

    testWidgets('the button is disabled until the quarter ends', (
      tester,
    ) async {
      await pumpLevelUp(tester, now: today, state: buildFreshState(today));
      await tester.tap(find.text('Season Tally').last);
      await tester.pumpAndSettle();
      final button = find.ancestor(
        of: find.text('Complete Season 1 & Level Up'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
      expect(find.text('69 days left · unlocks Jan 1'), findsOneWidget);
    });

    test(
      'SQLite stores new base levels even for missing branch rows',
      () async {
        final repo = RpgSqliteRepository(
          DatabaseHelper(
            factory: databaseFactoryFfi,
            path: DatabaseHelper.inMemoryPath,
          ),
        );
        addTearDown(repo.close);
        // An old backup with only Mind's config row.
        final demo = buildDemoState(today);
        final partial = demo.copyWith(
          branchConfigs: [demo.configFor(BranchType.mind)],
        );
        await repo.replaceAllData(partial);

        final result = SeasonRollover.apply(
          partial,
          DateTime(2027, 1, 1),
          newSeasonId: 's2',
        );
        await repo.prestigeSeason(
          completed: result.completedSeason,
          next: result.state,
        );
        final loaded = (await repo.loadFullState())!;
        expect(loaded.configFor(BranchType.body).baseLevel, 2);
        expect(loaded.configFor(BranchType.craft).baseLevel, 2);
        expect(loaded.configFor(BranchType.mind).baseLevel, 3);
      },
    );
  });

  test('a version 1 database is migrated to keystone history', () async {
    final dir = await Directory.systemTemp.createTemp('level_up_db');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, DatabaseHelper.fileName);

    // Create the v1 habits table by hand.
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE habits (
            id TEXT PRIMARY KEY, branch TEXT NOT NULL, title TEXT NOT NULL,
            target_criteria TEXT NOT NULL DEFAULT '',
            is_keystone INTEGER NOT NULL DEFAULT 0,
            active_half_month TEXT NOT NULL DEFAULT 'both',
            is_archived INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0)''');
          // No character yet, so the v3 and v4 data steps have nothing to
          // do.
          await db.execute(
            'CREATE TABLE characters (current_season_id TEXT NOT NULL)',
          );
          await db.execute('CREATE TABLE branch_configs (branch TEXT)');
        },
      ),
    );
    await v1.close();

    final helper = DatabaseHelper(factory: databaseFactoryFfi, path: path);
    addTearDown(helper.close);
    final db = await helper.database;
    final columns = [
      for (final row in await db.rawQuery('PRAGMA table_info(habits)'))
        row['name'],
    ];
    expect(columns, contains('keystone_periods'));
  });

  group('the v3 upgrade aligns the current season to its quarter', () {
    Future<RpgState> align(List<Season> seasons) async {
      final helper = DatabaseHelper(
        factory: databaseFactoryFfi,
        path: DatabaseHelper.inMemoryPath,
      );
      final repo = RpgSqliteRepository(helper);
      addTearDown(repo.close);
      await repo.replaceAllData(
        buildDemoState(today).copyWith(seasons: seasons),
      );
      await DatabaseHelper.alignCurrentSeasonToQuarter(await helper.database);
      return (await repo.loadFullState())!;
    }

    final legacy = Season(
      id: 'season-1',
      name: 'Season 1',
      startDate: DateTime.utc(2026, 10, 10),
      endDate: DateTime.utc(2027, 1, 7), // the old 90-day length
    );

    test('a 90-day season becomes its calendar quarter', () async {
      final season = (await align([legacy])).currentSeason;
      expect(toDateString(season.startDate), '2026-10-01');
      expect(toDateString(season.endDate), '2026-12-31');
    });

    test('it never starts before the previous season ended', () async {
      final previous = Season(
        id: 'season-0',
        name: 'Season 0',
        startDate: DateTime.utc(2026, 7, 12),
        endDate: DateTime.utc(2026, 10, 9),
        isArchived: true,
      );
      final season = (await align([previous, legacy])).currentSeason;
      expect(toDateString(season.startDate), '2026-10-10');
      expect(toDateString(season.endDate), '2026-12-31');
    });
  });

  testWidgets('the level badge counts up on first show', (tester) async {
    await pumpLevelUp(
      tester,
      now: today,
      state: buildDemoState(today),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('9'), findsNothing); // still counting
    await tester.pumpAndSettle();
    expect(find.text('9'), findsOneWidget);
  });
}

class JsonEncoderHelper {
  const JsonEncoderHelper();

  String encode(Object json) => const JsonEncoder().convert(json);
}

/// Fails every full-data replace, like a disk or constraint error.
class FailingImportRepository extends InMemoryRepository {
  FailingImportRepository([super.saved]);

  @override
  Future<void> replaceAllData(state) async => throw StateError('disk full');
}
