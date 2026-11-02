import '../../models/rpg_models.dart';

/// Inspiration chips for the class title.
const classSuggestions = [
  'Recovering Couch Potato',
  'Caffeine Paladin',
  'Code Ranger',
  'Shadow Monk',
];

/// One-line description of each branch for the overview card.
const branchDescriptions = {
  BranchType.mind: 'Learning, focus and reflection',
  BranchType.body: 'Movement, sleep and fuel',
  BranchType.craft: 'Skills and creative practice',
  BranchType.bond: 'Family, friends and love',
  BranchType.empire: 'Work, money and side projects',
  BranchType.spirit: 'Faith, gratitude and stillness',
  BranchType.wander: 'Adventure, play and new places',
};

/// Quick-fill keystones per branch: (title, target criteria).
const keystoneSuggestions = {
  BranchType.mind: [
    ('Read', '10 pages'),
    ('Meditate', '5 min'),
    ('Journal', '1 page'),
  ],
  BranchType.body: [
    ('Drink water', '13 cups daily'),
    ('Walk', '8,000 steps'),
    ('Sleep', '8 hrs'),
  ],
  BranchType.craft: [
    ('Sketch', '1 rough thumbnail'),
    ('Practice guitar', '15 min'),
    ('Write', '200 words'),
  ],
  BranchType.bond: [
    ('Call someone', '1 real conversation'),
    ('Family dinner', 'Phones away'),
    ('Send a kind text', '1 person'),
  ],
  BranchType.empire: [
    ('Side project', '30 focused min'),
    ('Learn a skill', '1 lesson'),
    ('Budget check', '5 min'),
  ],
  BranchType.spirit: [
    ('Gratitude list', '3 things'),
    ('Pray or reflect', '5 min'),
    ('Sit in silence', '2 min'),
  ],
  BranchType.wander: [
    ('Go outside', '20 min'),
    ('Try something new', '1 small thing'),
    ('Play', 'A game, sport or jam'),
  ],
};

const buffSuggestions = [
  'Lay out gym clothes at night',
  'Book on the pillow',
  'Water bottle on the desk',
];

const debuffSuggestions = [
  'Phone in bed after 11 PM',
  'Doomscrolling at breakfast',
  'Snoozing the alarm',
];

/// Quick-fill rewards per loot tier.
const lootSuggestions = {
  LootTier.common: ['Ice cream night', 'Fancy coffee', 'Movie night'],
  LootTier.rare: ['Buy a new book', 'Binge TV night', 'New video game'],
  LootTier.epic: ['Nice dinner out', 'Concert tickets', 'Spa day'],
  LootTier.legendary: ['Big gear upgrade', 'Weekend trip away', 'New guitar'],
};
