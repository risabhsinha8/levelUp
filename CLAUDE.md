# levelUp — Skill Tree RPG Habit Tracker

## Tech Stack & Conventions
- **Framework:** Flutter (Dart 3+, null-safe, Material 3 customized for Tabletop RPG aesthetic)
- **State Management:** `flutter_riverpod` (Notifier / AsyncNotifier pattern)
- **Local Persistence:** Local SQLite via `sqflite`, behind the `RpgRepository` layer (see Storage & Onboarding Rules)
- **Commands to verify work:** Always run `flutter analyze` and `flutter test` after every phase. Fix all warnings/errors before finishing a turn.

## Storage & Onboarding Rules (Post-Phase 6 Update)
- **Persistence:** Use local SQLite via `sqflite` (`skill_tree_rpg.db`) instead of `SharedPreferences` JSON blobs.
- **No Seed Data:** `seed_data.dart` is deprecated and must be removed. The app starts with an empty SQLite database on first install.
- **Onboarding Gate:** If the `characters` table in SQLite is empty, the root app router must show `OnboardingScreen` ("Session Zero"). Once completed, it writes initial records in a single SQLite transaction and transitions to `HomeShell`.

## Post-Onboarding Polish & Upgrade Rules (Phases 10–12)
- **Rules & Scoring Codex:** Accessible anytime via a `?` / Book icon in the top AppBar. Visually explains the 1-Point-Per-Branch-Per-Day cap, 5/15/30/50/80 node thresholds, Leveling formula, and 4 Loot tiers.
- **Survival Mode (Minimum Viable Day):** Toggle on the Today screen that filters the daily view down to ONLY the 5 ★ Keystone Habits so users can still secure 100% of their daily Branch Active Days on low-energy days.
- **Tactile Node Forging:** When a branch's active days reach a threshold (5, 15, 30, 50, 80), the node enters a `readyToForge` state (pulsing gold). The user must physically long-press the node on the Skill Tree screen to "Forge/Claim" it, triggering rising haptics and a celebration overlay.
- **Day 15 Campfire:** Automatically detects habits with <25% completion in Days 1–15 and offers a 1-tap guided habit swap for Days 16–End while preserving Half 1 active days.

## Project Layout
- `lib/models/` — immutable models (`rpg_models.dart`) and the persisted `RpgState`
- `lib/domain/` — pure rule engine (`rpg_engine.dart`) and derived `CharacterSheet`
- `lib/data/` — `database_helper.dart` (opens `skill_tree_rpg.db`, Phase 7 schema; extra columns marked "extension" keep data existing screens need) and `rpg_sqlite_repository.dart` (`RpgSqliteRepository`: `loadFullState`, single-transaction `initializeFromOnboarding`, and one granular write per user action). Buff/debuff chips are JSON arrays in `buff_text`/`debuff_text`; the current season's oath is `characters.signature_data`; month reflections live in `seasons.mid_month_notes`.
- `lib/providers/` — Riverpod `rpgStoreProvider` (actions update memory, then make one granular repository write; on a failed write the state reloads from SQLite; state is `null` until onboarding), `isOnboardedProvider` (whether a character exists in SQLite), `rpgStateProvider` (non-null state for widgets under `HomeShell`), `characterSheetProvider`, overridable `clockProvider`
- `lib/screens/root_gate.dart` — root router (`LevelUpApp.home`): `StartupLoadingScreen` while SQLite loads, `OnboardingScreen` (Session Zero, `lib/screens/onboarding/`: 5-step wizard ending in a signed oath) when `isOnboardedProvider` is false, otherwise `HomeShell`
- `lib/screens/codex_guide_screen.dart` — Adventurer's Codex (`openCodex`), opened from the header's book icon and the Settings tile; its formula card previews the live `characterSheetProvider` numbers.
- Survival Mode: `survivalModeDateProvider` stores the date it was switched on and `survivalModeProvider` is true only on that date, so it resets at midnight (memory only, not SQLite). Today's Focus then folds away non-keystone habits.
- Mid-Month Campfire (`lib/widgets/campfire_sheet.dart`): `RpgEngine.findStrugglingHabits` (under 25% over Half 1 days elapsed through yesterday, counted from the first check-in on record) and `RpgEngine.isCampfireDay` (14th–16th, when Today shows the banner; the Monthly Matrix has a manual button). Pivots reuse `RpgStore.pivotHabit`; notes reuse `updateReflectionNotes` (`seasons.mid_month_notes`).
- Character Card (`lib/widgets/character_share_card.dart`): `showCharacterShareSheet` (header share icon and Season Tally button) previews `CharacterShareCard`, a fixed 360×450 (4:5) card in a `RepaintBoundary`, exported with `toImage(pixelRatio: 3)` as a 1080×1350 PNG. Sharing goes through the overridable `characterCardSharerProvider` (default: temp file via `path_provider`, then `SharePlus.instance.share(ShareParams(files: …))`; `Share.shareXFiles` is deprecated in share_plus 12). Tests override the sharer and tap share inside `tester.runAsync`. iOS needs `NSPhotoLibraryAddUsageDescription` for "Save Image".
- `lib/theme/`, `lib/widgets/`, `lib/screens/` — Tactile Dark Folio UI. Empty lists use the shared `EmptyPrompt` widget; every screen must render for a Day 1 character with no logs, quests or loot (see `test/empty_states_test.dart`).
- Widget tests must use `LevelUpApp(useGoogleFonts: false)` because tests can't fetch fonts. Use `pumpLevelUp`, `buildDemoState` and the granular `InMemoryRepository` fake from `test/support/fixtures.dart`; the Level 9 demo character is test-only data, never shipped.
- SQLite tests run on the VM through `sqflite_common_ffi` (`databaseFactoryFfi`, `inMemoryDatabasePath`).

## Core RPG Domain Rules
1. **5 Core Branches:** `mind`, `body`, `craft`, `bond`, `empire`. Each has a distinct color, `baseLevel` (carried over from past seasons), and lists of `buffs` and `debuffs` (shown as editable chips).
2. **No Streak Punishment:** Skill Tree nodes unlock via cumulative active days within a Season, NOT unbroken streaks. Seasons are calendar quarters (Jan 1, Apr 1, Jul 1, Oct 1; 90–92 days). A character created mid-quarter joins that quarter's season on its current day (onboarding on Nov 1 = day 32 of Oct 1–Dec 31). Season months 1–3 are the quarter's calendar months.
3. **The "1-Point-Per-Branch-Per-Day" Rule:** A branch can have multiple habits (e.g., Body = Exercise, Water, Sleep). Even if a user completes all 3 habits on the same calendar date, that branch only gains **+1 Branch Active Day** for that date.
4. **Skill Tree Thresholds:** Each branch has 5 cumulative nodes per season at **5, 15, 30, 50, and 80** Branch Active Days.
5. **Keystone Habits:** One habit per branch is marked with a Star (`isKeystone: true`). It is the daily non-negotiable.
6. **Leveling Math:**
   - `Branch Level = Base Carry-Over Level + Forged Nodes (0 to 5) + Completed Feats in that Branch`
   - `Overall Character Level = Sum of all 5 Branch Levels`
7. **Loot Tiers & Keys:**
   - **Common Key:** Earned for every 7 consecutive days of completing a Keystone Habit.
   - **Rare Key:** Earned for forging any single Skill Node.
   - **Epic Key:** Earned for forging all 5 nodes in a single branch (reaching 80 active days).
   - **Legendary Key:** Earned for forging all 25 nodes across all 5 branches in a season.

## Implementation Notes
- Count Branch Active Days as the number of **distinct calendar dates** with at least one completed habit in that branch, within the current season. Never count raw habit completions.
- Missing a day never removes progress or locks a node. The only streak-based mechanic is the Common Key, and it is a reward only.
- Exactly one active keystone per branch: setting a new keystone must unset the previous active one in that branch. Star changes go through `Habit.withKeystone(on, today)`, which records `keystonePeriods`; Common Keys count only days a habit was the keystone, so moving the star never takes back earned keys.
- A habit with check-ins can't change branch (it would move earned points); the store throws and the editor locks the selector.
- Deleting a habit with check-ins archives it (`isArchived`) instead of removing it, so its branch points and keystone streaks still count; an archived keystone is unstarred from today with its history kept. Habits with no check-ins are removed outright.
- Months split into Half 1 (days 1–15) and Half 2 (16–end). A mid-month pivot never deletes a habit: the old one becomes `firstHalf`, the replacement `secondHalf`, so earned branch points stay. Keystones can't be pivoted.
- Season rollover (`lib/domain/season_rollover.dart`): allowed only once the season's quarter has ended (`RpgEngine.isSeasonOver`; the header then prompts to level up). It bakes each branch's level into `baseLevel`, archives the season with its original end date and a `SeasonSummary`, stamps its quests with `seasonId`, and starts the next season the day after the old one ended, running to that quarter's end, so check-ins made before rolling over still count. A skipped quarter becomes its own season that can be completed straight away. Schema v3 moved existing current seasons onto their quarter (`DatabaseHelper.alignCurrentSeasonToQuarter`). Logs are never deleted; season date ranges scope them. Loot keys are per season.
- Node forging: active days *earn* nodes (`BranchStats.unlockedNodes`); only *forged* ones (`forgedNodes` = `branch_configs.forged_node_count` capped to earned, schema v4) add levels and Rare/Epic/Legendary keys. Earned-but-unforged nodes are `readyToForge`: they pulse on the Skill Tree, and holding one for 1.2s calls `RpgStore.forgeNode` and shows `showNodeForgedCelebration` (`lib/widgets/celebration_overlay.dart`). Rollover forges ready nodes automatically and resets the count to 0; the v4 upgrade (`DatabaseHelper.forgeEarnedNodes`) and JSON backups without the field treat already-earned nodes as forged, so no level drops. `HomeShell` mutes hidden tabs with `TickerMode` so the looping pulse never runs offscreen; widget tests showing a ready node must `pump` durations instead of `pumpAndSettle`.
- Loot chests: the Loot Table shows a `TreasureChestCard` per tier with unspent keys. "Roll Random Loot" uses `RpgStore.rollLoot` (random source `randomProvider`, overridable; `pumpLevelUp(random:)` in tests), "Pick Reward" uses `claimLoot`; both show `showLootCelebration`.
- Node unlocks, levels, and key awards are derived from stored data. Keep this logic in pure Dart functions (no Flutter/Riverpod imports) with unit tests.
- "Today" comes from `todayProvider` (rolls over at midnight and on app resume via `HomeShell`), never from reading `clockProvider` once in a widget. Use `clockProvider` only for timestamps of actions.
- SQLite must run on Android 10's SQLite 3.22: no `INSERT ... ON CONFLICT DO UPDATE` (UPSERT) or other 3.24+ syntax. Schema changes bump `DatabaseHelper.schemaVersion` with an `onUpgrade` step.
