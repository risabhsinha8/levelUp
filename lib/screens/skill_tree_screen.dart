import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/attribute_card.dart';
import '../widgets/celebration_overlay.dart';
import '../widgets/oath_signature_card.dart';
import '../widgets/skill_tree_canvas.dart';

/// Tab 2: the Character Sheet — skill tree, attribute cards and the
/// seasonal oath.
class SkillTreeScreen extends ConsumerWidget {
  const SkillTreeScreen({super.key});

  Future<void> _forge(
    BuildContext context,
    WidgetRef ref,
    BranchType branch,
  ) async {
    final result = await ref.read(rpgStoreProvider.notifier).forgeNode(branch);
    if (result == null || !context.mounted) return;
    await showNodeForgedCelebration(context, result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStateProvider);
    final sheet = ref.watch(characterSheetProvider).requireValue;
    final forged = sheet.branches.values.fold(
      0,
      (sum, b) => sum + b.forgedNodes,
    );
    final ready = sheet.branches.values.fold(
      0,
      (sum, b) => sum + b.readyToForge,
    );
    final totalNodes = RpgEngine.maxNodesPerBranch * BranchType.values.length;

    return ListView(
      key: const PageStorageKey('skill-tree'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _SectionHeader(
          title: 'Skill Tree',
          trailing: '$forged/$totalNodes nodes',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: SkillTreeCanvas(
              sheet: sheet,
              onForge: (branch) => _forge(context, ref, branch),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ready > 0
              ? '$ready node${ready == 1 ? '' : 's'} ready! Hold a glowing '
                    'node to forge it.'
              : 'Tap a node to see what it takes to unlock.',
          textAlign: TextAlign.center,
          style: RpgStyles.of(context).stat.copyWith(
            fontSize: 10,
            color: ready > 0 ? RpgColors.gold : null,
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader(title: 'Attributes', trailing: 'Lv ${sheet.totalLevel}'),
        for (final branch in BranchType.values)
          AttributeCard(
            stats: sheet.branches[branch]!,
            config: state.configFor(branch),
          ),
        const SizedBox(height: 20),
        const _SectionHeader(title: 'Seasonal Oath'),
        const OathSignatureCard(),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: RpgStyles.of(context).stat.copyWith(color: RpgColors.gold),
            ),
        ],
      ),
    );
  }
}
