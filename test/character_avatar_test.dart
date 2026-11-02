import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/data/database_helper.dart';
import 'package:level_up/data/rpg_sqlite_repository.dart';
import 'package:level_up/domain/avatar_sprite.dart';
import 'package:level_up/domain/character_stats.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/screens/character_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixtures.dart';

/// A Saturday, 18 days into the demo season.
final today = DateTime(2026, 10, 24, 9);

const knight = AvatarSpec(
  skinTone: 3,
  hair: AvatarHair.long,
  hairColor: 5,
  face: AvatarFace.fierce,
  outfit: AvatarOutfit.armor,
  outfitColor: 2,
  headgear: AvatarHeadgear.helmet,
  background: 4,
);

void main() {
  group('avatar sprite', () {
    test('every combination of parts composes a 16×16 bust', () {
      for (final hair in AvatarHair.values) {
        for (final face in AvatarFace.values) {
          for (final outfit in AvatarOutfit.values) {
            for (final headgear in AvatarHeadgear.values) {
              final pixels = AvatarSprite.compose(
                AvatarSpec(
                  hair: hair,
                  face: face,
                  outfit: outfit,
                  headgear: headgear,
                ),
              );
              expect(pixels, hasLength(AvatarSprite.size * AvatarSprite.size));
              expect(pixels.whereType<int>(), isNotEmpty);
            }
          }
        }
      }
    });

    test('colors come from the palette, with an outline around shapes', () {
      final pixels = AvatarSprite.compose(knight);
      expect(pixels, contains(AvatarPalette.skinTones[3]));
      expect(pixels, contains(AvatarPalette.hairColors[5]));
      expect(pixels, contains(AvatarPalette.outfitColors[2]));
      expect(pixels, contains(AvatarSprite.outline));
      // Each part changes the picture.
      expect(
        AvatarSprite.compose(knight.copyWith(headgear: AvatarHeadgear.crown)),
        isNot(pixels),
      );
      expect(
        AvatarSprite.compose(knight.copyWith(face: AvatarFace.sleepy)),
        isNot(pixels),
      );
    });
  });

  group('AvatarSpec', () {
    test('round-trips JSON; unknown parts fall back to defaults', () {
      expect(AvatarSpec.fromJson(knight.toJson()), knight);
      expect(
        AvatarSpec.fromJson({'hair': 'dreadlocks', 'skinTone': 99}),
        const AvatarSpec(),
      );
    });

    test('random rolls are reproducible from the random source', () {
      expect(
        AvatarSpec.random(math.Random(3)),
        AvatarSpec.random(math.Random(3)),
      );
      final rolls = {
        for (var seed = 0; seed < 20; seed++)
          AvatarSpec.random(math.Random(seed)),
      };
      expect(rolls.length, greaterThan(1));
    });

    test('characters without one get a stable default from their name', () {
      const character = Character(
        name: 'Ari',
        classTitle: 'Novice',
        currentSeasonId: 's',
      );
      expect(character.avatarOrDefault, AvatarSpec.seeded('Ari'));
      expect(Character.fromJson(character.toJson()).avatar, isNull);
      final picked = character.copyWith(avatar: knight);
      expect(Character.fromJson(picked.toJson()), picked);
    });
  });

  group('CharacterStats', () {
    test('demo character: lifetime numbers and this season\'s points', () {
      final stats = CharacterStats.fromState(buildDemoState(today), today);
      expect(stats.daysLogged, 17);
      expect(stats.bestRun, 17); // Oct 7–23 without a gap.
      expect(stats.totalCheckIns, greaterThan(stats.daysLogged));
      expect(
        stats.checkInsByWeekday.fold(0, (a, b) => a + b),
        stats.totalCheckIns,
      );
      // 17 + 17 + 11 + 6 + 4 active days, out of 5 pillars × 18 days.
      expect(stats.seasonPoints, 55);
      expect(stats.seasonPointsPossible, 90);
      expect(stats.lifetimeActiveDays[BranchType.craft], 11);
      expect(stats.favoritePillar, BranchType.mind); // Ties with Body.
      expect(stats.seasonsCompleted, 0);
    });

    test('the heatmap ends with today\'s week', () {
      final stats = CharacterStats.fromState(buildDemoState(today), today);
      expect(stats.recentWeeks, hasLength(CharacterStats.recentWeekCount * 7));
      expect(stats.recentWeeks.last, isNull); // Sunday hasn't come yet.
      expect(stats.recentWeeks[stats.recentWeeks.length - 2], 0); // Today.
      expect(stats.recentWeeks[stats.recentWeeks.length - 3], isPositive);
    });

    test('a fresh character has nothing yet', () {
      final stats = CharacterStats.fromState(buildFreshState(today), today);
      expect(stats.daysLogged, 0);
      expect(stats.bestRun, 0);
      expect(stats.seasonPointRate, isNull);
      expect(stats.favoritePillar, isNull);
      expect(stats.bestWeekday, isNull);
    });
  });

  group('SQLite', () {
    setUpAll(sqfliteFfiInit);

    test('the avatar is saved with the character', () async {
      final repo = RpgSqliteRepository(
        DatabaseHelper(
          factory: databaseFactoryFfi,
          path: DatabaseHelper.inMemoryPath,
        ),
      );
      addTearDown(repo.close);
      final state = buildFreshState(today);
      await repo.initializeFromOnboarding(
        state.copyWith(character: state.character.copyWith(avatar: knight)),
      );
      expect((await repo.loadFullState())!.character.avatar, knight);

      final changed = knight.copyWith(headgear: AvatarHeadgear.crown);
      await repo.updateCharacter(state.character.copyWith(avatar: changed));
      expect((await repo.loadFullState())!.character.avatar, changed);
    });

    test('upgrading a v5 database adds an empty avatar', () async {
      final dir = await Directory.systemTemp.createTemp('level_up_v5');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, DatabaseHelper.fileName);

      final setup = DatabaseHelper(factory: databaseFactoryFfi, path: path);
      await RpgSqliteRepository(setup).replaceAllData(buildDemoState(today));
      final db = await setup.database;
      await db.execute(
        'CREATE TABLE c5 AS SELECT id, name, class_title, signature_data, '
        'current_season_id, signature_text FROM characters',
      );
      await db.execute('DROP TABLE characters');
      await db.execute('ALTER TABLE c5 RENAME TO characters');
      await db.setVersion(5);
      await setup.close();

      final repo = RpgSqliteRepository(
        DatabaseHelper(factory: databaseFactoryFfi, path: path),
      );
      addTearDown(repo.close);
      final loaded = (await repo.loadFullState())!;
      expect(loaded.character.avatar, isNull);
      expect(loaded.character.name, buildDemoState(today).character.name);
    });
  });

  group('screens', () {
    testWidgets('the header avatar opens the Character page with stats', (
      tester,
    ) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3000),
      );
      expect(find.bySemanticsLabel('Level 9'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('header-avatar')));
      await tester.pumpAndSettle();

      expect(find.byType(CharacterScreen), findsOneWidget);
      expect(find.text('55/90'), findsOneWidget);
      expect(find.text('Branch points · 61%'), findsOneWidget);
      expect(find.text('17'), findsWidgets); // Days logged, best run.
      expect(find.text('Favorite pillar: Mind'), findsOneWidget);
      expect(find.textContaining('Best day: '), findsOneWidget);
      expect(find.text('Last 12 Weeks'), findsOneWidget);
    });

    testWidgets('tapping a stat or ⓘ explains it with live numbers', (
      tester,
    ) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3000),
      );
      await tester.tap(find.byKey(const ValueKey('header-avatar')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Branch points · 61%'));
      await tester.pumpAndSettle();
      expect(find.textContaining('You have 55 of 90 possible'), findsOneWidget);
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('About Level & Season'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Level 9 is the sum of'), findsOneWidget);
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('About Last 12 Weeks'));
      await tester.pumpAndSettle();
      expect(find.textContaining('One square per day'), findsOneWidget);
    });

    testWidgets('Randomize and the part cyclers change the saved avatar', (
      tester,
    ) async {
      final repo = await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(800, 3000),
        random: math.Random(11),
      );
      await tester.tap(find.byKey(const ValueKey('header-avatar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-avatar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('avatar-randomize')));
      await tester.pumpAndSettle();
      final rolled = AvatarSpec.random(math.Random(11));
      await tester.tap(find.byKey(const ValueKey('avatar-next-headgear')));
      await tester.pumpAndSettle();
      final expected = rolled.copyWith(
        headgear: AvatarHeadgear
            .values[(rolled.headgear.index + 1) % AvatarHeadgear.values.length],
      );
      expect(find.text(expected.headgear.label), findsOneWidget);

      await tester.tap(find.text('Save Avatar'));
      await tester.pumpAndSettle();
      expect(repo.saved!.character.avatar, expected);
    });

    testWidgets('a played character page fits a 320pt-wide phone', (
      tester,
    ) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildDemoState(today),
        size: const Size(320, 3000),
      );
      await tester.tap(find.byKey(const ValueKey('header-avatar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Favorite pillar: Mind'), findsOneWidget);
    });

    testWidgets('pillars with 100+ active days fit a 320pt-wide phone', (
      tester,
    ) async {
      final demo = buildDemoState(today);
      // Every habit checked off for 150 days, across past seasons too.
      final state = demo.copyWith(
        logs: [
          for (var day = 1; day <= 150; day++)
            DailyLog(
              dateString: toDateString(today.subtract(Duration(days: day))),
              completedHabitIds: [for (final h in demo.habits) h.id],
            ),
        ],
      );
      await pumpLevelUp(
        tester,
        now: today,
        state: state,
        size: const Size(320, 3000),
      );
      await tester.tap(find.byKey(const ValueKey('header-avatar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('150 days'), findsWidgets); // Bars and the scale.
    });

    testWidgets('a Day 1 character page fits a 320pt-wide phone', (
      tester,
    ) async {
      await pumpLevelUp(
        tester,
        now: today,
        state: buildFreshState(today),
        size: const Size(320, 2400),
      );
      await tester.tap(find.byKey(const ValueKey('header-avatar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('No check-ins yet'), findsOneWidget);
      expect(find.text('0/0'), findsOneWidget);
    });
  });
}
