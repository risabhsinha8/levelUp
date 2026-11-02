import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_up/main.dart';
import 'package:level_up/models/rpg_models.dart';
import 'package:level_up/models/rpg_state.dart';
import 'package:level_up/providers/rpg_store_provider.dart';
import 'package:level_up/widgets/character_share_card.dart';

import 'support/fixtures.dart';

final today = DateTime(2026, 10, 24, 9);

Finder semantics(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// Pumps the app with a fake share sheet that records what it was given.
Future<List<Uint8List>> pumpWithSharer(
  WidgetTester tester, {
  RpgState? state,
  Size size = const Size(800, 2600),
  bool failing = false,
}) async {
  final shared = <Uint8List>[];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => today),
        rpgRepositoryProvider.overrideWithValue(
          InMemoryRepository(state ?? buildDemoState(today)),
        ),
        reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler()),
        characterCardSharerProvider.overrideWithValue((png, {origin}) async {
          if (failing) throw StateError('share sheet unavailable');
          shared.add(png);
        }),
      ],
      child: const LevelUpApp(useGoogleFonts: false),
    ),
  );
  await tester.pumpAndSettle();
  return shared;
}

Future<void> openFromHeader(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Share Character Card'));
  await tester.pumpAndSettle();
}

/// Taps share for real: rasterizing the card needs real async time.
Future<void> tapShare(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Share / Save Character Card'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the header opens the card with the live character', (
    tester,
  ) async {
    await pumpWithSharer(tester);
    await openFromHeader(tester);

    final card = find.byType(CharacterShareCard);
    expect(card, findsOneWidget);
    Finder onCard(String text) =>
        find.descendant(of: card, matching: find.text(text));
    expect(onCard('Rowan'), findsOneWidget);
    expect(onCard('Recovering Couch Potato'), findsOneWidget);
    expect(onCard('Season 1 • Day 18/86'), findsOneWidget);
    expect(semantics('Overall level 9'), findsOneWidget);
    expect(
      semantics(
        'Mind level 3, Body level 3, Craft level 2, Bond level 1, '
        'Empire level 0',
      ),
      findsOneWidget,
    );
    // Stats footer: 17 days logged, 6 nodes forged, 1 quest done.
    expect(onCard('17'), findsOneWidget);
    expect(onCard('6 / 25'), findsOneWidget);
    expect(onCard('1'), findsOneWidget);
    // No drawn oath yet, so the typed signature is shown.
    expect(onCard('“Small steps, every season.”'), findsOneWidget);
    expect(tester.getSize(card), CharacterShareCard.size);
  });

  testWidgets('a sealed oath shows the drawn signature', (tester) async {
    final demo = buildDemoState(today);
    final signed = demo.copyWith(
      seasons: [
        demo.currentSeason.copyWith(
          oath: SeasonOath(
            strokes: [
              [0.1, 0.5, 0.4, 0.3, 0.8, 0.6],
            ],
            signedAtDate: '2026-10-10',
          ),
        ),
      ],
    );
    await pumpWithSharer(tester, state: signed);
    await openFromHeader(tester);
    expect(semantics('Seasonal oath signature'), findsOneWidget);
    expect(find.text('“Small steps, every season.”'), findsNothing);
  });

  testWidgets('Season Tally opens the card too', (tester) async {
    await pumpWithSharer(tester, size: const Size(800, 3000));
    await tester.tap(find.text('Season Tally').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share Character Card'));
    await tester.pumpAndSettle();
    expect(find.byType(CharacterShareCard), findsOneWidget);
  });

  testWidgets('sharing exports a 1080×1350 PNG at 3× pixel ratio', (
    tester,
  ) async {
    final shared = await pumpWithSharer(tester);
    await openFromHeader(tester);
    await tapShare(tester);

    expect(shared, hasLength(1));
    final png = shared.single;
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    // IHDR: big-endian width and height at bytes 16–23.
    final header = ByteData.sublistView(png, 16, 24);
    expect(header.getUint32(0), 1080);
    expect(header.getUint32(4), 1350);
  });

  testWidgets('a failed share explains itself', (tester) async {
    await pumpWithSharer(tester, failing: true);
    await openFromHeader(tester);
    await tapShare(tester);
    expect(find.text("Couldn't share the card. Try again."), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the preview fits a 320pt-wide phone', (tester) async {
    await pumpWithSharer(tester, size: const Size(320, 900));
    await openFromHeader(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Share / Save Character Card'), findsOneWidget);
  });

  test('the radar scale rounds up to a multiple of 5', () {
    AttributeRadarPainter radar(List<int> levels) => AttributeRadarPainter(
      levels: {for (final (i, b) in BranchType.defaults.indexed) b: levels[i]},
      labelStyle: const TextStyle(),
    );
    expect(radar([0, 0, 0, 0, 0]).scaleMax, 5);
    expect(radar([3, 3, 2, 1, 0]).scaleMax, 5);
    expect(radar([7, 3, 2, 1, 0]).scaleMax, 10);
    expect(radar([10, 0, 0, 0, 11]).scaleMax, 15);
  });
}
