import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// Shows the full-screen translucent celebration and waits until it is
/// dismissed (tap anywhere or "Onward").
Future<void> showCelebration(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  required String headline,
  List<String> rewards = const [],
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss celebration',
    barrierColor: RpgColors.obsidian.withValues(alpha: 0.82),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (context, _, _) => CelebrationOverlay(
      icon: icon,
      color: color,
      title: title,
      headline: headline,
      rewards: rewards,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.8, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// "NODE FORGED / LEVEL UP!" for a freshly forged skill node.
Future<void> showNodeForgedCelebration(
  BuildContext context,
  NodeForgeResult result,
) {
  return showCelebration(
    context,
    icon: result.branch.icon,
    color: result.branch.color,
    title: 'NODE FORGED / LEVEL UP!',
    headline: 'Lv ${result.oldTotalLevel} → Lv ${result.newTotalLevel}',
    rewards: [
      '${result.branch.displayName} Lv ${result.oldBranchLevel} → '
          'Lv ${result.newBranchLevel}',
      for (final tier in LootTier.values)
        if ((result.keysEarned[tier] ?? 0) > 0)
          '+${result.keysEarned[tier]} ${tier.label} Loot Key Earned!',
    ],
  );
}

/// "LOOT UNLOCKED!" for a reward claimed with a key.
Future<void> showLootCelebration(BuildContext context, LootItem reward) {
  return showCelebration(
    context,
    icon: LucideIcons.gift,
    color: reward.tier.color,
    title: 'LOOT UNLOCKED!',
    headline: reward.title,
    rewards: ['1 ${reward.tier.label} Key spent · enjoy it, you earned it'],
  );
}

class CelebrationOverlay extends StatelessWidget {
  const CelebrationOverlay({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.headline,
    this.rewards = const [],
  });

  final IconData icon;
  final Color color;
  final String title;
  final String headline;
  final List<String> rewards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, glow, child) => Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.18),
                        border: Border.all(color: color, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.6 * glow),
                            blurRadius: 48 * glow,
                            spreadRadius: 10 * glow,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                    child: Icon(icon, size: 56, color: color),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: RpgColors.gold,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: styles.statLarge.copyWith(
                      fontSize: 30,
                      color: RpgColors.parchment,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final line in rewards)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color.withValues(alpha: 0.6)),
                      ),
                      child: Text(
                        line,
                        textAlign: TextAlign.center,
                        style: styles.stat.copyWith(
                          color: RpgColors.parchment,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Onward'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
