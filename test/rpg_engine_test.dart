import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/domain/rpg_engine.dart';
import 'package:level_up/models/rpg_models.dart';

/// `count` consecutive date strings starting at [start].
List<String> consecutiveDates(String start, int count) {
  final first = parseDateString(start);
  return [
    for (var i = 0; i < count; i++) toDateString(first.add(Duration(days: i))),
  ];
}

/// One log per date, each completing [habitIds].
List<DailyLog> logsFor(List<String> dates, List<String> habitIds) => [
  for (final date in dates)
    DailyLog(dateString: date, completedHabitIds: habitIds),
];

const exercise = Habit(
  id: 'exercise',
  branch: BranchType.body,
  title: 'Exercise',
  isKeystone: true,
);
const water = Habit(
  id: 'water',
  branch: BranchType.body,
  title: 'Water',
  targetCriteria: '13 cups daily',
);
const sleep = Habit(id: 'sleep', branch: BranchType.body, title: 'Sleep');
const reading = Habit(
  id: 'reading',
  branch: BranchType.mind,
  title: 'Reading',
  isKeystone: true,
);

/// One keystone habit per branch, ids `k-<branch>`.
final keystonePerBranch = [
  for (final branch in BranchType.values)
    Habit(id: 'k-${branch.name}', branch: branch, title: 'K', isKeystone: true),
];

void main() {
  group('calculateBranchActiveDays', () {
    final habits = [exercise, water, sleep, reading];

    test('1, 2 or 3 habits in a branch on one date yield exactly 1 day', () {
      for (final completed in [
        ['exercise'],
        ['exercise', 'water'],
        ['exercise', 'water', 'sleep'],
      ]) {
        final logs = [
          DailyLog(dateString: '2026-01-01', completedHabitIds: completed),
        ];
        expect(
          RpgEngine.calculateBranchActiveDays(BranchType.body, habits, logs),
          1,
          reason: 'completed: $completed',
        );
      }
    });

    test('duplicate logs for the same date still count once', () {
      final logs = [
        DailyLog(dateString: '2026-01-01', completedHabitIds: ['exercise']),
        DailyLog(dateString: '2026-01-01', completedHabitIds: ['water']),
        DailyLog(dateString: '2026-01-01', completedHabitIds: ['sleep']),
      ];
      expect(
        RpgEngine.calculateBranchActiveDays(BranchType.body, habits, logs),
        1,
      );
    });

    test('counts each distinct date across days', () {
      final logs = [
        DailyLog(dateString: '2026-01-01', completedHabitIds: ['exercise']),
        DailyLog(
          dateString: '2026-01-02',
          completedHabitIds: ['water', 'sleep'],
        ),
        DailyLog(dateString: '2026-01-05', completedHabitIds: ['sleep']),
      ];
      expect(
        RpgEngine.calculateBranchActiveDays(BranchType.body, habits, logs),
        3,
      );
    });

    test('other branches are unaffected and isolated', () {
      final logs = [
        DailyLog(
          dateString: '2026-01-01',
          completedHabitIds: ['exercise', 'water', 'reading'],
        ),
        DailyLog(dateString: '2026-01-02', completedHabitIds: ['reading']),
      ];
      final all = RpgEngine.calculateAllBranchActiveDays(habits, logs);
      expect(all[BranchType.body], 1);
      expect(all[BranchType.mind], 2);
      expect(all[BranchType.craft], 0);
      expect(all[BranchType.bond], 0);
      expect(all[BranchType.empire], 0);
    });

    test('missed days do not remove progress (no streak punishment)', () {
      final logs = [
        DailyLog(dateString: '2026-01-01', completedHabitIds: ['exercise']),
        DailyLog(dateString: '2026-01-10', completedHabitIds: ['exercise']),
        DailyLog(dateString: '2026-02-20', completedHabitIds: ['exercise']),
      ];
      expect(
        RpgEngine.calculateBranchActiveDays(BranchType.body, habits, logs),
        3,
      );
    });

    test('ignores unknown habit ids and empty logs', () {
      final logs = [
        DailyLog(dateString: '2026-01-01', completedHabitIds: ['deleted']),
        DailyLog(dateString: '2026-01-02'),
      ];
      expect(
        RpgEngine.calculateBranchActiveDays(BranchType.body, habits, logs),
        0,
      );
    });

    test('season filter only counts dates inside the season', () {
      final season = Season(
        id: 's1',
        name: 'Winter',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 3, 31),
      );
      final logs = [
        DailyLog(dateString: '2025-12-31', completedHabitIds: ['exercise']),
        DailyLog(dateString: '2026-01-01', completedHabitIds: ['exercise']),
        DailyLog(dateString: '2026-03-31', completedHabitIds: ['exercise']),
        DailyLog(dateString: '2026-04-01', completedHabitIds: ['exercise']),
      ];
      expect(
        RpgEngine.calculateBranchActiveDays(
          BranchType.body,
          habits,
          logs,
          season: season,
        ),
        2,
      );
    });
  });

  group('calculateUnlockedNodes', () {
    test('thresholds are 5, 15, 30, 50, 80', () {
      expect(RpgEngine.nodeThresholds, [5, 15, 30, 50, 80]);
    });

    test('unlocks exactly at each threshold, not one day before', () {
      const expected = {
        0: 0,
        4: 0,
        5: 1,
        14: 1,
        15: 2,
        29: 2,
        30: 3,
        49: 3,
        50: 4,
        79: 4,
        80: 5,
        90: 5,
      };
      expected.forEach((days, nodes) {
        expect(
          RpgEngine.calculateUnlockedNodes(days),
          nodes,
          reason: '$days active days',
        );
      });
    });

    test('multi-habit days do not accelerate node unlocks', () {
      // 5 dates with all 3 body habits = 5 active days, not 15.
      final logs = logsFor(consecutiveDates('2026-01-01', 5), [
        'exercise',
        'water',
        'sleep',
      ]);
      final days = RpgEngine.calculateBranchActiveDays(BranchType.body, [
        exercise,
        water,
        sleep,
      ], logs);
      expect(days, 5);
      expect(RpgEngine.calculateUnlockedNodes(days), 1);
    });
  });

  group('leveling', () {
    test('branch level = base carry-over + nodes + feats', () {
      expect(RpgEngine.calculateBranchLevel(0, 0, 0), 0);
      expect(RpgEngine.calculateBranchLevel(3, 0, 0), 3);
      expect(RpgEngine.calculateBranchLevel(3, 5, 2), 10);
    });

    test('base level carries over with a fresh season', () {
      // Last season ended at level 7; new season has no progress yet.
      expect(RpgEngine.calculateBranchLevel(7, 0, 0), 7);
      // After hitting the 5-day node, level goes up by one.
      expect(
        RpgEngine.calculateBranchLevel(
          7,
          RpgEngine.calculateUnlockedNodes(5),
          0,
        ),
        8,
      );
    });

    test('rejects invalid inputs', () {
      expect(
        () => RpgEngine.calculateBranchLevel(-1, 0, 0),
        throwsArgumentError,
      );
      expect(
        () => RpgEngine.calculateBranchLevel(0, 6, 0),
        throwsArgumentError,
      );
      expect(
        () => RpgEngine.calculateBranchLevel(0, -1, 0),
        throwsArgumentError,
      );
      expect(
        () => RpgEngine.calculateBranchLevel(0, 0, -1),
        throwsArgumentError,
      );
    });

    test('completed feats count only completed quests in the branch', () {
      const quests = [
        Quest(id: 'q1', title: 'A', branch: BranchType.body, isCompleted: true),
        Quest(id: 'q2', title: 'B', branch: BranchType.body),
        Quest(id: 'q3', title: 'C', branch: BranchType.mind, isCompleted: true),
        Quest(
          id: 'q4',
          title: 'D',
          branch: BranchType.body,
          isCompleted: true,
          isMainQuest: true,
          difficulty: 5,
        ),
      ];
      expect(RpgEngine.calculateCompletedFeats(BranchType.body, quests), 2);
      expect(RpgEngine.calculateCompletedFeats(BranchType.mind, quests), 1);
      expect(RpgEngine.calculateCompletedFeats(BranchType.craft, quests), 0);
    });

    test('character level = sum of all 5 branch levels', () {
      expect(
        RpgEngine.calculateTotalCharacterLevel({
          BranchType.mind: 4,
          BranchType.body: 10,
          BranchType.craft: 0,
          BranchType.bond: 2,
          BranchType.empire: 6,
        }),
        22,
      );
      expect(RpgEngine.calculateTotalCharacterLevel({}), 0);
    });
  });

  group('keystone Common Keys', () {
    test('6 consecutive days earns nothing, 7 earns one', () {
      expect(
        RpgEngine.calculateKeystoneCommonKeys(
          exercise,
          logsFor(consecutiveDates('2026-01-01', 6), ['exercise']),
        ),
        0,
      );
      expect(
        RpgEngine.calculateKeystoneCommonKeys(
          exercise,
          logsFor(consecutiveDates('2026-01-01', 7), ['exercise']),
        ),
        1,
      );
    });

    test('earns one key for every 7 consecutive days', () {
      int keysFor(int days) => RpgEngine.calculateKeystoneCommonKeys(
        exercise,
        logsFor(consecutiveDates('2026-01-01', days), ['exercise']),
      );
      expect(keysFor(13), 1);
      expect(keysFor(14), 2);
      expect(keysFor(21), 3);
    });

    test('a gap resets the consecutive count', () {
      final dates = [
        ...consecutiveDates('2026-01-01', 6),
        ...consecutiveDates('2026-01-08', 6), // Jan 7 missed.
      ];
      expect(
        RpgEngine.calculateKeystoneCommonKeys(
          exercise,
          logsFor(dates, ['exercise']),
        ),
        0,
      );
    });

    test('completing a non-keystone habit does not count', () {
      final logs = logsFor(consecutiveDates('2026-01-01', 7), ['water']);
      expect(RpgEngine.calculateKeystoneCommonKeys(exercise, logs), 0);
    });

    test('runs across a month boundary and DST change are consecutive', () {
      // US DST starts 2026-03-08.
      final logs = logsFor(consecutiveDates('2026-03-04', 7), ['exercise']);
      expect(RpgEngine.calculateKeystoneCommonKeys(exercise, logs), 1);
      final monthEnd = logsFor(consecutiveDates('2026-01-28', 7), ['exercise']);
      expect(RpgEngine.calculateKeystoneCommonKeys(exercise, monthEnd), 1);
    });

    test('unordered and duplicate logs are handled', () {
      final logs =
          logsFor(consecutiveDates('2026-01-01', 7).reversed.toList(), [
            'exercise',
          ])..add(
            DailyLog(dateString: '2026-01-03', completedHabitIds: ['exercise']),
          );
      expect(RpgEngine.calculateKeystoneCommonKeys(exercise, logs), 1);
    });
  });

  group('calculateAvailableLootKeys', () {
    test('no activity means no keys', () {
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: [exercise],
        logs: const [],
        claimedLoot: const [],
      );
      for (final tier in LootTier.values) {
        expect(keys[tier], const LootKeyBalance(earned: 0, claimed: 0));
      }
    });

    test('7-day keystone run triggers a Common and a Rare (5-day node)', () {
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: [exercise, water],
        logs: logsFor(consecutiveDates('2026-01-01', 7), ['exercise', 'water']),
        claimedLoot: const [],
      );
      expect(keys[LootTier.common]!.earned, 1);
      expect(keys[LootTier.rare]!.earned, 1);
      expect(keys[LootTier.epic]!.earned, 0);
      expect(keys[LootTier.legendary]!.earned, 0);
    });

    test('each keystone earns Common Keys independently', () {
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: [exercise, reading],
        logs: logsFor(consecutiveDates('2026-01-01', 7), [
          'exercise',
          'reading',
        ]),
        claimedLoot: const [],
      );
      expect(keys[LootTier.common]!.earned, 2);
    });

    test('80 active days in one branch earns 5 Rare and 1 Epic', () {
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: [water],
        logs: logsFor(consecutiveDates('2026-01-01', 80), ['water']),
        claimedLoot: const [],
      );
      expect(keys[LootTier.rare]!.earned, 5);
      expect(keys[LootTier.epic]!.earned, 1);
      expect(keys[LootTier.legendary]!.earned, 0);
      // Water is not a keystone, so no Common Keys.
      expect(keys[LootTier.common]!.earned, 0);
    });

    test('all 25 nodes across 5 branches earns the Legendary Key', () {
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: keystonePerBranch,
        logs: logsFor(
          consecutiveDates('2026-01-01', 80),
          keystonePerBranch.map((h) => h.id).toList(),
        ),
        claimedLoot: const [],
      );
      expect(keys[LootTier.rare]!.earned, 25);
      expect(keys[LootTier.epic]!.earned, 5);
      expect(keys[LootTier.legendary]!.earned, 1);
      // 80 days = 11 full weeks per keystone, 5 keystones.
      expect(keys[LootTier.common]!.earned, 55);
    });

    test('4 maxed branches is not Legendary', () {
      final four = keystonePerBranch.take(4).toList();
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: keystonePerBranch,
        logs: logsFor(
          consecutiveDates('2026-01-01', 80),
          four.map((h) => h.id).toList(),
        ),
        claimedLoot: const [],
      );
      expect(keys[LootTier.epic]!.earned, 4);
      expect(keys[LootTier.legendary]!.earned, 0);
    });

    test('claimed loot is subtracted per tier and available never < 0', () {
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: [exercise],
        logs: logsFor(consecutiveDates('2026-01-01', 15), ['exercise']),
        claimedLoot: const [
          LootItem(
            id: 'l1',
            tier: LootTier.common,
            title: 'Coffee',
            claimedAtDate: '2026-01-08',
          ),
          LootItem(
            id: 'l2',
            tier: LootTier.rare,
            title: 'Book',
            claimedAtDate: '2026-01-06',
          ),
          LootItem(
            id: 'l3',
            tier: LootTier.epic,
            title: 'Overclaimed',
            claimedAtDate: '2026-01-10',
          ),
        ],
      );
      expect(
        keys[LootTier.common],
        const LootKeyBalance(earned: 2, claimed: 1),
      );
      expect(keys[LootTier.common]!.available, 1);
      expect(keys[LootTier.rare], const LootKeyBalance(earned: 2, claimed: 1));
      expect(keys[LootTier.rare]!.available, 1);
      expect(keys[LootTier.epic]!.available, 0);
    });

    test('season filter ignores logs and claims outside the season', () {
      final season = Season(
        id: 's2',
        name: 'Spring',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 6, 29),
      );
      final keys = RpgEngine.calculateAvailableLootKeys(
        habits: [exercise],
        logs: [
          ...logsFor(consecutiveDates('2026-03-01', 30), ['exercise']),
          ...logsFor(consecutiveDates('2026-04-01', 7), ['exercise']),
        ],
        claimedLoot: const [
          LootItem(
            id: 'old',
            tier: LootTier.common,
            title: 'Old',
            claimedAtDate: '2026-03-10',
          ),
        ],
        season: season,
      );
      expect(
        keys[LootTier.common],
        const LootKeyBalance(earned: 1, claimed: 0),
      );
      expect(keys[LootTier.rare]!.earned, 1);
    });
  });

  group('models', () {
    test('JSON round-trips preserve equality', () {
      final season = Season(
        id: 's1',
        name: 'Winter',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 3, 31),
        isArchived: true,
      );
      final values = <Object>[
        const BranchConfig(
          branch: BranchType.craft,
          baseLevel: 3,
          buffs: ['Flow', 'Music on'],
          debuffs: ['Rust'],
        ),
        const Character(
          name: 'Ari',
          classTitle: 'Artificer',
          signatureText: 'Ship it',
          currentSeasonId: 's1',
        ),
        water.copyWith(activeHalfMonth: ActiveHalfMonth.secondHalf),
        DailyLog(dateString: '2026-01-01', completedHabitIds: ['a', 'b']),
        const Quest(
          id: 'q',
          title: 'Run 10k',
          isMainQuest: true,
          branch: BranchType.body,
          difficulty: 4,
          monthIndex: 2,
          rewardText: 'New shoes',
        ),
        const LootItem(
          id: 'l',
          tier: LootTier.legendary,
          title: 'Trip',
          claimedAtDate: '2026-03-31',
        ),
        season,
      ];
      final decoders = <Object Function(Map<String, dynamic>)>[
        BranchConfig.fromJson,
        Character.fromJson,
        Habit.fromJson,
        DailyLog.fromJson,
        Quest.fromJson,
        LootItem.fromJson,
        Season.fromJson,
      ];
      for (var i = 0; i < values.length; i++) {
        final json = (values[i] as dynamic).toJson() as Map<String, dynamic>;
        expect(decoders[i](json), values[i]);
      }
      expect(season.toJson()['startDate'], '2026-01-01');
    });

    test('copyWith changes only the given fields', () {
      final updated = exercise.copyWith(isKeystone: false, title: 'Lift');
      expect(updated.isKeystone, isFalse);
      expect(updated.title, 'Lift');
      expect(updated.id, exercise.id);
      expect(updated.branch, exercise.branch);
    });

    test('DailyLog habit ids are unmodifiable', () {
      final log = DailyLog(dateString: '2026-01-01', completedHabitIds: ['a']);
      expect(() => log.completedHabitIds.add('b'), throwsUnsupportedError);
    });

    test('branch types expose display names and hex colors', () {
      expect(BranchType.values.map((b) => b.name), [
        'mind',
        'body',
        'craft',
        'bond',
        'empire',
      ]);
      expect(BranchType.mind.displayName, 'Mind');
      expect(BranchType.mind.hexColor, matches(RegExp(r'^#[0-9A-F]{6}$')));
      expect(BranchType.values.map((b) => b.colorValue).toSet().length, 5);
    });
  });
}
