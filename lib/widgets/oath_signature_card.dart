import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// "Sign Your Seasonal Oath": a finger-drawn signature that seals the
/// commitment to the current quarterly season.
class OathSignatureCard extends ConsumerStatefulWidget {
  const OathSignatureCard({super.key});

  @override
  ConsumerState<OathSignatureCard> createState() => _OathSignatureCardState();
}

class _OathSignatureCardState extends ConsumerState<OathSignatureCard> {
  /// Strokes being drawn, in normalized 0–1 pad coordinates.
  final List<List<Offset>> _draft = [];

  Future<void> _clear(bool sealed) async {
    HapticFeedback.selectionClick();
    setState(_draft.clear);
    if (sealed) await ref.read(rpgStoreProvider.notifier).clearSeasonOath();
  }

  Future<void> _seal() async {
    HapticFeedback.heavyImpact();
    await ref.read(rpgStoreProvider.notifier).signSeasonOath([
      for (final stroke in _draft)
        [
          for (final p in stroke) ...[p.dx, p.dy],
        ],
    ]);
    setState(_draft.clear);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final state = ref.watch(rpgStateProvider);
    final season = state.currentSeason;
    final oath = season.oath;
    final sealed = oath != null;

    final strokes = sealed
        ? [
            for (final flat in oath.strokes)
              [
                for (var i = 0; i + 1 < flat.length; i += 2)
                  Offset(flat[i], flat[i + 1]),
              ],
          ]
        : _draft;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: sealed ? RpgColors.gold : RpgColors.goldDim),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.scroll, size: 18, color: RpgColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sign Your Seasonal Oath',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: RpgColors.gold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _oathText(state),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Stack(
              children: [
                SignaturePad(
                  strokes: strokes,
                  enabled: !sealed,
                  onStrokeStart: (p) => setState(() => _draft.add([p])),
                  onStrokeUpdate: (p) => setState(() => _draft.last.add(p)),
                ),
                if (sealed)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: _SealStamp(date: oath.signedAtDate),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Stacks the buttons vertically when they don't fit side by side.
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              overflowSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: sealed || _draft.isNotEmpty
                      ? () => _clear(sealed)
                      : null,
                  icon: const Icon(LucideIcons.eraser, size: 16),
                  label: const Text('Clear / Re-sign'),
                  style: TextButton.styleFrom(foregroundColor: RpgColors.ink),
                ),
                if (!sealed)
                  FilledButton.icon(
                    onPressed: _draft.isEmpty ? null : _seal,
                    icon: const Icon(LucideIcons.stamp, size: 16),
                    label: const Text('Seal Oath'),
                  ),
              ],
            ),
            if (!sealed)
              Text(
                'Sign with your finger to lock in your commitment.',
                style: styles.stat.copyWith(fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  String _oathText(RpgState state) {
    final season = state.currentSeason;
    final dates = DateFormat.MMMd();
    final branches = BranchType.values.map((b) => b.displayName).toList();
    return 'I, ${state.character.name}, swear to show up for my '
        '${branches.sublist(0, branches.length - 1).join(', ')} and '
        '${branches.last} through ${season.name} '
        '(${dates.format(season.startDate)} – ${dates.format(season.endDate)}). '
        'One point a day. No streak shame. Progress over perfection.';
  }
}

class _SealStamp extends StatelessWidget {
  const _SealStamp({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: RpgColors.gold, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'SEALED · ${DateFormat.MMMd().format(parseDateString(date))}',
          style: RpgStyles.of(context).stat.copyWith(
            color: RpgColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Drawing surface. Points are reported normalized to 0–1 of the pad size.
///
/// Uses a pan recognizer that claims the gesture on touch-down, so signing
/// inside a scrolling list draws instead of scrolling the page.
class SignaturePad extends StatelessWidget {
  const SignaturePad({
    super.key,
    required this.strokes,
    required this.enabled,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    this.height = 150,
  });

  final List<List<Offset>> strokes;
  final bool enabled;
  final ValueChanged<Offset> onStrokeStart;
  final ValueChanged<Offset> onStrokeUpdate;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        Offset normalize(Offset p) => Offset(
          (p.dx / size.width).clamp(0.0, 1.0),
          (p.dy / size.height).clamp(0.0, 1.0),
        );

        final pad = Container(
          height: height,
          decoration: BoxDecoration(
            color: RpgColors.obsidian,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RpgColors.outline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CustomPaint(
              size: size,
              painter: SignaturePainter(strokes: strokes),
            ),
          ),
        );

        return Semantics(
          label: 'Signature pad',
          child: enabled
              ? RawGestureDetector(
                  gestures: {
                    _EagerPanGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          _EagerPanGestureRecognizer
                        >(_EagerPanGestureRecognizer.new, (recognizer) {
                          recognizer
                            ..dragStartBehavior = DragStartBehavior.down
                            ..onStart = (d) {
                              onStrokeStart(normalize(d.localPosition));
                            }
                            ..onUpdate = (d) {
                              onStrokeUpdate(normalize(d.localPosition));
                            };
                        }),
                  },
                  child: pad,
                )
              : pad,
        );
      },
    );
  }
}

class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Paints the signature baseline and smoothed ink strokes.
class SignaturePainter extends CustomPainter {
  SignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final baselineY = size.height * 0.78;
    canvas.drawLine(
      Offset(size.width * 0.06, baselineY),
      Offset(size.width * 0.94, baselineY),
      Paint()
        ..color = RpgColors.outline
        ..strokeWidth = 1,
    );
    final cross = Paint()
      ..color = RpgColors.goldDim
      ..strokeWidth = 1.5;
    final cx = size.width * 0.06;
    final cy = baselineY - 10;
    canvas
      ..drawLine(Offset(cx, cy - 5), Offset(cx + 10, cy + 5), cross)
      ..drawLine(Offset(cx, cy + 5), Offset(cx + 10, cy - 5), cross);

    final ink = Paint()
      ..color = RpgColors.gold
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      final points = [
        for (final p in stroke) Offset(p.dx * size.width, p.dy * size.height),
      ];
      if (points.isEmpty) continue;
      if (points.length == 1) {
        canvas.drawCircle(points.first, 1.6, ink..style = PaintingStyle.fill);
        ink.style = PaintingStyle.stroke;
        continue;
      }
      // Quadratic curves through midpoints for a smooth pen line.
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length - 1; i++) {
        final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
        path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(SignaturePainter old) => true;
}
