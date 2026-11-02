import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import 'rpg_engine.dart';

/// A keystone habit chosen during onboarding.
class KeystoneChoice {
  const KeystoneChoice({
    required this.branch,
    required this.title,
    this.targetCriteria = '',
  });

  final BranchType branch;
  final String title;
  final String targetCriteria;
}

/// The current month's main quest chosen during onboarding.
class MainQuestChoice {
  const MainQuestChoice({
    required this.title,
    required this.branch,
    this.difficulty = 3,
    this.rewardText = '',
  });

  final String title;
  final BranchType branch;
  final int difficulty;
  final String rewardText;
}

/// A starting real-life reward for the loot table.
class LootChoice {
  const LootChoice({required this.tier, required this.title});

  final LootTier tier;
  final String title;
}

/// A starting buff (enabler) or debuff (friction) for a branch.
class ModifierChoice {
  const ModifierChoice({
    required this.branch,
    required this.text,
    required this.isBuff,
  });

  final BranchType branch;
  final String text;
  final bool isBuff;
}

/// Builds the first state for a character created in Session Zero: the
/// picked [avatar], level 0 in every branch, the chosen pillars ([branchNames] holds custom names;
/// [activeBranches] defaults to the five core ones), the chosen keystones, buffs and debuffs, an optional
/// main quest for the current month, the starting loot table, the signed
/// oath (if [oathStrokes] is non-empty), and Season 1: the calendar quarter
/// containing [today], so joining on Nov 1 starts on day 32 of Oct 1–Dec 31.
RpgState buildNewCharacterState({
  required String name,
  required String classTitle,
  AvatarSpec? avatar,
  List<BranchType> activeBranches = BranchType.defaults,
  Map<BranchType, String> branchNames = const {},
  required List<KeystoneChoice> keystones,
  MainQuestChoice? mainQuest,
  List<LootChoice> loot = const [],
  List<ModifierChoice> modifiers = const [],
  List<List<double>> oathStrokes = const [],
  required DateTime today,
  required String seasonId,
  required String Function() newId,
}) {
  final season = Season(
    id: seasonId,
    name: 'Season 1',
    startDate: Season.quarterStartOf(today),
    endDate: Season.quarterEndOf(today),
    oath: oathStrokes.isEmpty
        ? null
        : SeasonOath(strokes: oathStrokes, signedAtDate: toDateString(today)),
  );
  List<String> modifiersFor(BranchType branch, {required bool buffs}) => [
    for (final m in modifiers)
      if (m.branch == branch && m.isBuff == buffs && m.text.trim().isNotEmpty)
        m.text.trim(),
  ];
  return RpgState(
    character: Character(
      name: name,
      classTitle: classTitle,
      currentSeasonId: season.id,
      avatar: avatar,
    ),
    branchConfigs: [
      for (final branch in BranchType.values)
        BranchConfig(
          branch: branch,
          buffs: modifiersFor(branch, buffs: true),
          debuffs: modifiersFor(branch, buffs: false),
          customName: BranchConfig.customNameFor(
            branch,
            branchNames[branch] ?? '',
          ),
          isEnabled: activeBranches.contains(branch),
        ),
    ],
    habits: [
      for (final branch in activeBranches)
        for (final choice in keystones)
          if (choice.branch == branch && choice.title.trim().isNotEmpty)
            Habit(
              id: newId(),
              branch: branch,
              title: choice.title.trim(),
              targetCriteria: choice.targetCriteria.trim(),
              isKeystone: true,
            ),
    ],
    quests: [
      if (mainQuest != null &&
          mainQuest.title.trim().isNotEmpty &&
          activeBranches.contains(mainQuest.branch))
        Quest(
          id: newId(),
          title: mainQuest.title.trim(),
          isMainQuest: true,
          branch: mainQuest.branch,
          difficulty: mainQuest.difficulty,
          monthIndex: RpgEngine.calculateSeasonMonthIndex(season, today),
          rewardText: mainQuest.rewardText.trim(),
          seasonId: season.id,
        ),
    ],
    loot: [
      for (final choice in loot)
        if (choice.title.trim().isNotEmpty)
          LootItem(id: newId(), tier: choice.tier, title: choice.title.trim()),
    ],
    seasons: [season],
  );
}
