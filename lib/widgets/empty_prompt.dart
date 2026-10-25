import 'package:flutter/material.dart';

import '../theme/rpg_theme.dart';

/// Tabletop-styled placeholder for an empty list: an icon, a short title,
/// a hint, and an optional action. [compact] fits inside cards and sheets.
class EmptyPrompt extends StatelessWidget {
  const EmptyPrompt({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.color = RpgColors.goldDim,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 14 : 28,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        color: color.withValues(alpha: 0.04),
      ),
      child: Column(
        children: [
          Icon(icon, size: compact ? 22 : 34, color: color),
          SizedBox(height: compact ? 6 : 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style:
                (compact
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(color: RpgColors.parchment),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: styles.stat.copyWith(fontSize: compact ? 10 : 12),
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: compact ? 10 : 16),
            compact
                ? TextButton(onPressed: onAction, child: Text(actionLabel!))
                : FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
