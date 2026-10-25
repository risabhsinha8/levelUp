import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/character_sheet.dart';
import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// Expandable card for one attribute: the level formula, plus editable buff
/// (enabler) and debuff (friction) chips.
class AttributeCard extends ConsumerWidget {
  const AttributeCard({super.key, required this.stats, required this.config});

  final BranchStats stats;
  final BranchConfig config;

  Future<void> _add(BuildContext context, WidgetRef ref, bool isBuff) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _ModifierDialog(
        title: isBuff ? 'Add a Buff' : 'Add a Debuff',
        hint: isBuff
            ? 'e.g. Gym clothes laid out'
            : 'e.g. Late night scrolling',
      ),
    );
    if (text == null || text.isEmpty) return;
    await ref
        .read(rpgStoreProvider.notifier)
        .updateBranchModifiers(
          config.branch,
          buffs: isBuff ? [...config.buffs, text] : null,
          debuffs: isBuff ? null : [...config.debuffs, text],
        );
  }

  Future<void> _remove(WidgetRef ref, bool isBuff, int index) {
    final list = [...(isBuff ? config.buffs : config.debuffs)]..removeAt(index);
    return ref
        .read(rpgStoreProvider.notifier)
        .updateBranchModifiers(
          config.branch,
          buffs: isBuff ? list : null,
          debuffs: isBuff ? null : list,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final color = stats.branch.color;
    final next = stats.nextNodeThreshold;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('attribute-${stats.branch.name}'),
            tilePadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            iconColor: color,
            collapsedIconColor: RpgColors.ink,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    stats.branch.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(color: color),
                  ),
                ),
                Text(
                  'Lv ${stats.level}',
                  style: styles.statLarge.copyWith(fontSize: 18),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _LevelFormula(stats: stats, baseLevel: config.baseLevel),
            ),
            children: [
              Text(
                next == null
                    ? '${stats.activeDays} active days · branch mastered'
                    : '${stats.activeDays} active days · next node at $next',
                style: styles.stat,
              ),
              const SizedBox(height: 14),
              _ModifierSection(
                label: 'Buffs',
                caption: 'Enablers that make showing up easy',
                items: config.buffs,
                color: RpgColors.gold,
                icon: LucideIcons.arrowUpCircle,
                addLabel: '+ Buff',
                onAdd: () => _add(context, ref, true),
                onRemove: (i) => _remove(ref, true, i),
              ),
              const SizedBox(height: 12),
              _ModifierSection(
                label: 'Debuffs',
                caption: 'Friction to design around',
                items: config.debuffs,
                color: RpgColors.danger,
                icon: LucideIcons.arrowDownCircle,
                addLabel: '− Debuff',
                onAdd: () => _add(context, ref, false),
                onRemove: (i) => _remove(ref, false, i),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Base 1 + Nodes 2 + Feats 0 = 3`
class _LevelFormula extends StatelessWidget {
  const _LevelFormula({required this.stats, required this.baseLevel});

  final BranchStats stats;
  final int baseLevel;

  @override
  Widget build(BuildContext context) {
    final style = RpgStyles.of(context).stat.copyWith(fontSize: 11);
    final strong = style.copyWith(
      color: RpgColors.parchment,
      fontWeight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Base '),
          TextSpan(text: '$baseLevel', style: strong),
          const TextSpan(text: ' + Nodes '),
          TextSpan(text: '${stats.forgedNodes}', style: strong),
          const TextSpan(text: ' + Feats '),
          TextSpan(text: '${stats.completedFeats}', style: strong),
          const TextSpan(text: ' = '),
          TextSpan(
            text: '${stats.level}',
            style: strong.copyWith(color: stats.branch.color),
          ),
        ],
      ),
    );
  }
}

class _ModifierSection extends StatelessWidget {
  const _ModifierSection({
    required this.label,
    required this.caption,
    required this.items,
    required this.color,
    required this.icon,
    required this.addLabel,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final String caption;
  final List<String> items;
  final Color color;
  final IconData icon;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(caption, style: styles.stat.copyWith(fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < items.length; i++)
              InputChip(
                avatar: Icon(icon, size: 14, color: color),
                label: Text(items[i]),
                labelStyle: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: RpgColors.parchment),
                backgroundColor: color.withValues(alpha: 0.1),
                side: BorderSide(color: color.withValues(alpha: 0.5)),
                deleteIconColor: RpgColors.ink,
                deleteButtonTooltipMessage: 'Remove',
                onDeleted: () => onRemove(i),
              ),
            ActionChip(
              label: Text(addLabel),
              labelStyle: styles.stat.copyWith(color: color),
              backgroundColor: Colors.transparent,
              side: BorderSide(color: color.withValues(alpha: 0.5)),
              onPressed: onAdd,
            ),
          ],
        ),
      ],
    );
  }
}

class _ModifierDialog extends StatefulWidget {
  const _ModifierDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_ModifierDialog> createState() => _ModifierDialogState();
}

class _ModifierDialogState extends State<_ModifierDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
