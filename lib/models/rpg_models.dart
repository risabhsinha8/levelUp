/// Immutable domain models for the Skill Tree RPG habit tracker.
///
/// These classes are pure Dart (no Flutter imports) so they can be used by
/// the domain engine, repositories and tests alike. Dates are stored as
/// `YYYY-MM-DD` strings in JSON.
library;

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------

/// Formats [date] as a `YYYY-MM-DD` calendar date string.
String toDateString(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Parses a `YYYY-MM-DD` string into a UTC midnight [DateTime].
///
/// UTC is used so day arithmetic is never skewed by daylight-saving shifts.
DateTime parseDateString(String dateString) {
  final parts = dateString.split('-');
  if (parts.length != 3) {
    throw FormatException('Expected YYYY-MM-DD', dateString);
  }
  return DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The five core attribute branches of the skill tree.
enum BranchType {
  mind('Mind', 0xFF6366F1), // Indigo
  body('Body', 0xFF10B981), // Emerald
  craft('Craft', 0xFFF59E0B), // Amber
  bond('Bond', 0xFFF43F5E), // Rose
  empire('Empire', 0xFFA855F7); // Purple

  const BranchType(this.displayName, this.colorValue);

  final String displayName;

  /// ARGB color, e.g. `Color(branch.colorValue)` in Flutter.
  final int colorValue;

  /// Color as a `#RRGGBB` hex string.
  String get hexColor =>
      '#${(colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Which half of each month a habit is scheduled for.
enum ActiveHalfMonth {
  both,
  firstHalf,
  secondHalf;

  /// Last day of the first half of every month (Half 1 = days 1–15).
  static const int firstHalfLastDay = 15;

  /// The half (never [both]) that [date] falls in.
  static ActiveHalfMonth of(DateTime date) =>
      date.day <= firstHalfLastDay ? firstHalf : secondHalf;

  /// Whether a habit scheduled for this value is active on [date].
  bool includes(DateTime date) => this == both || this == of(date);
}

enum LootTier { common, rare, epic, legendary }

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class BranchConfig {
  const BranchConfig({
    required this.branch,
    this.baseLevel = 0,
    this.buffs = const [],
    this.debuffs = const [],
    this.forgedNodeCount = 0,
  });

  final BranchType branch;

  /// Level carried over from past seasons.
  final int baseLevel;

  /// Skill nodes the user has forged (long-pressed to claim) this season.
  /// Only forged nodes add levels and Rare/Epic/Legendary keys; earned ones
  /// beyond this count are ready to forge. Reset to 0 at season rollover.
  final int forgedNodeCount;

  /// Enablers that make the branch's habits easier, e.g. "Gym clothes laid
  /// out".
  final List<String> buffs;

  /// Friction that works against the branch, e.g. "Late night scrolling".
  final List<String> debuffs;

  BranchConfig copyWith({
    BranchType? branch,
    int? baseLevel,
    List<String>? buffs,
    List<String>? debuffs,
    int? forgedNodeCount,
  }) {
    return BranchConfig(
      branch: branch ?? this.branch,
      baseLevel: baseLevel ?? this.baseLevel,
      buffs: buffs ?? this.buffs,
      debuffs: debuffs ?? this.debuffs,
      forgedNodeCount: forgedNodeCount ?? this.forgedNodeCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'branch': branch.name,
    'baseLevel': baseLevel,
    'buffs': buffs,
    'debuffs': debuffs,
    'forgedNodeCount': forgedNodeCount,
  };

  /// Also reads the older single `buffText` / `debuffText` fields. Backups
  /// from before node forging count every earned node as forged, so their
  /// levels are unchanged.
  factory BranchConfig.fromJson(Map<String, dynamic> json) {
    List<String> strings(String listKey, String legacyKey) {
      final list = json[listKey] as List<dynamic>?;
      if (list != null) return List.unmodifiable(list.cast<String>());
      final legacy = json[legacyKey] as String? ?? '';
      return legacy.isEmpty ? const [] : [legacy];
    }

    return BranchConfig(
      branch: BranchType.values.byName(json['branch'] as String),
      baseLevel: json['baseLevel'] as int? ?? 0,
      buffs: strings('buffs', 'buffText'),
      debuffs: strings('debuffs', 'debuffText'),
      forgedNodeCount: json['forgedNodeCount'] as int? ?? 5,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BranchConfig &&
      other.branch == branch &&
      other.baseLevel == baseLevel &&
      _listEquals(other.buffs, buffs) &&
      _listEquals(other.debuffs, debuffs) &&
      other.forgedNodeCount == forgedNodeCount;

  @override
  int get hashCode => Object.hash(
    branch,
    baseLevel,
    Object.hashAll(buffs),
    Object.hashAll(debuffs),
    forgedNodeCount,
  );
}

class Character {
  const Character({
    required this.name,
    required this.classTitle,
    this.signatureText = '',
    required this.currentSeasonId,
  });

  final String name;
  final String classTitle;
  final String signatureText;
  final String currentSeasonId;

  Character copyWith({
    String? name,
    String? classTitle,
    String? signatureText,
    String? currentSeasonId,
  }) {
    return Character(
      name: name ?? this.name,
      classTitle: classTitle ?? this.classTitle,
      signatureText: signatureText ?? this.signatureText,
      currentSeasonId: currentSeasonId ?? this.currentSeasonId,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'classTitle': classTitle,
    'signatureText': signatureText,
    'currentSeasonId': currentSeasonId,
  };

  factory Character.fromJson(Map<String, dynamic> json) => Character(
    name: json['name'] as String,
    classTitle: json['classTitle'] as String,
    signatureText: json['signatureText'] as String? ?? '',
    currentSeasonId: json['currentSeasonId'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is Character &&
      other.name == name &&
      other.classTitle == classTitle &&
      other.signatureText == signatureText &&
      other.currentSeasonId == currentSeasonId;

  @override
  int get hashCode =>
      Object.hash(name, classTitle, signatureText, currentSeasonId);
}

/// A stretch of days during which a habit was its branch's keystone.
class KeystonePeriod {
  const KeystonePeriod({this.from, this.to});

  /// First day (`YYYY-MM-DD`, inclusive); null = since the habit began.
  final String? from;

  /// Last day (inclusive); null = still the keystone.
  final String? to;

  bool contains(String dateString) =>
      (from == null || dateString.compareTo(from!) >= 0) &&
      (to == null || dateString.compareTo(to!) <= 0);

  Map<String, dynamic> toJson() => {
    if (from != null) 'from': from,
    if (to != null) 'to': to,
  };

  factory KeystonePeriod.fromJson(Map<String, dynamic> json) =>
      KeystonePeriod(from: json['from'] as String?, to: json['to'] as String?);

  @override
  bool operator ==(Object other) =>
      other is KeystonePeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class Habit {
  const Habit({
    required this.id,
    required this.branch,
    required this.title,
    this.targetCriteria = '',
    this.isKeystone = false,
    this.activeHalfMonth = ActiveHalfMonth.both,
    this.isArchived = false,
    this.keystonePeriods = const [],
  });

  final String id;
  final BranchType branch;
  final String title;

  /// Free-text success criteria, e.g. "13 cups daily".
  final String targetCriteria;

  /// The branch's daily non-negotiable. Only one per branch.
  final bool isKeystone;
  final ActiveHalfMonth activeHalfMonth;

  /// Deleted by the user but kept because it has logged history, so the
  /// branch points (and keystone streaks) it earned still count.
  final bool isArchived;

  /// When this habit was a keystone. Empty means "for its whole history"
  /// if [isKeystone] (keystones created at onboarding), never otherwise.
  /// Recorded by [withKeystone] so moving the star never rewrites history.
  final List<KeystonePeriod> keystonePeriods;

  /// Whether this habit was its branch's keystone on [dateString].
  bool wasKeystoneOn(String dateString) => keystonePeriods.isEmpty
      ? isKeystone
      : keystonePeriods.any((p) => p.contains(dateString));

  /// Whether this habit is or ever was a keystone.
  bool get hasKeystoneHistory => isKeystone || keystonePeriods.isNotEmpty;

  /// Stars or unstars this habit from [today] (`YYYY-MM-DD`) on, keeping
  /// the days it was already the keystone.
  Habit withKeystone(bool keystone, String today) {
    if (keystone == isKeystone) return this;
    if (keystone) {
      return copyWith(
        isKeystone: true,
        keystonePeriods: [
          ...keystonePeriods,
          KeystonePeriod(from: today),
        ],
      );
    }
    return copyWith(
      isKeystone: false,
      keystonePeriods: keystonePeriods.isEmpty
          ? [KeystonePeriod(to: today)]
          : [
              for (final p in keystonePeriods)
                p.to == null ? KeystonePeriod(from: p.from, to: today) : p,
            ],
    );
  }

  /// Whether this habit is scheduled for [date]'s half of the month.
  /// Archived habits are never scheduled.
  bool isActiveOn(DateTime date) =>
      !isArchived && activeHalfMonth.includes(date);

  Habit copyWith({
    String? id,
    BranchType? branch,
    String? title,
    String? targetCriteria,
    bool? isKeystone,
    ActiveHalfMonth? activeHalfMonth,
    bool? isArchived,
    List<KeystonePeriod>? keystonePeriods,
  }) {
    return Habit(
      id: id ?? this.id,
      branch: branch ?? this.branch,
      title: title ?? this.title,
      targetCriteria: targetCriteria ?? this.targetCriteria,
      isKeystone: isKeystone ?? this.isKeystone,
      activeHalfMonth: activeHalfMonth ?? this.activeHalfMonth,
      isArchived: isArchived ?? this.isArchived,
      keystonePeriods: keystonePeriods ?? this.keystonePeriods,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch': branch.name,
    'title': title,
    'targetCriteria': targetCriteria,
    'isKeystone': isKeystone,
    'activeHalfMonth': activeHalfMonth.name,
    if (isArchived) 'isArchived': true,
    if (keystonePeriods.isNotEmpty)
      'keystonePeriods': [for (final p in keystonePeriods) p.toJson()],
  };

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    id: json['id'] as String,
    branch: BranchType.values.byName(json['branch'] as String),
    title: json['title'] as String,
    targetCriteria: json['targetCriteria'] as String? ?? '',
    isKeystone: json['isKeystone'] as bool? ?? false,
    activeHalfMonth: ActiveHalfMonth.values.byName(
      json['activeHalfMonth'] as String? ?? ActiveHalfMonth.both.name,
    ),
    isArchived: json['isArchived'] as bool? ?? false,
    keystonePeriods: [
      for (final p in json['keystonePeriods'] as List<dynamic>? ?? const [])
        KeystonePeriod.fromJson(p as Map<String, dynamic>),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is Habit &&
      other.id == id &&
      other.branch == branch &&
      other.title == title &&
      other.targetCriteria == targetCriteria &&
      other.isKeystone == isKeystone &&
      other.activeHalfMonth == activeHalfMonth &&
      other.isArchived == isArchived &&
      _listEquals(other.keystonePeriods, keystonePeriods);

  @override
  int get hashCode => Object.hash(
    id,
    branch,
    title,
    targetCriteria,
    isKeystone,
    activeHalfMonth,
    isArchived,
    Object.hashAll(keystonePeriods),
  );
}

class DailyLog {
  DailyLog({
    required this.dateString,
    List<String> completedHabitIds = const [],
  }) : completedHabitIds = List.unmodifiable(completedHabitIds);

  /// Calendar date as `YYYY-MM-DD`.
  final String dateString;
  final List<String> completedHabitIds;

  DailyLog copyWith({String? dateString, List<String>? completedHabitIds}) {
    return DailyLog(
      dateString: dateString ?? this.dateString,
      completedHabitIds: completedHabitIds ?? this.completedHabitIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'dateString': dateString,
    'completedHabitIds': completedHabitIds,
  };

  factory DailyLog.fromJson(Map<String, dynamic> json) => DailyLog(
    dateString: json['dateString'] as String,
    completedHabitIds: (json['completedHabitIds'] as List<dynamic>? ?? const [])
        .cast<String>(),
  );

  @override
  bool operator ==(Object other) =>
      other is DailyLog &&
      other.dateString == dateString &&
      _listEquals(other.completedHabitIds, completedHabitIds);

  @override
  int get hashCode =>
      Object.hash(dateString, Object.hashAll(completedHabitIds));
}

class Quest {
  const Quest({
    required this.id,
    required this.title,
    this.isMainQuest = false,
    required this.branch,
    this.difficulty = 1,
    this.isCompleted = false,
    this.monthIndex = 1,
    this.rewardText = '',
    this.seasonId,
  }) : assert(difficulty >= 1 && difficulty <= 5),
       assert(monthIndex >= 1 && monthIndex <= 3);

  final String id;
  final String title;
  final bool isMainQuest;
  final BranchType branch;

  /// 1 (trivial) to 5 (legendary).
  final int difficulty;
  final bool isCompleted;

  /// Month of the season this quest belongs to, 1 to 3.
  final int monthIndex;
  final String rewardText;

  /// Season this quest belongs to. Null means the current season (quests
  /// saved before seasons were tracked); rollover stamps it.
  final String? seasonId;

  Quest copyWith({
    String? id,
    String? title,
    bool? isMainQuest,
    BranchType? branch,
    int? difficulty,
    bool? isCompleted,
    int? monthIndex,
    String? rewardText,
    String? seasonId,
  }) {
    return Quest(
      id: id ?? this.id,
      title: title ?? this.title,
      isMainQuest: isMainQuest ?? this.isMainQuest,
      branch: branch ?? this.branch,
      difficulty: difficulty ?? this.difficulty,
      isCompleted: isCompleted ?? this.isCompleted,
      monthIndex: monthIndex ?? this.monthIndex,
      rewardText: rewardText ?? this.rewardText,
      seasonId: seasonId ?? this.seasonId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isMainQuest': isMainQuest,
    'branch': branch.name,
    'difficulty': difficulty,
    'isCompleted': isCompleted,
    'monthIndex': monthIndex,
    'rewardText': rewardText,
    if (seasonId != null) 'seasonId': seasonId,
  };

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
    id: json['id'] as String,
    title: json['title'] as String,
    isMainQuest: json['isMainQuest'] as bool? ?? false,
    branch: BranchType.values.byName(json['branch'] as String),
    difficulty: json['difficulty'] as int? ?? 1,
    isCompleted: json['isCompleted'] as bool? ?? false,
    monthIndex: json['monthIndex'] as int? ?? 1,
    rewardText: json['rewardText'] as String? ?? '',
    seasonId: json['seasonId'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Quest &&
      other.id == id &&
      other.title == title &&
      other.isMainQuest == isMainQuest &&
      other.branch == branch &&
      other.difficulty == difficulty &&
      other.isCompleted == isCompleted &&
      other.monthIndex == monthIndex &&
      other.rewardText == rewardText &&
      other.seasonId == seasonId;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    isMainQuest,
    branch,
    difficulty,
    isCompleted,
    monthIndex,
    rewardText,
    seasonId,
  );
}

class LootItem {
  const LootItem({
    required this.id,
    required this.tier,
    required this.title,
    this.claimedAtDate,
    this.claimedAt,
  });

  final String id;
  final LootTier tier;
  final String title;

  /// Date a key was spent on this item, as `YYYY-MM-DD`; null for a reward
  /// still sitting in the loot table. Claimed items form the history.
  final String? claimedAtDate;

  /// Exact claim time, for the history list. May be null for older claims.
  final DateTime? claimedAt;

  bool get isClaimed => claimedAtDate != null;

  LootItem copyWith({
    String? id,
    LootTier? tier,
    String? title,
    String? claimedAtDate,
    DateTime? claimedAt,
    bool clearClaim = false,
  }) {
    return LootItem(
      id: id ?? this.id,
      tier: tier ?? this.tier,
      title: title ?? this.title,
      claimedAtDate: clearClaim ? null : claimedAtDate ?? this.claimedAtDate,
      claimedAt: clearClaim ? null : claimedAt ?? this.claimedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tier': tier.name,
    'title': title,
    'claimedAtDate': claimedAtDate,
    if (claimedAt != null) 'claimedAt': claimedAt!.toIso8601String(),
  };

  factory LootItem.fromJson(Map<String, dynamic> json) => LootItem(
    id: json['id'] as String,
    tier: LootTier.values.byName(json['tier'] as String),
    title: json['title'] as String,
    claimedAtDate: json['claimedAtDate'] as String?,
    claimedAt: json['claimedAt'] == null
        ? null
        : DateTime.parse(json['claimedAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is LootItem &&
      other.id == id &&
      other.tier == tier &&
      other.title == title &&
      other.claimedAtDate == claimedAtDate &&
      other.claimedAt == claimedAt;

  @override
  int get hashCode => Object.hash(id, tier, title, claimedAtDate, claimedAt);
}

class Season {
  const Season({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.isArchived = false,
    this.oath,
    this.summary,
  });

  /// First day of the calendar quarter containing [date]. Seasons follow
  /// the quarters: Jan 1, Apr 1, Jul 1 and Oct 1.
  static DateTime quarterStartOf(DateTime date) =>
      DateTime.utc(date.year, (date.month - 1) ~/ 3 * 3 + 1);

  /// Last day of the calendar quarter containing [date].
  static DateTime quarterEndOf(DateTime date) {
    final start = quarterStartOf(date);
    return DateTime.utc(start.year, start.month + 3, 0);
  }

  final String id;
  final String name;

  /// Inclusive first day of the season (date only).
  final DateTime startDate;

  /// Inclusive last day of the season (date only).
  final DateTime endDate;
  final bool isArchived;

  /// The signed seasonal oath, or null if not signed yet.
  final SeasonOath? oath;

  /// Final tally, set when the season is completed and archived.
  final SeasonSummary? summary;

  /// Whether the `YYYY-MM-DD` [dateString] falls within this season.
  bool containsDate(String dateString) {
    final date = parseDateString(dateString);
    final start = parseDateString(toDateString(startDate));
    final end = parseDateString(toDateString(endDate));
    return !date.isBefore(start) && !date.isAfter(end);
  }

  Season copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    bool? isArchived,
    SeasonOath? oath,
    bool clearOath = false,
    SeasonSummary? summary,
  }) {
    return Season(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isArchived: isArchived ?? this.isArchived,
      oath: clearOath ? null : oath ?? this.oath,
      summary: summary ?? this.summary,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startDate': toDateString(startDate),
    'endDate': toDateString(endDate),
    'isArchived': isArchived,
    if (oath != null) 'oath': oath!.toJson(),
    if (summary != null) 'summary': summary!.toJson(),
  };

  factory Season.fromJson(Map<String, dynamic> json) => Season(
    id: json['id'] as String,
    name: json['name'] as String,
    startDate: parseDateString(json['startDate'] as String),
    endDate: parseDateString(json['endDate'] as String),
    isArchived: json['isArchived'] as bool? ?? false,
    oath: json['oath'] == null
        ? null
        : SeasonOath.fromJson(json['oath'] as Map<String, dynamic>),
    summary: json['summary'] == null
        ? null
        : SeasonSummary.fromJson(json['summary'] as Map<String, dynamic>),
  );

  @override
  bool operator ==(Object other) =>
      other is Season &&
      other.id == id &&
      other.name == name &&
      toDateString(other.startDate) == toDateString(startDate) &&
      toDateString(other.endDate) == toDateString(endDate) &&
      other.isArchived == isArchived &&
      other.oath == oath &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    toDateString(startDate),
    toDateString(endDate),
    isArchived,
    oath,
    summary,
  );
}

/// Mid-month reflection notes and habit pivots for one calendar month.
class MonthReflection {
  MonthReflection({
    required this.monthKey,
    this.notes = '',
    List<String> pivots = const [],
  }) : pivots = List.unmodifiable(pivots);

  /// Calendar month as `YYYY-MM`.
  final String monthKey;
  final String notes;

  /// Human-readable pivot history, e.g. "Meditation → Journaling".
  final List<String> pivots;

  static String keyFor(DateTime date) => toDateString(date).substring(0, 7);

  MonthReflection copyWith({
    String? monthKey,
    String? notes,
    List<String>? pivots,
  }) {
    return MonthReflection(
      monthKey: monthKey ?? this.monthKey,
      notes: notes ?? this.notes,
      pivots: pivots ?? this.pivots,
    );
  }

  Map<String, dynamic> toJson() => {
    'monthKey': monthKey,
    'notes': notes,
    'pivots': pivots,
  };

  factory MonthReflection.fromJson(Map<String, dynamic> json) =>
      MonthReflection(
        monthKey: json['monthKey'] as String,
        notes: json['notes'] as String? ?? '',
        pivots: (json['pivots'] as List<dynamic>? ?? const []).cast<String>(),
      );

  @override
  bool operator ==(Object other) =>
      other is MonthReflection &&
      other.monthKey == monthKey &&
      other.notes == notes &&
      _listEquals(other.pivots, pivots);

  @override
  int get hashCode => Object.hash(monthKey, notes, Object.hashAll(pivots));
}

/// A hand-drawn signature committing to a season.
class SeasonOath {
  SeasonOath({required List<List<double>> strokes, required this.signedAtDate})
    : strokes = List.unmodifiable([
        for (final stroke in strokes) List<double>.unmodifiable(stroke),
      ]);

  /// Each stroke is a flat list of points `[x0, y0, x1, y1, ...]`, normalized
  /// to 0–1 of the signature pad so it redraws at any size.
  final List<List<double>> strokes;

  /// Date signed, as `YYYY-MM-DD`.
  final String signedAtDate;

  Map<String, dynamic> toJson() => {
    'strokes': strokes,
    'signedAtDate': signedAtDate,
  };

  factory SeasonOath.fromJson(Map<String, dynamic> json) => SeasonOath(
    strokes: [
      for (final stroke in json['strokes'] as List<dynamic>)
        [for (final v in stroke as List<dynamic>) (v as num).toDouble()],
    ],
    signedAtDate: json['signedAtDate'] as String,
  );

  @override
  bool operator ==(Object other) {
    if (other is! SeasonOath ||
        other.signedAtDate != signedAtDate ||
        other.strokes.length != strokes.length) {
      return false;
    }
    for (var i = 0; i < strokes.length; i++) {
      if (!_listEquals(other.strokes[i], strokes[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(signedAtDate, Object.hashAll(strokes.map(Object.hashAll)));
}

/// One branch's result for a completed season.
class BranchSeasonResult {
  const BranchSeasonResult({
    required this.startLevel,
    required this.nodes,
    required this.feats,
    required this.activeDays,
  });

  /// Carry-over base level the season started with.
  final int startLevel;
  final int nodes;
  final int feats;
  final int activeDays;

  /// Level baked in as the next season's base level.
  int get endLevel => startLevel + nodes + feats;

  Map<String, dynamic> toJson() => {
    'startLevel': startLevel,
    'nodes': nodes,
    'feats': feats,
    'activeDays': activeDays,
  };

  factory BranchSeasonResult.fromJson(Map<String, dynamic> json) =>
      BranchSeasonResult(
        startLevel: json['startLevel'] as int,
        nodes: json['nodes'] as int,
        feats: json['feats'] as int,
        activeDays: json['activeDays'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is BranchSeasonResult &&
      other.startLevel == startLevel &&
      other.nodes == nodes &&
      other.feats == feats &&
      other.activeDays == activeDays;

  @override
  int get hashCode => Object.hash(startLevel, nodes, feats, activeDays);
}

/// The final tally of a completed season, per branch.
class SeasonSummary {
  SeasonSummary({required Map<BranchType, BranchSeasonResult> branches})
    : branches = Map.unmodifiable(branches);

  final Map<BranchType, BranchSeasonResult> branches;

  /// Character level when the season began.
  int get startLevel => branches.values.fold(0, (sum, b) => sum + b.startLevel);

  /// Character level when the season ended (and the next one begins).
  int get endLevel => branches.values.fold(0, (sum, b) => sum + b.endLevel);

  Map<String, dynamic> toJson() => {
    for (final entry in branches.entries) entry.key.name: entry.value.toJson(),
  };

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
    branches: {
      for (final entry in json.entries)
        BranchType.values.byName(entry.key): BranchSeasonResult.fromJson(
          entry.value as Map<String, dynamic>,
        ),
    },
  );

  @override
  bool operator ==(Object other) {
    if (other is! SeasonSummary || other.branches.length != branches.length) {
      return false;
    }
    return branches.entries.every((e) => other.branches[e.key] == e.value);
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    branches.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
