/// The character's pixel-art avatar: which part and color is picked for
/// each slot. Pure Dart; `lib/domain/avatar_sprite.dart` turns it into
/// pixels.
library;

import 'dart:math' as math;

enum AvatarHair {
  short('Short'),
  long('Long'),
  spiky('Spiky'),
  bun('Bun'),
  mohawk('Mohawk'),
  bald('Bald');

  const AvatarHair(this.label);
  final String label;
}

enum AvatarFace {
  bright('Bright'),
  cheerful('Cheerful'),
  calm('Calm'),
  fierce('Fierce'),
  spectacled('Spectacled'),
  sleepy('Sleepy');

  const AvatarFace(this.label);
  final String label;
}

enum AvatarOutfit {
  tunic('Tunic'),
  robe('Robe'),
  armor('Armor'),
  cloak('Cloak');

  const AvatarOutfit(this.label);
  final String label;
}

enum AvatarHeadgear {
  none('None'),
  hood('Hood'),
  wizardHat('Wizard Hat'),
  helmet('Helmet'),
  crown('Crown'),
  headband('Headband');

  const AvatarHeadgear(this.label);
  final String label;
}

/// ARGB swatches for the color slots.
abstract final class AvatarPalette {
  static const skinTones = [
    0xFFFFE0BD,
    0xFFF1C27D,
    0xFFE0AC69,
    0xFFC68642,
    0xFF8D5524,
    0xFF5C3A21,
    0xFF8FBF6A, // Orc green
    0xFF8FB3E0, // Frost blue
  ];

  static const hairColors = [
    0xFF2B2B2B,
    0xFF6B4226,
    0xFFA0522D,
    0xFFE6C35C,
    0xFFE8E8E8,
    0xFFC0392B,
    0xFF3B82F6,
    0xFF8B5CF6,
  ];

  static const outfitColors = [
    0xFFB91C1C, // Crimson
    0xFF15803D, // Forest
    0xFF4338CA, // Indigo
    0xFFB45309, // Amber
    0xFF7E22CE, // Violet
    0xFF475569, // Slate
    0xFF0F766E, // Teal
    0xFF78350F, // Leather
  ];

  static const backgrounds = [
    0xFF2A2F45,
    0xFF3B2A45,
    0xFF2A4536,
    0xFF45352A,
    0xFF452A2F,
    0xFF2A4045,
    0xFF3A3A3A,
    0xFF453F2A,
  ];
}

class AvatarSpec {
  const AvatarSpec({
    this.skinTone = 1,
    this.hair = AvatarHair.short,
    this.hairColor = 1,
    this.face = AvatarFace.bright,
    this.outfit = AvatarOutfit.tunic,
    this.outfitColor = 0,
    this.headgear = AvatarHeadgear.none,
    this.background = 0,
  });

  /// Every part picked at random from [random].
  factory AvatarSpec.random(math.Random random) {
    T pick<T>(List<T> options) => options[random.nextInt(options.length)];
    int index(List<int> swatches) => random.nextInt(swatches.length);
    return AvatarSpec(
      skinTone: index(AvatarPalette.skinTones),
      hair: pick(AvatarHair.values),
      hairColor: index(AvatarPalette.hairColors),
      face: pick(AvatarFace.values),
      outfit: pick(AvatarOutfit.values),
      outfitColor: index(AvatarPalette.outfitColors),
      headgear: pick(AvatarHeadgear.values),
      background: index(AvatarPalette.backgrounds),
    );
  }

  /// A stable avatar derived from [seed] (e.g. the character's name), for
  /// characters who never picked one.
  factory AvatarSpec.seeded(String seed) {
    var hash = 17;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return AvatarSpec.random(math.Random(hash));
  }

  /// Index into [AvatarPalette.skinTones].
  final int skinTone;
  final AvatarHair hair;

  /// Index into [AvatarPalette.hairColors].
  final int hairColor;
  final AvatarFace face;
  final AvatarOutfit outfit;

  /// Index into [AvatarPalette.outfitColors].
  final int outfitColor;
  final AvatarHeadgear headgear;

  /// Index into [AvatarPalette.backgrounds].
  final int background;

  AvatarSpec copyWith({
    int? skinTone,
    AvatarHair? hair,
    int? hairColor,
    AvatarFace? face,
    AvatarOutfit? outfit,
    int? outfitColor,
    AvatarHeadgear? headgear,
    int? background,
  }) {
    return AvatarSpec(
      skinTone: skinTone ?? this.skinTone,
      hair: hair ?? this.hair,
      hairColor: hairColor ?? this.hairColor,
      face: face ?? this.face,
      outfit: outfit ?? this.outfit,
      outfitColor: outfitColor ?? this.outfitColor,
      headgear: headgear ?? this.headgear,
      background: background ?? this.background,
    );
  }

  Map<String, dynamic> toJson() => {
    'skinTone': skinTone,
    'hair': hair.name,
    'hairColor': hairColor,
    'face': face.name,
    'outfit': outfit.name,
    'outfitColor': outfitColor,
    'headgear': headgear.name,
    'background': background,
  };

  /// Unknown part names and out-of-range colors fall back to defaults, so a
  /// backup from a newer version still loads.
  factory AvatarSpec.fromJson(Map<String, dynamic> json) {
    const defaults = AvatarSpec();
    T part<T extends Enum>(List<T> values, String key, T fallback) =>
        values.asNameMap()[json[key]] ?? fallback;
    int swatch(List<int> swatches, String key, int fallback) {
      final value = json[key];
      return value is int && value >= 0 && value < swatches.length
          ? value
          : fallback;
    }

    return AvatarSpec(
      skinTone: swatch(AvatarPalette.skinTones, 'skinTone', defaults.skinTone),
      hair: part(AvatarHair.values, 'hair', defaults.hair),
      hairColor: swatch(
        AvatarPalette.hairColors,
        'hairColor',
        defaults.hairColor,
      ),
      face: part(AvatarFace.values, 'face', defaults.face),
      outfit: part(AvatarOutfit.values, 'outfit', defaults.outfit),
      outfitColor: swatch(
        AvatarPalette.outfitColors,
        'outfitColor',
        defaults.outfitColor,
      ),
      headgear: part(AvatarHeadgear.values, 'headgear', defaults.headgear),
      background: swatch(
        AvatarPalette.backgrounds,
        'background',
        defaults.background,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AvatarSpec &&
      other.skinTone == skinTone &&
      other.hair == hair &&
      other.hairColor == hairColor &&
      other.face == face &&
      other.outfit == outfit &&
      other.outfitColor == outfitColor &&
      other.headgear == headgear &&
      other.background == background;

  @override
  int get hashCode => Object.hash(
    skinTone,
    hair,
    hairColor,
    face,
    outfit,
    outfitColor,
    headgear,
    background,
  );
}
