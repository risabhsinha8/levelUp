import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/rpg_theme.dart';

/// Gold medallion showing the character level. Counts up on first show and
/// pulses with a glow whenever the level rises.
class LevelBadge extends StatefulWidget {
  const LevelBadge({super.key, required this.level, this.size = 56});

  final int level;
  final double size;

  @override
  State<LevelBadge> createState() => _LevelBadgeState();
}

class _LevelBadgeState extends State<LevelBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(LevelBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.level > oldWidget.level) _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Semantics(
      label: 'Level ${widget.level}',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final wave = math.sin(_pulse.value * math.pi);
          return Transform.scale(
            scale: 1 + 0.14 * wave,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [RpgColors.slateRaised, RpgColors.obsidian],
                ),
                border: Border.all(color: RpgColors.gold, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: RpgColors.gold.withValues(alpha: 0.18 + 0.4 * wave),
                    blurRadius: 10 + 16 * wave,
                    spreadRadius: 1 + 3 * wave,
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'LVL',
                style: styles.stat.copyWith(
                  fontSize: 9,
                  color: RpgColors.gold,
                  letterSpacing: 1.5,
                ),
              ),
              TweenAnimationBuilder<double>(
                // Counts up from 0 on first show; later changes animate
                // from the current value.
                tween: Tween(begin: 0, end: widget.level.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  value.round().toString(),
                  style: styles.statLarge.copyWith(height: 1.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
