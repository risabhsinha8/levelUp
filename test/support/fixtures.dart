/// Test-only data and helpers. The app itself ships no seed data: real users
/// start in onboarding with an empty database.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/data/reminder_scheduler.dart';
import 'package:level_up/data/rpg_repository.dart';
import 'package:level_up/domain/reminder_plan.dart';
import 'package:level_up/domain/new_character.dart';
import 'package:level_up/main.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/providers/rpg_store_provider.dart';
import 'package:level_up/screens/home_shell.dart';

/// Records what the app would schedule instead of calling the OS.
class FakeReminderScheduler implements ReminderScheduler {
  /// The last plan handed over (what the device would have pending).
  ReminderPlan scheduled = ReminderPlan.empty;
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> replaceAll(ReminderPlan plan) async => scheduled = plan;
}

/// Repository fake that keeps the state in memory, applying each granular
/// write the way the SQLite repository does. [saveCount] counts writes.
class InMemoryRepository implements RpgRepository {
  InMemoryRepository([this.saved]);

  RpgState? saved;
  int saveCount = 0;

  RpgState get _state {
    final state = saved;
    if (state == null) throw StateError('No character yet.');
    return state;
  }

  void _write(RpgState next) {
    saved = next;
    saveCount++;
  }

  static List<T> _upsert<T>(List<T> list, T item, String Function(T) id) {
    final index = list.indexWhere((e) => id(e) == id(item));
    return index == -1 ? [...list, item] : ([...list]..[index] = item);
  }

  @override
  Future<bool> hasCharacter() async => saved != null;

  @override
  Future<RpgState?> loadFullState() async => saved;

  @override
  Future<void> initializeFromOnboarding(RpgState initial) async {
    if (saved != null) throw StateError('A character already exists.');
    _write(initial);
  }

  @override
  Future<void> replaceAllData(RpgState state) async => _write(state);

  @override
  Future<void> wipeAllData() async {
    saved = null;
    saveCount++;
  }

  @override
  Future<bool> toggleHabitForDate(String habitId, String dateString) async {
    final logs = [..._state.logs];
    final index = logs.indexWhere((l) => l.dateString == dateString);
    var done = true;
    if (index == -1) {
      logs.add(DailyLog(dateString: dateString, completedHabitIds: [habitId]));
    } else {
      final ids = [...logs[index].completedHabitIds];
      done = !ids.remove(habitId);
      if (done) ids.add(habitId);
      if (ids.isEmpty) {
        logs.removeAt(index);
      } else {
        logs[index] = logs[index].copyWith(completedHabitIds: ids);
      }
    }
    _write(_state.copyWith(logs: logs));
    return done;
  }

  @override
  Future<void> upsertHabits(List<Habit> habits) async {
    for (final habit in habits) {
      await upsertHabit(habit);
    }
    saveCount -= habits.length - 1; // one transaction
  }

  @override
  Future<void> upsertHabit(Habit habit) async {
    final habits = [
      for (final h in _state.habits)
        habit.isKeystone &&
                !habit.isArchived &&
                h.id != habit.id &&
                h.branch == habit.branch &&
                h.isKeystone &&
                !h.isArchived
            ? h.copyWith(isKeystone: false)
            : h,
    ];
    _write(_state.copyWith(habits: _upsert(habits, habit, (h) => h.id)));
  }

  @override
  Future<void> deleteHabit(String habitId) async => _write(
    _state.copyWith(
      habits: [
        for (final h in _state.habits)
          if (h.id != habitId) h,
      ],
    ),
  );

  @override
  Future<void> updateBranchBuffDebuff(BranchConfig config) async => _write(
    _state.copyWith(
      branchConfigs: _upsert(
        _state.branchConfigs,
        config,
        (c) => c.branch.name,
      ),
    ),
  );

  @override
  Future<void> renameBranch(BranchConfig config) =>
      updateBranchBuffDebuff(config);

  @override
  Future<void> updateForgedNodes(BranchConfig config) =>
      updateBranchBuffDebuff(config);

  @override
  Future<void> upsertQuest(Quest quest) async {
    final quests = [
      for (final q in _state.quests)
        quest.isMainQuest &&
                q.id != quest.id &&
                q.isMainQuest &&
                q.monthIndex == quest.monthIndex &&
                (q.seasonId == null || q.seasonId == quest.seasonId)
            ? q.copyWith(isMainQuest: false)
            : q,
    ];
    _write(_state.copyWith(quests: _upsert(quests, quest, (q) => q.id)));
  }

  @override
  Future<void> completeQuest(String questId, {bool completed = true}) async =>
      _write(
        _state.copyWith(
          quests: [
            for (final q in _state.quests)
              q.id == questId ? q.copyWith(isCompleted: completed) : q,
          ],
        ),
      );

  @override
  Future<void> upsertLootItem(LootItem item) async =>
      _write(_state.copyWith(loot: _upsert(_state.loot, item, (l) => l.id)));

  @override
  Future<void> claimLootItem(LootItem claim) => upsertLootItem(claim);

  @override
  Future<void> saveSignature(String seasonId, SeasonOath? oath) async => _write(
    _state.copyWith(
      seasons: [
        for (final s in _state.seasons)
          s.id != seasonId
              ? s
              : oath == null
              ? s.copyWith(clearOath: true)
              : s.copyWith(oath: oath),
      ],
    ),
  );

  @override
  Future<void> saveReflection(MonthReflection reflection) async => _write(
    _state.copyWith(
      reflections: _upsert(_state.reflections, reflection, (r) => r.monthKey),
    ),
  );

  @override
  Future<void> pivotHabit({
    required Habit old,
    required Habit replacement,
    required MonthReflection reflection,
  }) async {
    final habits = _upsert(
      _upsert(_state.habits, old, (h) => h.id),
      replacement,
      (h) => h.id,
    );
    _write(
      _state.copyWith(
        habits: habits,
        reflections: _upsert(_state.reflections, reflection, (r) => r.monthKey),
      ),
    );
  }

  @override
  Future<void> updateCharacter(Character character) async =>
      _write(_state.copyWith(character: character));

  @override
  Future<void> prestigeSeason({
    required Season completed,
    required RpgState next,
  }) async => _write(next);
}

/// Pumps the app with [state] (null = first install) and a fixed clock.
/// Pass [repository] to control loading; with [settle] false, only one frame
/// is pumped (e.g. to see the startup loading screen).
Future<InMemoryRepository> pumpLevelUp(
  WidgetTester tester, {
  required DateTime now,
  RpgState? state,
  InMemoryRepository? repository,
  Size size = const Size(800, 2600),
  bool settle = true,
  math.Random? random,
  FakeReminderScheduler? reminders,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = repository ?? InMemoryRepository(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        rpgRepositoryProvider.overrideWithValue(repo),
        if (random != null) randomProvider.overrideWithValue(random),
        reminderSchedulerProvider.overrideWithValue(
          reminders ?? FakeReminderScheduler(),
        ),
      ],
      child: const LevelUpApp(useGoogleFonts: false),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return repo;
}

/// The current state, read from inside the running app.
RpgState readState(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(HomeShell)),
).read(rpgStateProvider);

/// A level-0 character with one keystone per branch and Season 1 today.
RpgState buildFreshState(DateTime today) {
  var next = 0;
  return buildNewCharacterState(
    name: 'New Adventurer',
    classTitle: 'Novice',
    keystones: const [
      KeystoneChoice(branch: BranchType.mind, title: 'Read'),
      KeystoneChoice(branch: BranchType.body, title: 'Move'),
      KeystoneChoice(branch: BranchType.craft, title: 'Create'),
      KeystoneChoice(branch: BranchType.bond, title: 'Reach out'),
      KeystoneChoice(branch: BranchType.empire, title: 'Build'),
    ],
    today: today,
    seasonId: 'season-1',
    newId: () => 'habit-${next++}',
  );
}

/// The Level 9 "Recovering Couch Potato", 18 days into Season 1, with today
/// left empty:
///
/// | Branch | Base | Active days | Nodes | Feats | Level |
/// |--------|------|-------------|-------|-------|-------|
/// | Body   | 1    | 17          | 2     | 0     | 3     |
/// | Mind   | 1    | 17          | 2     | 0     | 3     |
/// | Craft  | 0    | 11          | 1     | 1     | 2     |
/// | Bond   | 0    | 6           | 1     | 0     | 1     |
/// | Empire | 0    | 4           | 0     | 0     | 0     |
RpgState buildDemoState(DateTime today) {
  final todayDate = DateTime.utc(today.year, today.month, today.day);
  final seasonStart = todayDate.subtract(const Duration(days: 17));
  final season = Season(
    id: 'season-1',
    name: 'Season 1',
    startDate: seasonStart,
    endDate: Season.quarterEndOf(seasonStart),
  );

  return RpgState(
    character: Character(
      name: 'Rowan',
      classTitle: 'Recovering Couch Potato',
      signatureText: 'Small steps, every season.',
      currentSeasonId: season.id,
    ),
    branchConfigs: _demoBranchConfigs,
    habits: _demoHabits,
    logs: [
      // Days 1–17; today (day 18) has no check-ins yet, so no log.
      for (var i = 0; i < 17; i++)
        DailyLog(
          dateString: toDateString(seasonStart.add(Duration(days: i))),
          completedHabitIds: [
            for (final entry in _demoPatterns.entries)
              if (entry.value[i] == '1') entry.key,
          ],
        ),
    ],
    quests: _demoQuests,
    loot: [
      ..._demoLoot,
      LootItem(
        id: 'loot-sketchbook-claim',
        tier: LootTier.rare,
        title: 'Fancy new sketchbook',
        claimedAtDate: toDateString(seasonStart.add(const Duration(days: 6))),
        claimedAt: seasonStart.add(const Duration(days: 6, hours: 19)),
      ),
    ],
    seasons: [season],
  );
}

const _demoBranchConfigs = [
  BranchConfig(
    branch: BranchType.mind,
    baseLevel: 1,
    forgedNodeCount: 2,
    buffs: ['Book on the pillow every morning', 'Podcast on the commute'],
    debuffs: ['Doomscrolling before breakfast'],
  ),
  BranchConfig(
    branch: BranchType.body,
    baseLevel: 1,
    forgedNodeCount: 2,
    buffs: [
      'Leave gym clothes out the night before',
      'Water bottle on the desk',
    ],
    debuffs: ['Phone in bed past 11 PM', 'Late night scrolling'],
  ),
  BranchConfig(
    branch: BranchType.craft,
    forgedNodeCount: 1,
    buffs: ['Sketchbook and pen live on the desk'],
    debuffs: ['Waiting for the "perfect" idea'],
  ),
  BranchConfig(
    branch: BranchType.bond,
    forgedNodeCount: 1,
    buffs: ['Call during the evening walk'],
    debuffs: ['Leaving messages on read'],
  ),
  BranchConfig(
    branch: BranchType.empire,
    buffs: ['First 30 minutes after work are for the project'],
    debuffs: ['Starting a new idea instead of finishing one'],
  ),
];

const _demoHabits = [
  Habit(
    id: 'habit-exercise',
    branch: BranchType.body,
    title: 'Exercise',
    targetCriteria: '20 min movement',
    isKeystone: true,
  ),
  Habit(
    id: 'habit-water',
    branch: BranchType.body,
    title: 'Water',
    targetCriteria: '13 cups daily',
  ),
  Habit(
    id: 'habit-sleep',
    branch: BranchType.body,
    title: 'Sleep',
    targetCriteria: '8 hrs',
  ),
  Habit(
    id: 'habit-sketching',
    branch: BranchType.craft,
    title: 'Sketching',
    targetCriteria: '1 rough thumbnail daily',
    isKeystone: true,
  ),
  Habit(
    id: 'habit-french',
    branch: BranchType.craft,
    title: 'French practice',
    targetCriteria: '1 lesson',
  ),
  Habit(
    id: 'habit-reading',
    branch: BranchType.mind,
    title: 'Reading',
    targetCriteria: '10 pages',
    isKeystone: true,
  ),
  Habit(
    id: 'habit-meditation',
    branch: BranchType.mind,
    title: 'Meditation',
    targetCriteria: '5 min',
  ),
  Habit(
    id: 'habit-call',
    branch: BranchType.bond,
    title: 'Call family/friends',
    targetCriteria: '1 real conversation',
    isKeystone: true,
  ),
  Habit(
    id: 'habit-side-project',
    branch: BranchType.empire,
    title: 'Work on side project',
    targetCriteria: '30 focused min',
    isKeystone: true,
  ),
];

/// One string per habit; character `i` is season day `i + 1` ('1' = done).
const _demoPatterns = {
  'habit-exercise': '111111101101101100', // 7-day keystone run -> Common Key
  'habit-water': '111011111011111110',
  'habit-sleep': '110110111011011010',
  'habit-reading': '111101111111011110', // days 6-12 -> Common Key
  'habit-meditation': '101010101010101010',
  'habit-sketching': '100110010110010010',
  'habit-french': '010000100000100000',
  'habit-call': '100100100100100100',
  'habit-side-project': '000000001001010100',
};

const _demoQuests = [
  Quest(
    id: 'quest-5k',
    title: 'Run a 5K without stopping',
    isMainQuest: true,
    branch: BranchType.body,
    difficulty: 4,
    monthIndex: 3,
    rewardText: 'New running shoes',
  ),
  Quest(
    id: 'quest-sketchbook',
    title: 'Fill the first 20 pages of a sketchbook',
    branch: BranchType.craft,
    difficulty: 2,
    isCompleted: true,
    rewardText: 'Brush pen set',
  ),
  Quest(
    id: 'quest-book',
    title: 'Finish one non-fiction book',
    isMainQuest: true,
    branch: BranchType.mind,
    difficulty: 3,
    monthIndex: 1,
    rewardText: 'A new hardcover of my choice',
  ),
  Quest(
    id: 'quest-french-words',
    title: 'Master 50 French words',
    branch: BranchType.craft,
    difficulty: 2,
    monthIndex: 1,
  ),
  Quest(
    id: 'quest-chapters',
    title: 'Read 10 chapters in one sitting',
    branch: BranchType.mind,
    difficulty: 3,
    monthIndex: 1,
  ),
  Quest(
    id: 'quest-dinner',
    title: 'Host a dinner for friends',
    branch: BranchType.bond,
    difficulty: 3,
    monthIndex: 2,
  ),
  Quest(
    id: 'quest-launch',
    title: 'Ship the side project landing page',
    isMainQuest: true,
    branch: BranchType.empire,
    difficulty: 5,
    monthIndex: 3,
    rewardText: 'Celebration dinner',
  ),
  Quest(
    id: 'quest-french',
    title: 'Order a whole meal in French',
    branch: BranchType.craft,
    difficulty: 3,
    monthIndex: 2,
  ),
];

const _demoLoot = [
  LootItem(id: 'loot-coffee', tier: LootTier.common, title: 'Fancy coffee'),
  LootItem(
    id: 'loot-ice-cream',
    tier: LootTier.common,
    title: 'Ice cream party',
  ),
  LootItem(id: 'loot-tv', tier: LootTier.rare, title: 'Binge TV night'),
  LootItem(id: 'loot-game', tier: LootTier.rare, title: 'New video game'),
  LootItem(id: 'loot-guitar', tier: LootTier.epic, title: 'New guitar gear'),
  LootItem(id: 'loot-concert', tier: LootTier.epic, title: 'Concert tickets'),
  LootItem(
    id: 'loot-trip',
    tier: LootTier.legendary,
    title: 'Weekend trip away',
  ),
];
