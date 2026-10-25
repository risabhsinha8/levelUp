import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import 'quest_widgets.dart';
import 'empty_prompt.dart';

/// Quest Log: the month's Main Quest hero card and its Side Quests.
class QuestLogView extends ConsumerWidget {
  const QuestLogView({
    super.key,
    required this.monthIndex,
    required this.currentMonthIndex,
    required this.onMonthChanged,
    required this.onAddMainQuest,
    required this.onAddSideQuest,
  });

  final int monthIndex;
  final int currentMonthIndex;
  final ValueChanged<int> onMonthChanged;
  final VoidCallback onAddMainQuest;
  final VoidCallback onAddSideQuest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStateProvider);
    final quests = state.currentQuests.where((q) => q.monthIndex == monthIndex);
    final main = quests.where((q) => q.isMainQuest).firstOrNull;
    final sides = [
      for (final branch in BranchType.values)
        for (final q in quests)
          if (!q.isMainQuest && q.branch == branch) q,
    ];
    final styles = RpgStyles.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (var m = 1; m <= 3; m++)
              ChoiceChip(
                label: Text(
                  m == currentMonthIndex ? 'Month $m · now' : 'Month $m',
                ),
                labelStyle: styles.stat.copyWith(
                  color: m == monthIndex ? RpgColors.gold : RpgColors.ink,
                ),
                selected: m == monthIndex,
                showCheckmark: false,
                selectedColor: RpgColors.gold.withValues(alpha: 0.16),
                side: BorderSide(
                  color: m == monthIndex
                      ? RpgColors.goldDim
                      : RpgColors.outline,
                ),
                onSelected: (_) => onMonthChanged(m),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (main == null)
          _EmptyMainQuest(monthIndex: monthIndex, onAdd: onAddMainQuest)
        else
          MainQuestHeroCard(key: ValueKey(main.id), quest: main),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Side Quests',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${sides.where((q) => q.isCompleted).length}/${sides.length} feats',
              style: styles.stat.copyWith(color: RpgColors.gold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Stretch goals. Each one checked off is +1 Feat for its branch.',
          style: styles.stat.copyWith(fontSize: 10),
        ),
        const SizedBox(height: 10),
        if (sides.isEmpty)
          EmptyPrompt(
            icon: LucideIcons.scroll,
            title: 'No side quests yet',
            message:
                'The Month $monthIndex quest board is bare. Post a stretch '
                'goal and earn +1 Feat when you finish it.',
            actionLabel: 'Post a Side Quest',
            onAction: onAddSideQuest,
            compact: true,
          )
        else
          for (final quest in sides) _SideQuestTile(quest: quest),
      ],
    );
  }
}

class _EmptyMainQuest extends StatelessWidget {
  const _EmptyMainQuest({required this.monthIndex, required this.onAdd});

  final int monthIndex;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: RpgColors.goldDim),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(LucideIcons.crown, color: RpgColors.goldDim, size: 32),
            const SizedBox(height: 10),
            Text(
              'No Main Quest for Month $monthIndex',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              "Pick the month's #1 highlight goal.",
              style: RpgStyles.of(context).stat,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Set Main Quest'),
              style: OutlinedButton.styleFrom(
                foregroundColor: RpgColors.gold,
                side: const BorderSide(color: RpgColors.goldDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The month's #1 goal, with a celebratory burst when completed.
class MainQuestHeroCard extends ConsumerStatefulWidget {
  const MainQuestHeroCard({super.key, required this.quest});

  final Quest quest;

  @override
  ConsumerState<MainQuestHeroCard> createState() => _MainQuestHeroCardState();
}

class _MainQuestHeroCardState extends ConsumerState<MainQuestHeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final quest = widget.quest;
    final messenger = ScaffoldMessenger.of(context);
    final before = ref
        .read(characterSheetProvider)
        .value
        ?.branches[quest.branch]
        ?.level;
    HapticFeedback.heavyImpact();
    _burst.forward(from: 0);
    final store = ref.read(rpgStoreProvider.notifier);
    await store.completeQuest(quest.id);
    final after = ref
        .read(characterSheetProvider)
        .value
        ?.branches[quest.branch]
        ?.level;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Main Quest complete! +1 Feat · ${quest.branch.displayName} '
          'Lv $before → $after',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.setQuestCompleted(quest.id, completed: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quest = widget.quest;
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final done = quest.isCompleted;
    final color = quest.branch.color;

    return AnimatedBuilder(
      animation: _burst,
      builder: (context, child) {
        final pulse = math.sin(_burst.value * math.pi);
        return Transform.scale(
          scale: 1 + 0.03 * pulse,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child!,
              if (_burst.isAnimating)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SparkBurstPainter(
                        progress: _burst.value,
                        color: color,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: done ? RpgColors.gold : RpgColors.goldDim,
            width: done ? 2 : 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: done ? 0.28 : 0.18),
              RpgColors.slate,
              RpgColors.slate,
            ],
          ),
          boxShadow: done
              ? [
                  BoxShadow(
                    color: RpgColors.gold.withValues(alpha: 0.25),
                    blurRadius: 18,
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.crown, size: 16, color: RpgColors.gold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'MONTH ${quest.monthIndex} MAIN QUEST',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.stat.copyWith(
                      color: RpgColors.gold,
                      letterSpacing: 1.4,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                BranchBadge(branch: quest.branch),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              quest.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: RpgColors.gold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                DifficultyStars(value: quest.difficulty, size: 18),
                const SizedBox(width: 8),
                Text('Difficulty', style: styles.stat),
              ],
            ),
            if (quest.rewardText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(LucideIcons.gift, size: 14, color: RpgColors.ink),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      quest.rewardText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: done
                  ? OutlinedButton.icon(
                      onPressed: () => ref
                          .read(rpgStoreProvider.notifier)
                          .setQuestCompleted(quest.id, completed: false),
                      icon: const Icon(LucideIcons.checkCircle2, size: 18),
                      label: const Text('Quest Complete · Tap to undo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: RpgColors.gold,
                        side: const BorderSide(color: RpgColors.gold),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _complete,
                      icon: const Icon(LucideIcons.swords, size: 18),
                      label: const Text('Complete Main Quest (+1 Skill Point)'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gold and branch-colored sparks flying out from the card center.
class _SparkBurstPainter extends CustomPainter {
  _SparkBurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const int _sparks = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(progress);
    final fade = 1 - progress;
    final reach = size.shortestSide * 0.9;
    for (var i = 0; i < _sparks; i++) {
      final angle = 2 * math.pi * i / _sparks + (i.isEven ? 0.1 : -0.1);
      final distance = reach * eased * (i % 3 == 0 ? 1.0 : 0.75);
      final position = center + Offset.fromDirection(angle, distance);
      final paint = Paint()
        ..color = (i.isEven ? RpgColors.gold : color).withValues(alpha: fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(position, 3.5 * fade + 1, paint);
    }
  }

  @override
  bool shouldRepaint(_SparkBurstPainter old) => old.progress != progress;
}

class _SideQuestTile extends ConsumerWidget {
  const _SideQuestTile({required this.quest});

  final Quest quest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final styles = RpgStyles.of(context);
    final done = quest.isCompleted;
    final color = quest.branch.color;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        checked: done,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.mediumImpact();
            ref
                .read(rpgStoreProvider.notifier)
                .setQuestCompleted(quest.id, completed: !done);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: done ? color : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: done ? color : RpgColors.ink,
                      width: 1.5,
                    ),
                  ),
                  child: done
                      ? const Icon(
                          LucideIcons.check,
                          size: 16,
                          color: RpgColors.obsidian,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quest.title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: RpgColors.ink,
                          color: done ? RpgColors.ink : RpgColors.parchment,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          BranchBadge(branch: quest.branch),
                          DifficultyStars(value: quest.difficulty, size: 13),
                          if (quest.rewardText.isNotEmpty)
                            Text(quest.rewardText, style: styles.stat),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: done ? 1 : 0.35,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    '+1',
                    style: styles.statLarge.copyWith(
                      fontSize: 14,
                      color: done ? color : RpgColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
