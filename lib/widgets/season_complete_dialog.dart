import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/season_rollover.dart';
import '../models/rpg_models.dart';
import '../theme/rpg_theme.dart';

/// Celebratory "Season Complete" dialog shown after a rollover.
class SeasonCompleteDialog extends StatelessWidget {
  const SeasonCompleteDialog({super.key, required this.result});

  final SeasonRolloverResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final summary = result.summary;
    final gained = summary.endLevel - summary.startLevel;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: RpgColors.gold, width: 1.5),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: RpgColors.gold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: RpgColors.gold.withValues(alpha: 0.45),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.trophy,
                  size: 36,
                  color: RpgColors.gold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${result.completedSeason.name} Complete!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: RpgColors.gold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LevelPill(label: 'Before', level: summary.startLevel),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(LucideIcons.arrowRight, color: RpgColors.gold),
                ),
                _LevelPill(
                  label: 'Now',
                  level: summary.endLevel,
                  highlight: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '+$gained level${gained == 1 ? '' : 's'} this season',
              style: styles.stat.copyWith(color: RpgColors.parchment),
            ),
            const SizedBox(height: 16),
            for (final branch in BranchType.values)
              if (summary.branches.containsKey(branch))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
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
                      Expanded(child: Text(result.state.nameOf(branch))),
                      Text(
                        'Lv ${summary.branches[branch]!.startLevel} → '
                        '${summary.branches[branch]!.endLevel}',
                        style: styles.stat.copyWith(color: branch.color),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 16),
            Text(
              '${result.newSeason.name} is underway. Your levels are now '
              'permanent and the skill tree resets for a new climb.',
              textAlign: TextAlign.center,
              style: styles.stat,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Begin ${result.newSeason.name}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({
    required this.label,
    required this.level,
    this.highlight = false,
  });

  final String label;
  final int level;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Column(
      children: [
        Text(label, style: styles.stat.copyWith(fontSize: 10)),
        const SizedBox(height: 4),
        Text(
          'Lv $level',
          style: styles.statLarge.copyWith(
            fontSize: highlight ? 30 : 22,
            color: highlight ? RpgColors.gold : RpgColors.ink,
          ),
        ),
      ],
    );
  }
}
