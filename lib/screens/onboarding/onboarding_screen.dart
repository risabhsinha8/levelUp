import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/new_character.dart';
import '../../models/rpg_models.dart';
import '../../providers/rpg_store_provider.dart';
import '../../theme/rpg_theme.dart';
import '../../widgets/settings_section.dart';
import 'onboarding_steps.dart';

/// "Session Zero": a 5-step wizard shown while no character exists (step 1
/// also picks and names the pillars). On
/// "Begin Season 1" everything is written to SQLite in one transaction and
/// the root gate switches to `HomeShell`.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepTitles = [
    'Roll Your Character',
    'Keystone Habits',
    'Buffs & Main Quest',
    'Loot Vault',
    'Seasonal Oath',
  ];

  final _pages = PageController();
  int _step = 0;
  bool _saving = false;

  // Step 1
  late AvatarSpec _avatar = AvatarSpec.random(ref.read(randomProvider));
  final _name = TextEditingController();
  final _class = TextEditingController();
  final _pillars = {...BranchType.defaults};
  final _pillarNames = {
    for (final b in BranchType.values) b: TextEditingController(),
  };
  // Step 2
  final _keystoneTitles = {
    for (final b in BranchType.values) b: TextEditingController(),
  };
  final _keystoneTargets = {
    for (final b in BranchType.values) b: TextEditingController(),
  };
  // Step 3
  BranchType _modifierBranch = BranchType.body;
  final _buff = TextEditingController();
  final _debuff = TextEditingController();
  final _questTitle = TextEditingController();
  final _questReward = TextEditingController();
  BranchType _questBranch = BranchType.mind;
  int _questDifficulty = 3;
  // Step 4
  final _loot = {for (final t in LootTier.values) t: <String>[]};
  final _lootDrafts = {
    for (final t in LootTier.values) t: TextEditingController(),
  };
  // Step 5: signature strokes, normalized to 0–1 of the pad.
  final List<List<Offset>> _strokes = [];

  @override
  void dispose() {
    _pages.dispose();
    for (final c in [
      _name,
      _class,
      _buff,
      _debuff,
      _questTitle,
      _questReward,
      ..._pillarNames.values,
      ..._keystoneTitles.values,
      ..._keystoneTargets.values,
      ..._lootDrafts.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The chosen pillars, in branch order.
  List<BranchType> get _branches => [
    for (final b in BranchType.values)
      if (_pillars.contains(b)) b,
  ];

  /// Display names of the chosen pillars, in branch order.
  Map<BranchType, String> get _names => {
    for (final b in _branches)
      b: BranchConfig(
        branch: b,
        customName: BranchConfig.customNameFor(b, _pillarNames[b]!.text),
      ).name,
  };

  void _togglePillar(BranchType branch) {
    setState(() {
      if (!_pillars.remove(branch)) _pillars.add(branch);
      final first = _branches.first;
      if (!_pillars.contains(_modifierBranch)) _modifierBranch = first;
      if (!_pillars.contains(_questBranch)) _questBranch = first;
    });
  }

  List<KeystoneChoice> get _keystones => [
    for (final branch in _branches)
      if (_keystoneTitles[branch]!.text.trim().isNotEmpty)
        KeystoneChoice(
          branch: branch,
          title: _keystoneTitles[branch]!.text.trim(),
          targetCriteria: _keystoneTargets[branch]!.text.trim(),
        ),
  ];

  MainQuestChoice? get _mainQuest => _questTitle.text.trim().isEmpty
      ? null
      : MainQuestChoice(
          title: _questTitle.text.trim(),
          branch: _questBranch,
          difficulty: _questDifficulty,
          rewardText: _questReward.text.trim(),
        );

  /// Picked rewards per tier, plus any typed but not yet added.
  Map<LootTier, List<String>> get _lootByTier => {
    for (final tier in LootTier.values)
      tier: {
        ..._loot[tier]!,
        _lootDrafts[tier]!.text.trim(),
      }.where((t) => t.isNotEmpty).toList(),
  };

  List<LootChoice> get _lootChoices => [
    for (final MapEntry(key: tier, value: titles) in _lootByTier.entries)
      for (final title in titles) LootChoice(tier: tier, title: title),
  ];

  void _toggleLoot(LootTier tier, String title) => setState(() {
    final picked = _loot[tier]!;
    if (!picked.remove(title)) picked.add(title);
  });

  void _addLoot(LootTier tier) => setState(() {
    final title = _lootDrafts[tier]!.text.trim();
    if (title.isNotEmpty && !_loot[tier]!.contains(title)) {
      _loot[tier]!.add(title);
    }
    _lootDrafts[tier]!.clear();
  });

  bool get _stepComplete => switch (_step) {
    0 => _name.text.trim().isNotEmpty && _class.text.trim().isNotEmpty,
    1 => _keystones.isNotEmpty,
    2 => true,
    3 => _lootByTier.values.every((titles) => titles.isNotEmpty),
    _ => _strokes.isNotEmpty,
  };

  String? get _blockedHint => switch (_step) {
    0 => 'Name your character and pick a class.',
    1 => 'Set at least one keystone.',
    3 => 'Add a reward for every tier.',
    4 => 'Sign the oath to begin.',
    _ => null,
  };

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pages.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _begin() async {
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.heavyImpact();
    setState(() => _saving = true);
    try {
      await ref
          .read(rpgStoreProvider.notifier)
          .completeOnboarding(
            name: _name.text.trim(),
            classTitle: _class.text.trim(),
            avatar: _avatar,
            activeBranches: _branches,
            branchNames: {
              for (final b in BranchType.values) b: _pillarNames[b]!.text,
            },
            keystones: _keystones,
            modifiers: [
              ModifierChoice(
                branch: _modifierBranch,
                text: _buff.text,
                isBuff: true,
              ),
              ModifierChoice(
                branch: _modifierBranch,
                text: _debuff.text,
                isBuff: false,
              ),
            ],
            mainQuest: _mainQuest,
            loot: _lootChoices,
            oathStrokes: [
              for (final stroke in _strokes)
                [
                  for (final p in stroke) ...[p.dx, p.dy],
                ],
            ],
          );
      // The root gate now shows HomeShell.
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create your character: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _stepTitles.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(
              step: _step,
              count: _stepTitles.length,
              title: _stepTitles[_step],
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  RollCharacterStep(
                    avatar: _avatar,
                    onAvatarChanged: (a) => setState(() => _avatar = a),
                    name: _name,
                    classTitle: _class,
                    pillars: _pillars,
                    pillarNames: _pillarNames,
                    onTogglePillar: _togglePillar,
                    onChanged: () => setState(() {}),
                    onRestore: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ImportBackupDialog(),
                    ),
                  ),
                  KeystonesStep(
                    branches: _branches,
                    names: _names,
                    titles: _keystoneTitles,
                    targets: _keystoneTargets,
                    onChanged: () => setState(() {}),
                  ),
                  BuffsAndQuestStep(
                    branches: _branches,
                    names: _names,
                    modifierBranch: _modifierBranch,
                    buff: _buff,
                    debuff: _debuff,
                    questTitle: _questTitle,
                    questReward: _questReward,
                    questBranch: _questBranch,
                    questDifficulty: _questDifficulty,
                    onModifierBranchChanged: (b) =>
                        setState(() => _modifierBranch = b),
                    onQuestBranchChanged: (b) =>
                        setState(() => _questBranch = b),
                    onDifficultyChanged: (d) =>
                        setState(() => _questDifficulty = d),
                    onChanged: () => setState(() {}),
                  ),
                  LootVaultStep(
                    rewards: _loot,
                    drafts: _lootDrafts,
                    onToggle: _toggleLoot,
                    onAdd: _addLoot,
                    onChanged: () => setState(() {}),
                  ),
                  SignOathStep(
                    name: _name.text.trim(),
                    classTitle: _class.text.trim(),
                    avatar: _avatar,
                    names: _names,
                    keystones: _keystones,
                    mainQuest: _mainQuest,
                    lootCount: _lootChoices.length,
                    today: ref.read(clockProvider)(),
                    strokes: _strokes,
                    onStrokeStart: (p) => setState(() => _strokes.add([p])),
                    onStrokeUpdate: (p) => setState(() => _strokes.last.add(p)),
                    onClear: () => setState(_strokes.clear),
                  ),
                ],
              ),
            ),
            _NavBar(
              showBack: _step > 0,
              isLast: isLast,
              enabled: _stepComplete && !_saving,
              saving: _saving,
              hint: _stepComplete ? null : _blockedHint,
              onBack: _saving ? null : () => _go(_step - 1),
              onNext: () => isLast ? _begin() : _go(_step + 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// "STEP 2 OF 5 · Keystone Habits" over a glowing gold progress bar.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.step,
    required this.count,
    required this.title,
  });

  final int step;
  final int count;
  final String title;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.dice5, size: 14, color: RpgColors.gold),
              const SizedBox(width: 6),
              Text(
                'SESSION ZERO',
                style: styles.stat.copyWith(
                  color: RpgColors.gold,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'Step ${step + 1} of $count · $title',
                  overflow: TextOverflow.ellipsis,
                  style: styles.stat.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Step ${step + 1} of $count',
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (step + 1) / count),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Container(
                height: 4,
                decoration: BoxDecoration(
                  color: RpgColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    decoration: BoxDecoration(
                      color: RpgColors.gold,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: RpgColors.gold.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.showBack,
    required this.isLast,
    required this.enabled,
    required this.saving,
    required this.hint,
    required this.onBack,
    required this.onNext,
  });

  final bool showBack;
  final bool isLast;
  final bool enabled;
  final bool saving;
  final String? hint;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: RpgColors.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(hint!, style: styles.stat.copyWith(fontSize: 10)),
            ),
          Row(
            children: [
              if (showBack)
                TextButton(onPressed: onBack, child: const Text('Back')),
              const Spacer(),
              Flexible(
                child: isLast
                    ? _GlowingBeginButton(
                        enabled: enabled,
                        saving: saving,
                        onPressed: onNext,
                      )
                    : FilledButton(
                        onPressed: enabled ? onNext : null,
                        child: const Text('Next'),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowingBeginButton extends StatelessWidget {
  const _GlowingBeginButton({
    required this.enabled,
    required this.saving,
    required this.onPressed,
  });

  final bool enabled;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: RpgColors.gold.withValues(alpha: 0.6),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(LucideIcons.swords, size: 18),
        label: const Text('Begin Season 1', overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
