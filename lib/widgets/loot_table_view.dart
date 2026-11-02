import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import 'celebration_overlay.dart';
import 'empty_prompt.dart';

/// Tiers with a key to spend and at least one reward to spend it on.
Set<LootTier> choosableLootTiers(WidgetRef ref) {
  final state = ref.read(rpgStateProvider);
  final keys = ref.read(characterSheetProvider).requireValue.lootKeys;
  return {
    for (final tier in LootTier.values)
      if (keys[tier]!.available > 0 &&
          state.loot.any((l) => l.tier == tier && !l.isClaimed))
        tier,
  };
}

/// Lets the user choose one of [tier]'s rewards, spends a key on it and
/// celebrates. Does nothing if the sheet is dismissed.
Future<void> chooseLootReward(
  BuildContext context,
  WidgetRef ref,
  LootTier tier,
) async {
  final rewards = [
    for (final l in ref.read(rpgStateProvider).loot)
      if (l.tier == tier && !l.isClaimed) l,
  ];
  final item = await showModalBottomSheet<LootItem>(
    context: context,
    backgroundColor: RpgColors.slateRaised,
    showDragHandle: true,
    builder: (_) => _PickRewardSheet(tier: tier, rewards: rewards),
  );
  if (item != null && context.mounted) await _claimLoot(context, ref, item);
}

Future<void> _claimLoot(
  BuildContext context,
  WidgetRef ref,
  LootItem item,
) async {
  HapticFeedback.heavyImpact();
  final ok = await ref.read(rpgStoreProvider.notifier).claimLoot(item.id);
  if (!context.mounted) return;
  if (ok) {
    await showLootCelebration(context, item);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No ${item.tier.label} Key available.')),
    );
  }
}

/// Loot Table: treasure chests for unspent keys, the key wallet, rewards
/// grouped by tier, and claim history.
class LootTableView extends ConsumerWidget {
  const LootTableView({super.key});

  Future<void> _roll(BuildContext context, WidgetRef ref, LootTier tier) async {
    final reward = await ref.read(rpgStoreProvider.notifier).rollLoot(tier);
    if (reward != null && context.mounted) {
      await showLootCelebration(context, reward);
    }
  }

  Future<void> _addReward(
    BuildContext context,
    WidgetRef ref,
    LootTier tier,
  ) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _AddRewardDialog(tier: tier),
    );
    if (title == null || title.isEmpty) return;
    await ref.read(rpgStoreProvider.notifier).addLootItem(tier, title);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rpgStateProvider);
    final keys = ref.watch(characterSheetProvider).requireValue.lootKeys;
    final history = state.loot.where((l) => l.isClaimed).toList()
      ..sort((a, b) => _claimTime(b).compareTo(_claimTime(a)));

    List<LootItem> rewardsOf(LootTier tier) => [
      for (final l in state.loot)
        if (l.tier == tier && !l.isClaimed) l,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final tier in LootTier.values)
          if (keys[tier]!.available > 0)
            TreasureChestCard(
              key: ValueKey('chest-${tier.name}'),
              tier: tier,
              keys: keys[tier]!.available,
              rewardCount: rewardsOf(tier).length,
              onRoll: () => _roll(context, ref, tier),
              onPick: () => chooseLootReward(context, ref, tier),
            ),
        _KeyWallet(keys: keys),
        const SizedBox(height: 20),
        for (final tier in LootTier.values)
          _TierSection(
            tier: tier,
            balance: keys[tier]!,
            rewards: rewardsOf(tier),
            onClaim: (item) => _claimLoot(context, ref, item),
            onAdd: () => _addReward(context, ref, tier),
          ),
        const SizedBox(height: 8),
        _ClaimHistory(history: history),
      ],
    );
  }

  static DateTime _claimTime(LootItem item) =>
      item.claimedAt ?? parseDateString(item.claimedAtDate!);
}

/// A glowing chest for a tier with unspent keys: roll a random reward
/// (after a shake) or pick one.
class TreasureChestCard extends StatefulWidget {
  const TreasureChestCard({
    super.key,
    required this.tier,
    required this.keys,
    required this.rewardCount,
    required this.onRoll,
    required this.onPick,
  });

  final LootTier tier;
  final int keys;
  final int rewardCount;
  final Future<void> Function() onRoll;
  final Future<void> Function() onPick;

  @override
  State<TreasureChestCard> createState() => _TreasureChestCardState();
}

class _TreasureChestCardState extends State<TreasureChestCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  bool _busy = false;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool shake = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (shake) {
        // A rattle per quarter of the shake, then the lid flies open.
        for (var i = 0; i < 4; i++) {
          HapticFeedback.selectionClick();
          await _shake.animateTo((i + 1) / 4);
        }
        HapticFeedback.heavyImpact();
        _shake.reset();
      }
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final color = widget.tier.color;
    final canOpen = widget.rewardCount > 0 && !_busy;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.22), RpgColors.slate],
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final t = _shake.value;
                  return Transform.rotate(
                    angle: math.sin(t * math.pi * 8) * 0.18 * (1 - t / 2),
                    child: Transform.scale(scale: 1 + 0.12 * t, child: child),
                  );
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.16),
                    border: Border.all(color: color),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Icon(LucideIcons.package, color: color, size: 26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.tier.label} Treasure Chest',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: color,
                      ),
                    ),
                    Text(
                      widget.rewardCount == 0
                          ? 'Add a ${widget.tier.label} reward below to '
                                'open it.'
                          : '${widget.keys} key${widget.keys == 1 ? '' : 's'}'
                                ' ready · ${widget.rewardCount} reward'
                                '${widget.rewardCount == 1 ? '' : 's'} inside',
                      style: styles.stat,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canOpen
                      ? () => _run(widget.onRoll, shake: true)
                      : null,
                  icon: const Icon(LucideIcons.dices, size: 16),
                  label: const FittedBox(child: Text('Roll Random Loot')),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: RpgColors.obsidian,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canOpen ? () => _run(widget.onPick) : null,
                  icon: const Icon(LucideIcons.gift, size: 16),
                  label: const FittedBox(child: Text('Pick Reward')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lists a tier's rewards; returns the one picked.
class _PickRewardSheet extends StatelessWidget {
  const _PickRewardSheet({required this.tier, required this.rewards});

  final LootTier tier;
  final List<LootItem> rewards;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick a ${tier.label} Reward',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: tier.color),
            ),
            const SizedBox(height: 4),
            Text(
              'Spends 1 ${tier.label} Key.',
              style: RpgStyles.of(context).stat,
            ),
            const SizedBox(height: 8),
            for (final item in rewards)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(LucideIcons.gift, color: tier.color),
                title: Text(item.title),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyWallet extends StatelessWidget {
  const _KeyWallet({required this.keys});

  final Map<LootTier, LootKeyBalance> keys;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: RpgColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RpgColors.goldDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.wallet, size: 16, color: RpgColors.gold),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Loot Keys Wallet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: RpgColors.gold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final tier in LootTier.values)
                Expanded(
                  child: Tooltip(
                    message: '${tier.label}: ${tier.keySource}',
                    child: _KeyTile(tier: tier, balance: keys[tier]!),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Keys are earned automatically from your skill tree and keystones.',
            style: styles.stat.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _KeyTile extends StatelessWidget {
  const _KeyTile({required this.tier, required this.balance});

  final LootTier tier;
  final LootKeyBalance balance;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final has = balance.available > 0;
    final color = tier.color;
    return Semantics(
      container: true,
      label: '${balance.available} ${tier.label} keys available',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: has ? color.withValues(alpha: 0.12) : RpgColors.obsidian,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: has ? color.withValues(alpha: 0.7) : RpgColors.outline,
            ),
          ),
          child: Column(
            children: [
              Icon(
                LucideIcons.key,
                size: 16,
                color: has ? color : RpgColors.outline,
              ),
              const SizedBox(height: 2),
              Text(
                '${balance.available}',
                style: styles.statLarge.copyWith(
                  color: has ? color : RpgColors.ink,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tier.label,
                  style: styles.stat.copyWith(fontSize: 10, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierSection extends StatelessWidget {
  const _TierSection({
    required this.tier,
    required this.balance,
    required this.rewards,
    required this.onClaim,
    required this.onAdd,
  });

  final LootTier tier;
  final LootKeyBalance balance;
  final List<LootItem> rewards;
  final ValueChanged<LootItem> onClaim;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final color = tier.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tier.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: color),
                ),
              ),
              Text(
                '${balance.available} key${balance.available == 1 ? '' : 's'}',
                style: styles.stat.copyWith(color: color),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 8),
            child: Text(
              tier.keySource,
              style: styles.stat.copyWith(fontSize: 10),
            ),
          ),
          if (rewards.isEmpty)
            EmptyPrompt(
              icon: LucideIcons.gift,
              title: 'The loot table is empty',
              message:
                  'Add a real-life ${tier.label} reward to spend '
                  '${tier.label} Keys on.',
              compact: true,
              color: color,
            ),
          for (final item in rewards)
            _RewardTile(
              item: item,
              canClaim: balance.available > 0,
              onClaim: () => onClaim(item),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: Icon(LucideIcons.plus, size: 14, color: color),
              label: Text(
                'Add ${tier.label} reward',
                style: styles.stat.copyWith(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.item,
    required this.canClaim,
    required this.onClaim,
  });

  final LootItem item;
  final bool canClaim;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final color = item.tier.color;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Icon(LucideIcons.gift, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: canClaim
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [],
              ),
              child: FilledButton.icon(
                onPressed: canClaim ? onClaim : null,
                icon: const Icon(LucideIcons.key, size: 14),
                label: const Text('Claim Loot'),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: RpgColors.obsidian,
                  disabledBackgroundColor: RpgColors.slateRaised,
                  disabledForegroundColor: RpgColors.ink,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimHistory extends StatelessWidget {
  const _ClaimHistory({required this.history});

  final List<LootItem> history;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Claimed Loot History',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const EmptyPrompt(
            icon: LucideIcons.key,
            title: 'No loot claimed yet',
            message: 'Earn a key, then claim a reward from the table above.',
            compact: true,
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      LucideIcons.checkCircle2,
                      color: history[i].tier.color,
                      size: 20,
                    ),
                    title: Text(history[i].title),
                    subtitle: Text(
                      '${history[i].tier.label} · ${_formatClaim(history[i])}',
                      style: styles.stat.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static String _formatClaim(LootItem item) {
    final at = item.claimedAt;
    if (at == null) {
      return DateFormat.yMMMd().format(parseDateString(item.claimedAtDate!));
    }
    return DateFormat('MMM d, y · h:mm a').format(at);
  }
}

class _AddRewardDialog extends StatefulWidget {
  const _AddRewardDialog({required this.tier});

  final LootTier tier;

  @override
  State<_AddRewardDialog> createState() => _AddRewardDialogState();
}

class _AddRewardDialogState extends State<_AddRewardDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final hint = switch (widget.tier) {
      LootTier.common => 'e.g. Ice cream party',
      LootTier.rare => 'e.g. Binge TV night',
      LootTier.epic => 'e.g. New guitar gear',
      LootTier.legendary => 'e.g. Weekend trip away',
    };
    return AlertDialog(
      title: Text('New ${widget.tier.label} Reward'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
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
