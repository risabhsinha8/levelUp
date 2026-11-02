import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/character_sheet.dart';
import '../domain/rpg_engine.dart';
import '../models/rpg_models.dart';
import '../models/rpg_state.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';
import 'oath_signature_card.dart';
import 'pixel_avatar.dart';

/// Hands a rendered card PNG to the platform share sheet. [origin] anchors
/// the iPad popover. Override in tests.
typedef CardSharer = Future<void> Function(Uint8List png, {Rect? origin});

final characterCardSharerProvider = Provider<CardSharer>((ref) => shareCardPng);

/// Writes [png] to a temporary file and opens the share sheet with it.
Future<void> shareCardPng(Uint8List png, {Rect? origin}) async {
  const name = 'levelup_character_card.png';
  final XFile file;
  if (kIsWeb) {
    file = XFile.fromData(png, mimeType: 'image/png', name: name);
  } else {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, name);
    await File(path).writeAsBytes(png, flush: true);
    file = XFile(path, mimeType: 'image/png');
  }
  await SharePlus.instance.share(
    ShareParams(
      files: [file],
      text: 'My levelUp character card',
      sharePositionOrigin: origin,
    ),
  );
}

/// Opens the Character Card preview with its share button.
Future<void> showCharacterShareSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: RpgColors.slateRaised,
    builder: (_) => const CharacterShareSheet(),
  );
}

/// The modal: the card preview and "Share / Save Character Card".
class CharacterShareSheet extends ConsumerStatefulWidget {
  const CharacterShareSheet({super.key});

  /// Export scale: the 360×450 card becomes a 1080×1350 PNG.
  static const double pixelRatio = 3;

  @override
  ConsumerState<CharacterShareSheet> createState() =>
      _CharacterShareSheetState();
}

class _CharacterShareSheetState extends ConsumerState<CharacterShareSheet> {
  final _cardKey = GlobalKey();
  final _buttonKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    final share = ref.read(characterCardSharerProvider);
    final boundary =
        _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final button = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = button == null
        ? null
        : button.localToGlobal(Offset.zero) & button.size;
    setState(() => _sharing = true);
    try {
      final image = await boundary.toImage(
        pixelRatio: CharacterShareSheet.pixelRatio,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      HapticFeedback.mediumImpact();
      await share(bytes!.buffer.asUint8List(), origin: origin);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't share the card. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rpgStateProvider);
    final sheet = ref.watch(characterSheetProvider).requireValue;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        children: [
          Text('Character Card', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'A 4:5 card for your feed, story or camera roll.',
            style: RpgStyles.of(context).stat,
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: FittedBox(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: CharacterShareCard(state: state, sheet: sheet),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: _buttonKey,
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.share2, size: 18),
              label: const Text('Share / Save Character Card'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 4:5 trading card, laid out at a fixed 360×450 so the preview and the
/// exported PNG always match.
class CharacterShareCard extends StatelessWidget {
  const CharacterShareCard({
    super.key,
    required this.state,
    required this.sheet,
  });

  static const Size size = Size(360, 450);

  final RpgState state;
  final CharacterSheet sheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = RpgStyles.of(context);
    final season = state.currentSeason;
    final forged = sheet.activeBranches.fold(
      0,
      (sum, b) => sum + sheet.branches[b]!.forgedNodes,
    );
    final daysLogged = {
      for (final log in state.logs)
        if (log.completedHabitIds.isNotEmpty &&
            season.containsDate(log.dateString))
          log.dateString,
    }.length;
    final quests = state.currentQuests.where((q) => q.isCompleted).length;

    // Solid behind the rounded frame so the PNG has no transparent corners.
    return Container(
      width: size.width,
      height: size.height,
      color: RpgColors.obsidian,
      child: CustomPaint(
        foregroundPainter: _OrnateBorderPainter(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [RpgColors.slateRaised, RpgColors.obsidian],
            ),
          ),
          child: Column(
            children: [
              // Header: avatar, name, class, season and the level shield.
              Row(
                children: [
                  PixelAvatar(spec: state.character.avatarOrDefault, size: 58),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.character.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: RpgColors.parchment,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          state.character.classTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: RpgColors.gold,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${season.name} • Day ${sheet.seasonDay}/'
                          '${sheet.seasonLength}',
                          style: styles.stat.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  // Clear of the corner flourish.
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10),
                    child: _LevelShield(level: sheet.totalLevel),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Semantics(
                  label: [
                    for (final b in sheet.activeBranches)
                      '${state.nameOf(b)} level ${sheet.branches[b]!.level}',
                  ].join(', '),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: AttributeRadarPainter(
                      levels: {
                        for (final b in sheet.activeBranches)
                          b: sheet.branches[b]!.level,
                      },
                      names: {
                        for (final b in sheet.activeBranches)
                          b: state.nameOf(b),
                      },
                      labelStyle: styles.stat.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Stats footer.
              Row(
                children: [
                  _Stat(value: '$daysLogged', label: 'Days Logged'),
                  _Stat(
                    value:
                        '$forged / '
                        '${RpgEngine.maxNodesPerBranch * sheet.activeBranches.length}',
                    label: 'Nodes Forged',
                  ),
                  _Stat(value: '$quests', label: 'Quests Done'),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: _OathSignature(
                  oath: season.oath,
                  typed: state.character.signatureText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: RpgColors.obsidian,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: RpgColors.goldDim.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: styles.statLarge.copyWith(
                  fontSize: 17,
                  color: RpgColors.parchment,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                style: styles.stat.copyWith(
                  fontSize: 8,
                  letterSpacing: 0.8,
                  color: RpgColors.goldDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The drawn oath if sealed, else the typed signature, else a blank line.
class _OathSignature extends StatelessWidget {
  const _OathSignature({required this.oath, required this.typed});

  final SeasonOath? oath;
  final String typed;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    final oath = this.oath;
    if (oath != null) {
      return Semantics(
        label: 'Seasonal oath signature',
        child: CustomPaint(
          size: Size.infinite,
          painter: SignaturePainter(
            strokes: [
              for (final flat in oath.strokes)
                [
                  for (var i = 0; i + 1 < flat.length; i += 2)
                    Offset(flat[i], flat[i + 1]),
                ],
            ],
          ),
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          typed.isEmpty ? 'Oath unsigned' : '“$typed”',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.stat.copyWith(
            color: typed.isEmpty ? RpgColors.ink : RpgColors.gold,
            fontStyle: FontStyle.italic,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: RpgColors.outline),
      ],
    );
  }
}

class _LevelShield extends StatelessWidget {
  const _LevelShield({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return Semantics(
      label: 'Overall level $level',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 66,
          height: 76,
          child: CustomPaint(
            painter: _ShieldPainter(),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'LV',
                    style: styles.stat.copyWith(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: RpgColors.obsidian,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$level',
                    style: styles.statLarge.copyWith(
                      fontSize: 26,
                      height: 1,
                      color: RpgColors.obsidian,
                    ),
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

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shield = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h * 0.14)
      ..lineTo(w, h * 0.5)
      ..quadraticBezierTo(w, h * 0.82, w / 2, h)
      ..quadraticBezierTo(0, h * 0.82, 0, h * 0.5)
      ..lineTo(0, h * 0.14)
      ..close();
    canvas
      ..drawShadow(shield, RpgColors.gold, 6, false)
      ..drawPath(
        shield,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF1D77A), RpgColors.gold, RpgColors.goldDim],
          ).createShader(Offset.zero & size),
      )
      ..drawPath(
        shield,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = RpgColors.parchment.withValues(alpha: 0.7),
      );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => false;
}

/// Gold outer frame, a dim inner rule and a flourish in each corner.
class _OrnateBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1.5),
      const Radius.circular(18),
    );
    final inner = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(8),
      const Radius.circular(12),
    );
    canvas
      ..drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = RpgColors.gold,
      )
      ..drawRRect(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = RpgColors.goldDim,
      );

    final flourish = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = RpgColors.gold;
    final gem = Paint()..color = RpgColors.gold;
    // Draw the top-left flourish, mirrored into the other corners.
    for (final (sx, sy) in const [
      (1.0, 1.0),
      (-1.0, 1.0),
      (1.0, -1.0),
      (-1.0, -1.0),
    ]) {
      canvas
        ..save()
        ..translate(sx > 0 ? 0 : size.width, sy > 0 ? 0 : size.height)
        ..scale(sx, sy);
      final curl = Path()
        ..moveTo(14, 34)
        ..quadraticBezierTo(14, 14, 34, 14)
        ..moveTo(20, 46)
        ..quadraticBezierTo(22, 22, 46, 20);
      canvas
        ..drawPath(curl, flourish)
        ..drawPath(
          Path()
            ..moveTo(14, 8)
            ..lineTo(20, 14)
            ..lineTo(14, 20)
            ..lineTo(8, 14)
            ..close(),
          gem,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_OrnateBorderPainter old) => false;
}

/// Radar of the active pillars' levels (a pentagon for five), each axis in
/// its branch color.
class AttributeRadarPainter extends CustomPainter {
  AttributeRadarPainter({
    required this.levels,
    this.names = const {},
    required this.labelStyle,
  });

  /// Level per axis, in axis order.
  final Map<BranchType, int> levels;

  /// Axis labels; default names when missing.
  final Map<BranchType, String> names;
  final TextStyle labelStyle;

  /// The outer ring's level: at least 5, rounded up to a multiple of 5.
  int get scaleMax {
    final top = levels.values.fold(0, math.max);
    return math.max(5, (top / 5).ceil() * 5);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero).translate(0, 4);
    final radius = math.min(size.width, size.height) / 2 - 30;
    final branches = levels.keys.toList();
    Offset point(int i, double fraction) {
      final angle = -math.pi / 2 + 2 * math.pi * i / branches.length;
      return center +
          Offset(math.cos(angle), math.sin(angle)) * radius * fraction;
    }

    Path ring(double fraction) {
      final path = Path()..moveTo(point(0, fraction).dx, point(0, fraction).dy);
      for (var i = 1; i < branches.length; i++) {
        path.lineTo(point(i, fraction).dx, point(i, fraction).dy);
      }
      return path..close();
    }

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = RpgColors.outline;
    for (final f in [0.2, 0.4, 0.6, 0.8, 1.0]) {
      canvas.drawPath(ring(f), grid);
    }

    final max = scaleMax;
    final values = [
      for (final b in branches) ((levels[b] ?? 0) / max).clamp(0.0, 1.0),
    ];
    for (final (i, b) in branches.indexed) {
      canvas.drawLine(
        center,
        point(i, 1),
        Paint()
          ..strokeWidth = 1.2
          ..color = b.color.withValues(alpha: 0.5),
      );
    }

    final shape = Path()
      ..moveTo(point(0, values[0]).dx, point(0, values[0]).dy);
    for (var i = 1; i < branches.length; i++) {
      shape.lineTo(point(i, values[i]).dx, point(i, values[i]).dy);
    }
    shape.close();
    canvas
      ..drawPath(shape, Paint()..color = RpgColors.gold.withValues(alpha: 0.2))
      ..drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = RpgColors.gold,
      );

    for (final (i, b) in branches.indexed) {
      final vertex = point(i, values[i]);
      canvas
        ..drawCircle(vertex, 5, Paint()..color = RpgColors.obsidian)
        ..drawCircle(vertex, 4, Paint()..color = b.color);

      final label = TextPainter(
        text: TextSpan(
          text: '${names[b] ?? b.displayName}\n',
          style: labelStyle.copyWith(color: b.color),
          children: [
            TextSpan(
              text: 'Lv ${levels[b] ?? 0}',
              style: labelStyle.copyWith(
                color: RpgColors.parchment,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      final anchor = point(i, 1.22);
      label.paint(canvas, anchor - Offset(label.width / 2, label.height / 2));
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(AttributeRadarPainter old) =>
      !mapEquals(old.levels, levels) ||
      !mapEquals(old.names, names) ||
      old.labelStyle != labelStyle;
}
