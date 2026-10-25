import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/new_character.dart';
import '../../domain/rpg_engine.dart';
import '../../models/rpg_models.dart';
import '../../theme/rpg_theme.dart';
import '../../widgets/oath_signature_card.dart';
import '../../widgets/quest_widgets.dart';
import 'onboarding_data.dart';

/// Scrollable page body shared by every step.
class StepPage extends StatelessWidget {
  const StepPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.scrollable = true,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(subtitle, style: RpgStyles.of(context).stat),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

/// Wrap of tappable suggestion chips.
class SuggestionChips extends StatelessWidget {
  const SuggestionChips({
    super.key,
    required this.labels,
    required this.onSelected,
    this.color = RpgColors.goldDim,
  });

  final List<String> labels;
  final ValueChanged<int> onSelected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < labels.length; i++)
          ActionChip(
            avatar: Icon(LucideIcons.sparkles, size: 12, color: color),
            label: Text(labels[i]),
            labelStyle: styles.stat.copyWith(
              color: RpgColors.parchment,
              fontSize: 11,
            ),
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            backgroundColor: Colors.transparent,
            visualDensity: VisualDensity.compact,
            onPressed: () => onSelected(i),
          ),
      ],
    );
  }
}

class BranchChoiceChips extends StatelessWidget {
  const BranchChoiceChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final BranchType selected;
  final ValueChanged<BranchType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final branch in BranchType.values)
          ChoiceChip(
            label: Text(branch.displayName),
            selected: selected == branch,
            showCheckmark: false,
            selectedColor: branch.color.withValues(alpha: 0.25),
            side: BorderSide(
              color: selected == branch ? branch.color : RpgColors.outline,
            ),
            labelStyle: TextStyle(
              color: selected == branch ? branch.color : RpgColors.ink,
            ),
            onSelected: (_) => onSelected(branch),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.color = RpgColors.outline});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: RpgColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RpgColors.outline),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Roll Your Character
// ---------------------------------------------------------------------------

class RollCharacterStep extends StatelessWidget {
  const RollCharacterStep({
    super.key,
    required this.name,
    required this.classTitle,
    required this.onChanged,
    required this.onRestore,
  });

  final TextEditingController name;
  final TextEditingController classTitle;
  final VoidCallback onChanged;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    return StepPage(
      title: 'Roll Your Character',
      subtitle:
          'Every campaign starts with a Session Zero. Who is starting this '
          'one?',
      children: [
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Character Name',
            hintText: 'e.g. Rowan',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: classTitle,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Class Title',
            hintText: 'An honest, funny title for where you are now',
          ),
        ),
        const SizedBox(height: 10),
        SuggestionChips(
          labels: classSuggestions,
          onSelected: (i) {
            classTitle.text = classSuggestions[i];
            onChanged();
          },
        ),
        const SizedBox(height: 24),
        _SectionCard(
          color: RpgColors.gold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The Five Branches',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: RpgColors.gold,
                ),
              ),
              const SizedBox(height: 10),
              for (final branch in BranchType.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: branch.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 64,
                        child: Text(
                          branch.displayName,
                          style: styles.stat.copyWith(
                            color: branch.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          branchDescriptions[branch]!,
                          style: styles.stat,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    LucideIcons.shieldCheck,
                    size: 16,
                    color: RpgColors.gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cumulative active days over a quarterly Season '
                      '(Jan, Apr, Jul, Oct)—no streak-break punishment.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: onRestore,
            icon: const Icon(LucideIcons.upload, size: 16),
            label: const Text('Restore a backup instead'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Forge Your 5 Keystone Habits
// ---------------------------------------------------------------------------

class KeystonesStep extends StatelessWidget {
  const KeystonesStep({
    super.key,
    required this.titles,
    required this.targets,
    required this.onChanged,
  });

  final Map<BranchType, TextEditingController> titles;
  final Map<BranchType, TextEditingController> targets;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StepPage(
      title: 'Forge Your 5 Keystone Habits',
      subtitle: 'The anti-burnout setup.',
      children: [
        _SectionCard(
          color: RpgColors.gold,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.star_rounded, color: RpgColors.gold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Start small: one non-negotiable ★ Keystone per branch. '
                  "Pick something you'd do even on your worst day. You can "
                  'add more habits once these stick.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        for (final branch in BranchType.values)
          _SectionCard(
            color: branch.color,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: RpgColors.gold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      branch.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: branch.color,
                      ),
                    ),
                  ],
                ),
                TextField(
                  key: ValueKey('keystone-title-${branch.name}'),
                  controller: titles[branch],
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(labelText: 'Keystone'),
                ),
                TextField(
                  key: ValueKey('keystone-target-${branch.name}'),
                  controller: targets[branch],
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Target criteria',
                    hintText: 'e.g. ${keystoneSuggestions[branch]!.first.$2}',
                  ),
                ),
                const SizedBox(height: 10),
                SuggestionChips(
                  color: branch.color,
                  labels: [
                    for (final (title, target) in keystoneSuggestions[branch]!)
                      '$title · $target',
                  ],
                  onSelected: (i) {
                    final (title, target) = keystoneSuggestions[branch]![i];
                    titles[branch]!.text = title;
                    targets[branch]!.text = target;
                    onChanged();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: Buffs, Debuffs & Month 1 Main Quest
// ---------------------------------------------------------------------------

class BuffsAndQuestStep extends StatelessWidget {
  const BuffsAndQuestStep({
    super.key,
    required this.modifierBranch,
    required this.buff,
    required this.debuff,
    required this.questTitle,
    required this.questReward,
    required this.questBranch,
    required this.questDifficulty,
    required this.onModifierBranchChanged,
    required this.onQuestBranchChanged,
    required this.onDifficultyChanged,
    required this.onChanged,
  });

  final BranchType modifierBranch;
  final TextEditingController buff;
  final TextEditingController debuff;
  final TextEditingController questTitle;
  final TextEditingController questReward;
  final BranchType questBranch;
  final int questDifficulty;
  final ValueChanged<BranchType> onModifierBranchChanged;
  final ValueChanged<BranchType> onQuestBranchChanged;
  final ValueChanged<int> onDifficultyChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    return StepPage(
      title: 'Buffs, Debuffs & Main Quest',
      subtitle:
          'Design your environment, then pick the one goal that would make '
          'this month a win. Everything here is optional.',
      children: [
        _SectionCard(
          color: modifierBranch.color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Buff & Debuff', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Which attribute needs it most?', style: styles.stat),
              const SizedBox(height: 8),
              BranchChoiceChips(
                selected: modifierBranch,
                onSelected: onModifierBranchChanged,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: buff,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: '+ Buff (enabler)',
                  prefixIcon: Icon(
                    LucideIcons.arrowUpCircle,
                    color: RpgColors.gold,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SuggestionChips(
                color: RpgColors.gold,
                labels: buffSuggestions,
                onSelected: (i) {
                  buff.text = buffSuggestions[i];
                  onChanged();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: debuff,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: '− Debuff (friction)',
                  prefixIcon: Icon(
                    LucideIcons.arrowDownCircle,
                    color: RpgColors.danger,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SuggestionChips(
                color: RpgColors.danger,
                labels: debuffSuggestions,
                onSelected: (i) {
                  debuff.text = debuffSuggestions[i];
                  onChanged();
                },
              ),
            ],
          ),
        ),
        _SectionCard(
          color: RpgColors.gold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.crown,
                    size: 16,
                    color: RpgColors.gold,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      "This Month's Main Quest",
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              TextField(
                controller: questTitle,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: 'Main quest',
                  hintText: 'e.g. Run a 5K without stopping',
                ),
              ),
              const SizedBox(height: 12),
              BranchChoiceChips(
                selected: questBranch,
                onSelected: onQuestBranchChanged,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Difficulty', style: styles.stat),
                  DifficultyStars(
                    value: questDifficulty,
                    size: 24,
                    onChanged: onDifficultyChanged,
                  ),
                ],
              ),
              TextField(
                controller: questReward,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reward',
                  hintText: 'e.g. New running shoes',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4: Stock Your Loot Vault
// ---------------------------------------------------------------------------

class LootVaultStep extends StatelessWidget {
  const LootVaultStep({super.key, required this.loot, required this.onChanged});

  final Map<LootTier, TextEditingController> loot;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    return StepPage(
      title: 'Stock Your Loot Vault',
      subtitle:
          'Keys are earned automatically. Choose one real-life reward per '
          'tier to spend them on.',
      children: [
        for (final tier in LootTier.values)
          _SectionCard(
            color: tier.color,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.key, size: 16, color: tier.color),
                    const SizedBox(width: 6),
                    Text(
                      tier.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tier.color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tier.keySource,
                        textAlign: TextAlign.end,
                        style: styles.stat.copyWith(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                TextField(
                  key: ValueKey('loot-${tier.name}'),
                  controller: loot[tier],
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: '${tier.label} reward',
                    prefixIcon: Icon(
                      LucideIcons.gift,
                      color: tier.color,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SuggestionChips(
                  color: tier.color,
                  labels: lootSuggestions[tier]!,
                  onSelected: (i) {
                    loot[tier]!.text = lootSuggestions[tier]![i];
                    onChanged();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 5: Sign the Seasonal Oath
// ---------------------------------------------------------------------------

class SignOathStep extends StatelessWidget {
  const SignOathStep({
    super.key,
    required this.name,
    required this.classTitle,
    required this.keystones,
    required this.mainQuest,
    required this.lootCount,
    required this.today,
    required this.strokes,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    required this.onClear,
  });

  final String name;
  final String classTitle;
  final List<KeystoneChoice> keystones;
  final MainQuestChoice? mainQuest;
  final int lootCount;
  final DateTime today;
  final List<List<Offset>> strokes;
  final ValueChanged<Offset> onStrokeStart;
  final ValueChanged<Offset> onStrokeUpdate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final dates = DateFormat.MMMd();
    final season = Season(
      id: 'preview',
      name: 'Season 1',
      startDate: Season.quarterStartOf(today),
      endDate: Season.quarterEndOf(today),
    );
    final start = season.startDate;
    final end = season.endDate;
    final seasonLength = RpgEngine.calculateSeasonLength(season);
    final joinDay = RpgEngine.calculateSeasonDay(season, today);
    final questMonth = RpgEngine.calculateSeasonMonthIndex(season, today);

    return StepPage(
      title: 'Sign the Seasonal Oath',
      subtitle: 'Review your character sheet, then sign to begin.',
      children: [
        _SectionCard(
          color: RpgColors.gold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: RpgColors.gold, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Lv 0',
                      style: styles.stat.copyWith(
                        color: RpgColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleLarge),
                        Text(
                          classTitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: RpgColors.gold,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Season 1 · Day $joinDay of $seasonLength · '
                '${dates.format(start)} – ${dates.format(end)}',
                style: styles.stat.copyWith(color: RpgColors.parchment),
              ),
              const Divider(height: 20),
              for (final k in keystones)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: RpgColors.gold,
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 60,
                        child: Text(
                          k.branch.displayName,
                          style: styles.stat.copyWith(color: k.branch.color),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          k.targetCriteria.isEmpty
                              ? k.title
                              : '${k.title} · ${k.targetCriteria}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: RpgColors.parchment,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (mainQuest != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      LucideIcons.crown,
                      size: 14,
                      color: RpgColors.gold,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Month $questMonth: ${mainQuest!.title}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: RpgColors.parchment,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text('$lootCount rewards in the loot vault', style: styles.stat),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'I, $name, swear to show up for my Mind, Body, Craft, Bond and '
          'Empire through Season 1. One point a day. No streak shame. '
          'Progress over perfection.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        SignaturePad(
          strokes: strokes,
          enabled: true,
          onStrokeStart: onStrokeStart,
          onStrokeUpdate: onStrokeUpdate,
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                strokes.isEmpty
                    ? 'Sign with your finger to lock in your commitment.'
                    : 'Signed. Ready when you are.',
                style: styles.stat.copyWith(
                  fontSize: 10,
                  color: strokes.isEmpty ? RpgColors.ink : RpgColors.gold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: strokes.isEmpty ? null : onClear,
              icon: const Icon(LucideIcons.eraser, size: 14),
              label: const Text('Clear / Re-sign'),
              style: TextButton.styleFrom(foregroundColor: RpgColors.ink),
            ),
          ],
        ),
      ],
    );
  }
}
