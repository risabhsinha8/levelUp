import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/character_sheet.dart';
import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import 'empty_prompt.dart';

/// [unlocked] nodes are forged; [readyToForge] ones are earned by active
/// days but wait for the user to hold them.
enum NodeState { unlocked, readyToForge, inProgress, locked }

/// State of node [index] (0-based) for a branch with [stats].
NodeState nodeStateFor(BranchStats stats, int index) {
  if (index < stats.forgedNodes) return NodeState.unlocked;
  if (index < stats.unlockedNodes) return NodeState.readyToForge;
  if (index == stats.unlockedNodes) return NodeState.inProgress;
  return NodeState.locked;
}

/// The active pillars side by side, each with 5 milestone nodes growing
/// upward from a root, joined by energy paths that fill as active days
/// accrue. Scrolls sideways when the columns would be too narrow.
class SkillTreeCanvas extends StatelessWidget {
  const SkillTreeCanvas({super.key, required this.sheet, this.onForge});

  final CharacterSheet sheet;

  /// Called when a ready node of a branch has been held long enough.
  final ValueChanged<BranchType>? onForge;

  static const double height = 400;
  static const double nodeSize = 46;
  static const double _top = 30;
  static const double _rootArea = 64;
  static const double _minColumnWidth = 58;

  static double _nodeY(int index) {
    const bottom = height - _rootArea - nodeSize / 2 - 8;
    const top = _top + nodeSize / 2;
    final step = (bottom - top) / (RpgEngine.maxNodesPerBranch - 1);
    return bottom - index * step;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final branches = sheet.activeBranches;
          final width = math.max(
            constraints.maxWidth,
            _minColumnWidth * branches.length,
          );
          final columnWidth = width / branches.length;
          double columnX(BranchType b) =>
              columnWidth * (branches.indexOf(b) + 0.5);

          final tree = TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, charge, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EnergyPathPainter(
                      sheet: sheet,
                      columnWidth: columnWidth,
                      nodeY: _nodeY,
                      rootY: height - _rootArea + 6,
                      charge: charge,
                    ),
                  ),
                ),
                for (final branch in branches) ...[
                  for (var i = 0; i < RpgEngine.maxNodesPerBranch; i++)
                    Positioned(
                      left: columnX(branch) - nodeSize / 2,
                      top: _nodeY(i) - nodeSize / 2,
                      child: SkillNode(
                        key: ValueKey('node-${branch.name}-$i'),
                        stats: sheet.branches[branch]!,
                        index: i,
                        charge: charge,
                        onTap: () => showNodeDetails(context, branch, i),
                        onForge: onForge == null
                            ? null
                            : () => onForge!(branch),
                      ),
                    ),
                  if (sheet.branches[branch]!.readyToForge > 0)
                    Positioned(
                      left: columnX(branch) - columnWidth / 2 + 2,
                      width: columnWidth - 4,
                      top:
                          _nodeY(sheet.branches[branch]!.forgedNodes) +
                          nodeSize / 2 -
                          4,
                      child: const IgnorePointer(child: _ForgeBadge()),
                    ),
                  Positioned(
                    left: columnX(branch) - columnWidth / 2,
                    width: columnWidth,
                    top: height - _rootArea + 12,
                    child: _BranchRoot(stats: sheet.branches[branch]!),
                  ),
                ],
              ],
            ),
          );
          if (width <= constraints.maxWidth) return tree;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width, child: tree),
          );
        },
      ),
    );
  }
}

class _BranchRoot extends StatelessWidget {
  const _BranchRoot({required this.stats});

  final BranchStats stats;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final color = stats.branch.color;
    return Column(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          stats.name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: styles.stat.copyWith(
            fontSize: 10,
            color: color,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '${stats.activeDays}d · Lv ${stats.level}',
          maxLines: 1,
          softWrap: false,
          style: styles.stat.copyWith(fontSize: 9),
        ),
      ],
    );
  }
}

class _EnergyPathPainter extends CustomPainter {
  _EnergyPathPainter({
    required this.sheet,
    required this.columnWidth,
    required this.nodeY,
    required this.rootY,
    required this.charge,
  });

  final CharacterSheet sheet;
  final double columnWidth;
  final double Function(int index) nodeY;
  final double rootY;

  /// 0–1 intro animation: energy flows up from the roots.
  final double charge;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()
      ..color = RpgColors.outline
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Ground line joining the roots.
    canvas.drawLine(
      Offset(columnWidth * 0.5, rootY),
      Offset(size.width - columnWidth * 0.5, rootY),
      dim..color = RpgColors.outline.withValues(alpha: 0.6),
    );
    dim.color = RpgColors.outline;

    for (final (column, branch) in sheet.activeBranches.indexed) {
      final stats = sheet.branches[branch]!;
      final x = columnWidth * (column + 0.5);
      final color = branch.color;
      final glow = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      final core = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      var previousThreshold = 0;
      var fromY = rootY;
      for (var i = 0; i < RpgEngine.maxNodesPerBranch; i++) {
        final threshold = RpgEngine.nodeThresholds[i];
        final toY = nodeY(i) + SkillTreeCanvas.nodeSize / 2;
        final from = Offset(x, fromY);
        final to = Offset(x, toY);
        canvas.drawLine(from, to, dim);

        final fill =
            ((stats.activeDays - previousThreshold) /
                    (threshold - previousThreshold))
                .clamp(0.0, 1.0) *
            charge;
        if (fill > 0) {
          final lit = Offset.lerp(from, to, fill)!;
          canvas
            ..drawLine(from, lit, glow)
            ..drawLine(from, lit, core);
        }
        previousThreshold = threshold;
        fromY = nodeY(i) - SkillTreeCanvas.nodeSize / 2;
      }
    }
  }

  @override
  bool shouldRepaint(_EnergyPathPainter old) =>
      old.sheet != sheet ||
      old.charge != charge ||
      old.columnWidth != columnWidth;
}

/// Floating "Hold to Forge (+1 Lvl)" pill under a branch's next ready node.
class _ForgeBadge extends StatelessWidget {
  const _ForgeBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: RpgColors.gold,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: RpgColors.gold.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
          child: Text(
            'Hold to Forge (+1 Lvl)',
            style: RpgStyles.of(context).stat.copyWith(
              fontSize: 9,
              color: RpgColors.obsidian,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// One milestone node. Forged: filled and glowing; ready to forge: pulsing
/// gold, held to claim; next: progress ring with `days/threshold`; locked:
/// dim outline with its threshold.
class SkillNode extends StatelessWidget {
  const SkillNode({
    super.key,
    required this.stats,
    required this.index,
    required this.onTap,
    this.onForge,
    this.charge = 1,
  });

  final BranchStats stats;
  final int index;
  final VoidCallback onTap;

  /// Forges the branch's next ready node; null disables holding.
  final VoidCallback? onForge;
  final double charge;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final state = nodeStateFor(stats, index);
    final threshold = RpgEngine.nodeThresholds[index];
    final color = stats.branch.color;
    const size = SkillTreeCanvas.nodeSize;

    if (state == NodeState.readyToForge) {
      return ForgeableNode(
        color: color,
        label: '${stats.name} node ${index + 1}, ready to forge',
        onTap: onTap,
        onForge: onForge,
      );
    }

    // Ready nodes returned above; they share the forged arms below.
    final label = switch (state) {
      NodeState.unlocked ||
      NodeState.readyToForge => '${stats.name} node ${index + 1}, unlocked',
      NodeState.inProgress =>
        '${stats.name} node ${index + 1}, '
            '${stats.activeDays} of $threshold days',
      NodeState.locked =>
        '${stats.name} node ${index + 1}, locked, '
            'unlocks at $threshold days',
    };

    final Widget body = switch (state) {
      NodeState.unlocked || NodeState.readyToForge => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.55 * charge),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          LucideIcons.check,
          size: 22,
          color: RpgColors.obsidian,
        ),
      ),
      NodeState.inProgress => CustomPaint(
        painter: _ProgressRingPainter(
          color: color,
          progress: stats.activeDays / threshold * charge,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                '${stats.activeDays}/$threshold',
                style: styles.stat.copyWith(
                  fontSize: 10,
                  color: RpgColors.parchment,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
      NodeState.locked => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: RpgColors.slate,
          border: Border.all(color: RpgColors.outline, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          '$threshold',
          style: styles.stat.copyWith(
            fontSize: 12,
            color: RpgColors.ink.withValues(alpha: 0.7),
          ),
        ),
      ),
    };

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: ExcludeSemantics(child: body),
        ),
      ),
    );
  }
}

/// A ready-to-forge node: a pulsing gold aura, and a gold ring that fills
/// while the user holds it for [holdDuration], ticking haptics every 200 ms
/// and landing a heavy impact when [onForge] fires.
class ForgeableNode extends StatefulWidget {
  const ForgeableNode({
    super.key,
    required this.color,
    required this.label,
    required this.onTap,
    required this.onForge,
  });

  static const holdDuration = Duration(milliseconds: 1200);
  static const _tick = Duration(milliseconds: 200);

  final Color color;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onForge;

  @override
  State<ForgeableNode> createState() => _ForgeableNodeState();
}

class _ForgeableNodeState extends State<ForgeableNode>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: ForgeableNode.holdDuration,
    reverseDuration: const Duration(milliseconds: 250),
  )..addListener(_onHoldTick);
  Offset? _downAt;
  int _ticks = 0;
  bool _forged = false;

  /// Set once a hold gets going, so releasing it doesn't also count as a
  /// tap that opens the node's details.
  bool _suppressTap = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honor reduce-motion: a steady glow instead of a pulse.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _hold.dispose();
    super.dispose();
  }

  void _onHoldTick() {
    if (_hold.status != AnimationStatus.forward) return;
    // Forge the moment the ring is full (the controller reports
    // "completed" a frame later).
    if (_hold.value >= 1) {
      if (!_forged) _forge();
      return;
    }
    final elapsed = ForgeableNode.holdDuration * _hold.value;
    final ticks = elapsed.inMilliseconds ~/ ForgeableNode._tick.inMilliseconds;
    if (ticks > _ticks) {
      _ticks = ticks;
      _suppressTap = true;
      HapticFeedback.selectionClick();
    }
  }

  void _forge() {
    _forged = true;
    HapticFeedback.heavyImpact();
    widget.onForge?.call();
  }

  void _start(PointerDownEvent event) {
    if (widget.onForge == null || _forged) return;
    _downAt = event.position;
    _ticks = 0;
    _suppressTap = false;
    _hold.forward(from: 0);
  }

  void _cancel() {
    _downAt = null;
    if (!_forged && _hold.value > 0) _hold.reverse();
  }

  @override
  Widget build(BuildContext context) {
    const size = SkillTreeCanvas.nodeSize;
    return Semantics(
      button: true,
      label: widget.label,
      hint: 'Hold to forge, +1 level',
      onLongPress: widget.onForge == null || _forged ? null : _forge,
      child: Listener(
        onPointerDown: _start,
        onPointerUp: (_) => _cancel(),
        onPointerCancel: (_) => _cancel(),
        onPointerMove: (event) {
          final down = _downAt;
          if (down != null && (event.position - down).distance > 20) {
            _cancel();
          }
        },
        child: GestureDetector(
          onTap: () {
            if (!_suppressTap && !_forged) widget.onTap();
          },
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: size,
            height: size,
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: Listenable.merge([_pulse, _hold]),
                builder: (context, _) {
                  final pulse = Curves.easeInOut.transform(_pulse.value);
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: 1 + 0.08 * pulse + 0.1 * _hold.value,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: RpgColors.gold,
                            border: Border.all(color: widget.color, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: RpgColors.gold.withValues(
                                  alpha: 0.35 + 0.35 * pulse,
                                ),
                                blurRadius: 12 + 12 * pulse,
                                spreadRadius: 1 + 3 * pulse,
                              ),
                            ],
                          ),
                          child: const Icon(
                            LucideIcons.hammer,
                            size: 20,
                            color: RpgColors.obsidian,
                          ),
                        ),
                      ),
                      if (_hold.value > 0)
                        Positioned(
                          left: -7,
                          top: -7,
                          right: -7,
                          bottom: -7,
                          child: CustomPaint(
                            painter: _HoldRingPainter(progress: _hold.value),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldRingPainter extends CustomPainter {
  _HoldRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..drawArc(
        rect.deflate(2),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = RpgColors.gold.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawArc(
        rect.deflate(2),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = RpgColors.gold,
      );
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) => old.progress != progress;
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;
    canvas.drawCircle(center, radius + 3, Paint()..color = RpgColors.obsidian);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = RpgColors.outline,
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas
      ..drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Opens the bottom sheet for node [index] of [branch].
Future<void> showNodeDetails(
  BuildContext context,
  BranchType branch,
  int index,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: RpgColors.slateRaised,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => NodeDetailSheet(branch: branch, index: index),
  );
}

class NodeDetailSheet extends ConsumerWidget {
  const NodeDetailSheet({super.key, required this.branch, required this.index});

  final BranchType branch;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final state = ref.watch(rpgStateProvider);
    final stats = ref
        .watch(characterSheetProvider)
        .requireValue
        .branches[branch]!;
    final threshold = RpgEngine.nodeThresholds[index];
    final nodeState = nodeStateFor(stats, index);
    final daysLeft = math.max(0, threshold - stats.activeDays);
    final color = branch.color;
    final isFinal = index == RpgEngine.maxNodesPerBranch - 1;
    final habits = state.habitsFor(branch);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${stats.name} · Node ${index + 1}',
                    style: theme.textTheme.titleLarge?.copyWith(color: color),
                  ),
                ),
                Text('$threshold days', style: styles.stat),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              switch (nodeState) {
                NodeState.unlocked => 'Forged',
                NodeState.readyToForge =>
                  'Ready to forge: hold the glowing node on the Skill Tree',
                _ =>
                  '$daysLeft more active day${daysLeft == 1 ? '' : 's'} '
                      'to unlock',
              },
              style: theme.textTheme.titleMedium?.copyWith(
                color: switch (nodeState) {
                  NodeState.unlocked => color,
                  NodeState.readyToForge => RpgColors.gold,
                  _ => RpgColors.parchment,
                },
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (stats.activeDays / threshold).clamp(0.0, 1.0),
                minHeight: 6,
                color: color,
                backgroundColor: RpgColors.outline,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${math.min(stats.activeDays, threshold)}/$threshold '
              '${stats.name} active days this season',
              style: styles.stat,
            ),
            const SizedBox(height: 4),
            Text(
              isFinal
                  ? 'Reward: Rare Key + Epic Key (branch mastered)'
                  : 'Reward: Rare Key',
              style: styles.stat.copyWith(color: RpgColors.gold),
            ),
            const SizedBox(height: 20),
            Text('Contributing habits', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Any one of these done earns the day. Max 1 point per day.',
              style: styles.stat.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 8),
            if (habits.isEmpty)
              EmptyPrompt(
                icon: LucideIcons.sprout,
                title: 'No ${stats.name} habits yet',
                message:
                    "Add one from Today's Focus to start earning "
                    '${stats.name} days.',
                compact: true,
                color: color,
              )
            else
              for (final habit in habits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        habit.isKeystone
                            ? Icons.star_rounded
                            : Icons.circle_outlined,
                        size: habit.isKeystone ? 18 : 10,
                        color: habit.isKeystone ? RpgColors.gold : color,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              habit.isArchived
                                  ? '${habit.title} (archived)'
                                  : habit.title,
                            ),
                            if (habit.targetCriteria.isNotEmpty)
                              Text(habit.targetCriteria, style: styles.stat),
                          ],
                        ),
                      ),
                      Text(
                        '${RpgEngine.calculateHabitActiveDays(habit.id, state.logs, season: state.currentSeason)}d',
                        style: styles.stat.copyWith(color: RpgColors.parchment),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
