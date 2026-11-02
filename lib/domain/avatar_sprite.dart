/// Composes an [AvatarSpec] into a 16×16 pixel-art bust. Pure Dart, so the
/// painter, the share card and tests all see the same pixels.
library;

import '../models/avatar.dart';

/// A layer: rows of 16 pixel keys, starting at [top]. `.` leaves the pixel
/// below unchanged.
class _Layer {
  const _Layer(this.top, this.rows);

  final int top;
  final List<String> rows;
}

abstract final class AvatarSprite {
  static const int size = 16;

  /// Outline drawn around every shape.
  static const int outline = 0xFF121316;

  static const _steel = 0xFFB8C0CC;
  static const _steelDark = 0xFF7D8696;
  static const _gold = 0xFFD4AF37;
  static const _gem = 0xFFE5484D;
  static const _eye = 0xFF1A1A1A;
  static const _white = 0xFFFFFFFF;
  static const _mouth = 0xFF8B3A3A;
  static const _blush = 0xFFF2A0A0;

  static const _base = _Layer(3, [
    '.....SSSSSS.....',
    '....SSSSSSSS....',
    '....SSSSSSSS....',
    '...SSSSSSSSSS...',
    '...SSSSSSSSSS...',
    '....SSSSSSSS....',
    '....sSSSSSSs....',
    '.....sSSSSs.....',
    '......ssss......',
    '...OOOOOOOOOO...',
    '..OOOOOOOOOOOO..',
    '.OOOOOOOOOOOOOO.',
    '.OOOOOOOOOOOOOO.',
  ]);

  static const _outfits = {
    AvatarOutfit.tunic: _Layer(12, [
      '.......ss.......',
      '.......oo.......',
      '................',
      '.ooooooYYoooooo.',
    ]),
    AvatarOutfit.robe: _Layer(12, [
      '.......YY.......',
      '.......YY.......',
      '.oo....YY....oo.',
      '.oo....YY....oo.',
    ]),
    AvatarOutfit.armor: _Layer(12, [
      '...AAAOOOOAAA...',
      '..AAAaOOOOaAAA..',
      '.AAAAaOOOOaAAAA.',
      '.AAAAaOYYOaAAAA.',
    ]),
    AvatarOutfit.cloak: _Layer(11, [
      '.....oo..oo.....',
      '...oooOssOooo...',
      '..oooOOYYOOooo..',
      '.ooooOOOOOOoooo.',
      '.ooooOOOOOOoooo.',
    ]),
  };

  static const _faces = {
    AvatarFace.bright: _Layer(6, [
      '.....WE..WE.....',
      '.....EE..EE.....',
      '................',
      '.......MM.......',
    ]),
    AvatarFace.cheerful: _Layer(6, [
      '.....WE..WE.....',
      '.....EE..EE.....',
      '....P.M..M.P....',
      '.......MM.......',
    ]),
    AvatarFace.calm: _Layer(7, [
      '.....EE..EE.....',
      '................',
      '.......MM.......',
    ]),
    AvatarFace.fierce: _Layer(6, [
      '......E..E......',
      '.....EE..EE.....',
      '................',
      '......MMMM......',
    ]),
    AvatarFace.spectacled: _Layer(6, [
      '....YYYYYYYY....',
      '....YEY..YEY....',
      '....YYY..YYY....',
      '.......MM.......',
    ]),
    AvatarFace.sleepy: _Layer(6, [
      '.....ss..ss.....',
      '.....EE..EE.....',
      '................',
      '........M.......',
    ]),
  };

  static const _hair = {
    AvatarHair.short: _Layer(2, [
      '.....HHHHHH.....',
      '....HHHHHHHH....',
      '...HHHHHHHHHH...',
      '...HH......HH...',
      '...H........H...',
    ]),
    AvatarHair.long: _Layer(2, [
      '.....HHHHHH.....',
      '....HHHHHHHH....',
      '...HHHHHHHHHH...',
      '...HHH....HHH...',
      '..HH........HH..',
      '..HH........HH..',
      '..HH........HH..',
      '..Hh........hH..',
      '..hh........hh..',
      '..hh........hh..',
      '..hh........hh..',
    ]),
    AvatarHair.spiky: _Layer(0, [
      '....H..H..H.....',
      '....HH.HH.HH....',
      '...HHHHHHHHHH...',
      '...HHHHHHHHHH...',
      '...HHHHHHHHHH...',
      '...H.HH..HH.H...',
      '...H........H...',
    ]),
    AvatarHair.bun: _Layer(0, [
      '......HHHH......',
      '......HhhH......',
      '.....HHHHHH.....',
      '....HHHHHHHH....',
      '...HHHHHHHHHH...',
      '...HH......HH...',
      '...H........H...',
    ]),
    AvatarHair.mohawk: _Layer(0, [
      '.......HH.......',
      '.......HH.......',
      '.......HH.......',
      '......HHHH......',
      '.......hh.......',
    ]),
    AvatarHair.bald: _Layer(0, []),
  };

  static const _headgear = {
    AvatarHeadgear.none: _Layer(0, []),
    AvatarHeadgear.hood: _Layer(1, [
      '.....OOOOOO.....',
      '....OOOOOOOO....',
      '...OOOOOOOOOO...',
      '..OOOooooooOOO..',
      '..OO........OO..',
      '..OO........OO..',
      '..OO........OO..',
      '..Oo........oO..',
      '..oo........oo..',
      '...oo......oo...',
    ]),
    AvatarHeadgear.wizardHat: _Layer(0, [
      '........O.......',
      '.......OOo......',
      '......OOOOo.....',
      '.....YYYYYY.....',
      '..OOOOOOOOOOOO..',
    ]),
    AvatarHeadgear.helmet: _Layer(0, [
      '.......OO.......',
      '......OOO.......',
      '.....AAAAAA.....',
      '....AAAAAAAA....',
      '...AAAAAAAAAA...',
      '...AaaaaaaaaA...',
      '...A...aa...A...',
      '...A........A...',
      '...a........a...',
    ]),
    AvatarHeadgear.crown: _Layer(1, [
      '....Y..YY..Y....',
      '....YY.YY.YY....',
      '....YYYYYYYY....',
      '....YRYYYYRY....',
    ]),
    AvatarHeadgear.headband: _Layer(4, [
      '...OOOOOOOOOO...',
      '............Oo..',
      '.............o..',
    ]),
  };

  /// [color] darkened for shading.
  static int shade(int color) {
    int channel(int shift) => (((color >> shift) & 0xFF) * 0.72).round();
    return 0xFF000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
  }

  /// The pixels of [spec], row by row (`size * size` ARGB colors; null is
  /// transparent). Every shape gets a dark outline.
  static List<int?> compose(AvatarSpec spec) {
    final skin = AvatarPalette.skinTones[spec.skinTone];
    final hair = AvatarPalette.hairColors[spec.hairColor];
    final cloth = AvatarPalette.outfitColors[spec.outfitColor];
    final colors = {
      'S': skin,
      's': shade(skin),
      'H': hair,
      'h': shade(hair),
      'O': cloth,
      'o': shade(cloth),
      'A': _steel,
      'a': _steelDark,
      'Y': _gold,
      'R': _gem,
      'E': _eye,
      'W': _white,
      'M': _mouth,
      'P': _blush,
      'K': outline,
    };

    final pixels = List<int?>.filled(size * size, null);
    for (final layer in [
      _base,
      _outfits[spec.outfit]!,
      _faces[spec.face]!,
      _hair[spec.hair]!,
      _headgear[spec.headgear]!,
    ]) {
      for (final (i, row) in layer.rows.indexed) {
        assert(row.length == size, 'Avatar row "$row" is not $size wide');
        for (var x = 0; x < size; x++) {
          final key = row[x];
          if (key != '.') pixels[(layer.top + i) * size + x] = colors[key];
        }
      }
    }

    // Outline: every empty pixel touching a filled one.
    final outlined = [...pixels];
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (pixels[y * size + x] != null) continue;
        bool filled(int dx, int dy) {
          final nx = x + dx;
          final ny = y + dy;
          return nx >= 0 &&
              nx < size &&
              ny >= 0 &&
              ny < size &&
              pixels[ny * size + nx] != null;
        }

        if (filled(1, 0) || filled(-1, 0) || filled(0, 1) || filled(0, -1)) {
          outlined[y * size + x] = outline;
        }
      }
    }
    return outlined;
  }
}
