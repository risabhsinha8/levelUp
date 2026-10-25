import 'rpg_models.dart';

/// The full persisted app state: everything the character sheet is built from.
class RpgState {
  RpgState({
    required this.character,
    required List<BranchConfig> branchConfigs,
    List<Habit> habits = const [],
    List<DailyLog> logs = const [],
    List<Quest> quests = const [],
    List<LootItem> loot = const [],
    required List<Season> seasons,
    List<MonthReflection> reflections = const [],
  }) : branchConfigs = List.unmodifiable(branchConfigs),
       habits = List.unmodifiable(habits),
       logs = List.unmodifiable(logs),
       quests = List.unmodifiable(quests),
       loot = List.unmodifiable(loot),
       seasons = List.unmodifiable(seasons),
       reflections = List.unmodifiable(reflections);

  /// Bump when the JSON shape changes incompatibly.
  static const int schemaVersion = 1;

  final Character character;
  final List<BranchConfig> branchConfigs;
  final List<Habit> habits;
  final List<DailyLog> logs;
  final List<Quest> quests;
  final List<LootItem> loot;
  final List<Season> seasons;
  final List<MonthReflection> reflections;

  Season get currentSeason =>
      seasons.firstWhere((s) => s.id == character.currentSeasonId);

  /// Quests of the current season (quests without a season id belong to it).
  List<Quest> get currentQuests => [
    for (final q in quests)
      if (q.seasonId == null || q.seasonId == character.currentSeasonId) q,
  ];

  /// Completed seasons, most recent first.
  List<Season> get archivedSeasons =>
      seasons.where((s) => s.isArchived).toList().reversed.toList();

  /// Config for [branch], or a level-0 default if none is stored.
  BranchConfig configFor(BranchType branch) => branchConfigs.firstWhere(
    (c) => c.branch == branch,
    orElse: () => BranchConfig(branch: branch),
  );

  /// All habits of [branch], including archived ones (their history still
  /// counts).
  List<Habit> habitsFor(BranchType branch) =>
      habits.where((h) => h.branch == branch).toList();

  /// Whether [habitId] has been checked off on any day.
  bool hasCheckIns(String habitId) =>
      logs.any((l) => l.completedHabitIds.contains(habitId));

  /// Habits the user can still check off and edit.
  List<Habit> get activeHabits => habits.where((h) => !h.isArchived).toList();

  /// The active keystone of [branch], if any.
  Habit? keystoneFor(BranchType branch) => habits
      .where((h) => h.branch == branch && h.isKeystone && !h.isArchived)
      .firstOrNull;

  /// Ids of habits completed on [date] (merging duplicate logs).
  Set<String> completedOn(DateTime date) {
    final dateString = toDateString(date);
    return {
      for (final log in logs)
        if (log.dateString == dateString) ...log.completedHabitIds,
    };
  }

  /// Habits scheduled for [date]'s half of the month, plus any completed on
  /// [date] (e.g. a habit pivoted out later), grouped in branch order.
  List<Habit> habitsShownOn(DateTime date) {
    final done = completedOn(date);
    return [
      for (final branch in BranchType.values)
        for (final h in habits)
          if (h.branch == branch && (h.isActiveOn(date) || done.contains(h.id)))
            h,
    ];
  }

  /// Reflection for the month of [date], or an empty one.
  MonthReflection reflectionFor(DateTime date) {
    final key = MonthReflection.keyFor(date);
    return reflections.firstWhere(
      (r) => r.monthKey == key,
      orElse: () => MonthReflection(monthKey: key),
    );
  }

  RpgState copyWith({
    Character? character,
    List<BranchConfig>? branchConfigs,
    List<Habit>? habits,
    List<DailyLog>? logs,
    List<Quest>? quests,
    List<LootItem>? loot,
    List<Season>? seasons,
    List<MonthReflection>? reflections,
  }) {
    return RpgState(
      character: character ?? this.character,
      branchConfigs: branchConfigs ?? this.branchConfigs,
      habits: habits ?? this.habits,
      logs: logs ?? this.logs,
      quests: quests ?? this.quests,
      loot: loot ?? this.loot,
      seasons: seasons ?? this.seasons,
      reflections: reflections ?? this.reflections,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'character': character.toJson(),
    'branchConfigs': [for (final c in branchConfigs) c.toJson()],
    'habits': [for (final h in habits) h.toJson()],
    'logs': [for (final l in logs) l.toJson()],
    'quests': [for (final q in quests) q.toJson()],
    'loot': [for (final l in loot) l.toJson()],
    'seasons': [for (final s in seasons) s.toJson()],
    'reflections': [for (final r in reflections) r.toJson()],
  };

  factory RpgState.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) fromJson) => [
      for (final item in json[key] as List<dynamic>? ?? const [])
        fromJson(item as Map<String, dynamic>),
    ];

    return RpgState(
      character: Character.fromJson(json['character'] as Map<String, dynamic>),
      branchConfigs: list('branchConfigs', BranchConfig.fromJson),
      habits: list('habits', Habit.fromJson),
      logs: list('logs', DailyLog.fromJson),
      quests: list('quests', Quest.fromJson),
      loot: list('loot', LootItem.fromJson),
      seasons: list('seasons', Season.fromJson),
      reflections: list('reflections', MonthReflection.fromJson),
    );
  }
}
