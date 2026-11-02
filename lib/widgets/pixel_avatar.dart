import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../domain/avatar_sprite.dart';
import '../models/rpg_models.dart';
import '../providers/rpg_store_provider.dart';
import '../theme/rpg_theme.dart';

/// The character's pixel-art bust on its backdrop, framed in gold.
class PixelAvatar extends StatelessWidget {
  const PixelAvatar({super.key, required this.spec, this.size = 64});

  final AvatarSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.18);
    return Semantics(
      image: true,
      label: 'Avatar',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color(AvatarPalette.backgrounds[spec.background]),
          borderRadius: radius,
          border: Border.all(color: RpgColors.gold, width: size > 80 ? 2 : 1.5),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: CustomPaint(painter: _SpritePainter(spec)),
        ),
      ),
    );
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.spec) : pixels = AvatarSprite.compose(spec);

  final AvatarSpec spec;
  final List<int?> pixels;

  @override
  void paint(Canvas canvas, Size size) {
    // The bust sits on the bottom edge, with a little headroom.
    const grid = AvatarSprite.size;
    final pixel = size.shortestSide * 0.86 / grid;
    final left = (size.width - pixel * grid) / 2;
    final top = size.height - pixel * grid;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < grid; y++) {
      for (var x = 0; x < grid; x++) {
        final color = pixels[y * grid + x];
        if (color == null) continue;
        canvas.drawRect(
          // Slight overlap hides seams between pixels.
          Rect.fromLTWH(
            left + x * pixel,
            top + y * pixel,
            pixel + 0.5,
            pixel + 0.5,
          ),
          paint..color = Color(color),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter old) => old.spec != spec;
}

/// Preview, Randomize and a ◀ ▶ cycler per avatar slot. With [collapsible]
/// the cyclers hide behind "Customize" (Session Zero).
class AvatarEditor extends ConsumerStatefulWidget {
  const AvatarEditor({
    super.key,
    required this.spec,
    required this.onChanged,
    this.collapsible = false,
  });

  final AvatarSpec spec;
  final ValueChanged<AvatarSpec> onChanged;
  final bool collapsible;

  @override
  ConsumerState<AvatarEditor> createState() => _AvatarEditorState();
}

class _AvatarEditorState extends ConsumerState<AvatarEditor> {
  late bool _expanded = !widget.collapsible;

  void _randomize() {
    HapticFeedback.mediumImpact();
    widget.onChanged(AvatarSpec.random(ref.read(randomProvider)));
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final set = widget.onChanged;
    T step<T>(List<T> options, T current, int by) =>
        options[(options.indexOf(current) + by) % options.length];
    int swatch(List<int> swatches, int current, int by) =>
        (current + by) % swatches.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: PixelAvatar(key: ValueKey(spec), spec: spec, size: 104),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('avatar-randomize'),
                    onPressed: _randomize,
                    icon: const Icon(LucideIcons.dice5, size: 18),
                    label: const Text('Randomize'),
                  ),
                  if (widget.collapsible)
                    TextButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded
                            ? LucideIcons.chevronUp
                            : LucideIcons.slidersHorizontal,
                        size: 16,
                      ),
                      label: Text(_expanded ? 'Done' : 'Customize'),
                    ),
                ],
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    children: [
                      _Cycler(
                        slot: 'skin',
                        label: 'Skin',
                        swatch: AvatarPalette.skinTones[spec.skinTone],
                        onStep: (by) => set(
                          spec.copyWith(
                            skinTone: swatch(
                              AvatarPalette.skinTones,
                              spec.skinTone,
                              by,
                            ),
                          ),
                        ),
                      ),
                      _Cycler(
                        slot: 'hair',
                        label: 'Hair',
                        value: spec.hair.label,
                        onStep: (by) => set(
                          spec.copyWith(
                            hair: step(AvatarHair.values, spec.hair, by),
                          ),
                        ),
                      ),
                      _Cycler(
                        slot: 'hair-color',
                        label: 'Hair color',
                        swatch: AvatarPalette.hairColors[spec.hairColor],
                        onStep: (by) => set(
                          spec.copyWith(
                            hairColor: swatch(
                              AvatarPalette.hairColors,
                              spec.hairColor,
                              by,
                            ),
                          ),
                        ),
                      ),
                      _Cycler(
                        slot: 'face',
                        label: 'Face',
                        value: spec.face.label,
                        onStep: (by) => set(
                          spec.copyWith(
                            face: step(AvatarFace.values, spec.face, by),
                          ),
                        ),
                      ),
                      _Cycler(
                        slot: 'outfit',
                        label: 'Outfit',
                        value: spec.outfit.label,
                        onStep: (by) => set(
                          spec.copyWith(
                            outfit: step(AvatarOutfit.values, spec.outfit, by),
                          ),
                        ),
                      ),
                      _Cycler(
                        slot: 'outfit-color',
                        label: 'Outfit color',
                        swatch: AvatarPalette.outfitColors[spec.outfitColor],
                        onStep: (by) => set(
                          spec.copyWith(
                            outfitColor: swatch(
                              AvatarPalette.outfitColors,
                              spec.outfitColor,
                              by,
                            ),
                          ),
                        ),
                      ),
                      _Cycler(
                        slot: 'headgear',
                        label: 'Headgear',
                        value: spec.headgear.label,
                        onStep: (by) => set(
                          spec.copyWith(
                            headgear: step(
                              AvatarHeadgear.values,
                              spec.headgear,
                              by,
                            ),
                          ),
                        ),
                      ),
                      _Cycler(
                        slot: 'backdrop',
                        label: 'Backdrop',
                        swatch: AvatarPalette.backgrounds[spec.background],
                        onStep: (by) => set(
                          spec.copyWith(
                            background: swatch(
                              AvatarPalette.backgrounds,
                              spec.background,
                              by,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// "Hair   ◀ Short ▶": steps one avatar slot backward or forward.
class _Cycler extends StatelessWidget {
  const _Cycler({
    required this.slot,
    required this.label,
    required this.onStep,
    this.value,
    this.swatch,
  });

  final String slot;
  final String label;
  final ValueChanged<int> onStep;
  final String? value;
  final int? swatch;

  @override
  Widget build(BuildContext context) {
    final styles = RpgStyles.of(context);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(child: Text(label, style: styles.stat)),
          IconButton(
            key: ValueKey('avatar-prev-$slot'),
            tooltip: 'Previous $label',
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.chevronLeft, size: 18),
            onPressed: () => onStep(-1),
          ),
          SizedBox(
            width: 92,
            child: Center(
              child: swatch != null
                  ? Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(swatch!),
                        shape: BoxShape.circle,
                        border: Border.all(color: RpgColors.parchment),
                      ),
                    )
                  : Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.stat.copyWith(color: RpgColors.parchment),
                    ),
            ),
          ),
          IconButton(
            key: ValueKey('avatar-next-$slot'),
            tooltip: 'Next $label',
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.chevronRight, size: 18),
            onPressed: () => onStep(1),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to change the character's avatar; saves on "Save".
Future<void> showAvatarEditor(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: RpgColors.slateRaised,
    builder: (_) => const _AvatarEditorSheet(),
  );
}

class _AvatarEditorSheet extends ConsumerStatefulWidget {
  const _AvatarEditorSheet();

  @override
  ConsumerState<_AvatarEditorSheet> createState() => _AvatarEditorSheetState();
}

class _AvatarEditorSheetState extends ConsumerState<_AvatarEditorSheet> {
  late AvatarSpec _spec = ref.read(rpgStateProvider).character.avatarOrDefault;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Avatar', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            AvatarEditor(
              spec: _spec,
              onChanged: (spec) => setState(() => _spec = spec),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await ref.read(rpgStoreProvider.notifier).updateAvatar(_spec);
                navigator.pop();
              },
              child: const Text('Save Avatar'),
            ),
          ],
        ),
      ),
    );
  }
}
