import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// 1–5 star difficulty. Pass [onChanged] to make it tappable.
class DifficultyStars extends StatelessWidget {
  const DifficultyStars({
    super.key,
    required this.value,
    this.size = 16,
    this.onChanged,
  });

  final int value;
  final double size;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Difficulty $value of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            GestureDetector(
              onTap: onChanged == null ? null : () => onChanged!(i),
              child: Padding(
                padding: EdgeInsets.only(right: onChanged == null ? 0 : 4),
                child: Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: i <= value ? RpgColors.gold : RpgColors.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small pill with the branch's color dot and name.
class BranchBadge extends ConsumerWidget {
  const BranchBadge({super.key, required this.branch});

  final BranchType branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = branch.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            ref.watch(rpgStateProvider).nameOf(branch),
            style: RpgStyles.of(
              context,
            ).stat.copyWith(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}
