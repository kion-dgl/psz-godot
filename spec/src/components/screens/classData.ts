export interface ClassInfo {
  id: string;
  name: string;
  race: 'Human' | 'Newman' | 'Cast';
  gender: 'Male' | 'Female';
  type: 'Hunter' | 'Ranger' | 'Force';
  /** Short playstyle descriptor shown in character-select UIs in place of
   * the raw stat numbers — e.g. "High Defense and Attack". Keeps the focus
   * on the character's role in the world rather than the RPG numbers. */
  tagline: string;
  bonuses: string[];
  stats: {
    hp: number;
    pp: number;
    attack: number;
    defense: number;
    accuracy: number;
    evasion: number;
    technique: number;
  };
}

export const ALL_CLASSES: ClassInfo[] = [
  {
    id: 'humar', name: 'HUmar', race: 'Human', gender: 'Male', type: 'Hunter',
    tagline: 'Balanced melee all-rounder',
    bonuses: [],
    stats: { hp: 82, pp: 67, attack: 56, defense: 10, accuracy: 110, evasion: 13, technique: 33 },
  },
  {
    id: 'humarl', name: 'HUmarl', race: 'Human', gender: 'Female', type: 'Hunter',
    tagline: 'Quick-strike duelist',
    bonuses: [],
    stats: { hp: 80, pp: 70, attack: 54, defense: 10, accuracy: 116, evasion: 13, technique: 35 },
  },
  {
    id: 'hunewm', name: 'HUnewm', race: 'Newman', gender: 'Male', type: 'Hunter',
    tagline: 'Spell-wielding hunter',
    bonuses: ['Natural PP recovery'],
    stats: { hp: 77, pp: 75, attack: 50, defense: 9, accuracy: 121, evasion: 21, technique: 43 },
  },
  {
    id: 'hunewearl', name: 'HUnewearl', race: 'Newman', gender: 'Female', type: 'Hunter',
    tagline: 'Mystic close-quarters fighter',
    bonuses: ['Natural PP recovery'],
    stats: { hp: 75, pp: 79, attack: 48, defense: 9, accuracy: 126, evasion: 21, technique: 45 },
  },
  {
    id: 'hucast', name: 'HUcast', race: 'Cast', gender: 'Male', type: 'Hunter',
    tagline: 'Heavy-armor brawler',
    bonuses: ['Natural HP recovery'],
    stats: { hp: 98, pp: 52, attack: 60, defense: 12, accuracy: 132, evasion: 7, technique: 25 },
  },
  {
    id: 'hucaseal', name: 'HUcaseal', race: 'Cast', gender: 'Female', type: 'Hunter',
    tagline: 'Precise android striker',
    bonuses: ['Natural HP recovery'],
    stats: { hp: 95, pp: 59, attack: 58, defense: 11, accuracy: 138, evasion: 8, technique: 28 },
  },
  {
    id: 'ramar', name: 'RAmar', race: 'Human', gender: 'Male', type: 'Ranger',
    tagline: 'Steady marksman',
    bonuses: [],
    stats: { hp: 72, pp: 73, attack: 41, defense: 8, accuracy: 151, evasion: 14, technique: 31 },
  },
  {
    id: 'ramarl', name: 'RAmarl', race: 'Human', gender: 'Female', type: 'Ranger',
    tagline: 'Quick-draw sharpshooter',
    bonuses: [],
    stats: { hp: 71, pp: 76, attack: 39, defense: 7, accuracy: 158, evasion: 14, technique: 33 },
  },
  {
    id: 'racast', name: 'RAcast', race: 'Cast', gender: 'Male', type: 'Ranger',
    tagline: 'Armored long-range gunner',
    bonuses: ['Natural HP recovery'],
    stats: { hp: 86, pp: 62, attack: 47, defense: 9, accuracy: 165, evasion: 9, technique: 27 },
  },
  {
    id: 'racaseal', name: 'RAcaseal', race: 'Cast', gender: 'Female', type: 'Ranger',
    tagline: 'Surgical sharpshooter',
    bonuses: ['Natural HP recovery'],
    stats: { hp: 83, pp: 66, attack: 44, defense: 8, accuracy: 171, evasion: 9, technique: 29 },
  },
  {
    id: 'fomar', name: 'FOmar', race: 'Human', gender: 'Male', type: 'Force',
    tagline: 'Offensive elemental caster',
    bonuses: ['75% tech damage reduction', 'Foie/Barta/Zonde boost'],
    stats: { hp: 73, pp: 102, attack: 37, defense: 7, accuracy: 105, evasion: 14, technique: 49 },
  },
  {
    id: 'fomarl', name: 'FOmarl', race: 'Human', gender: 'Female', type: 'Force',
    tagline: 'Healer and party support',
    bonuses: ['75% tech damage reduction', 'Grants/Resta boost'],
    stats: { hp: 70, pp: 106, attack: 35, defense: 7, accuracy: 109, evasion: 14, technique: 50 },
  },
  {
    id: 'fonewm', name: 'FOnewm', race: 'Newman', gender: 'Male', type: 'Force',
    tagline: 'Master of every technique',
    bonuses: ['75% tech damage reduction', 'All tech boost', 'Natural PP recovery'],
    stats: { hp: 68, pp: 97, attack: 33, defense: 6, accuracy: 93, evasion: 14, technique: 56 },
  },
  {
    id: 'fonewearl', name: 'FOnewearl', race: 'Newman', gender: 'Female', type: 'Force',
    tagline: 'Specialist dark caster',
    bonuses: ['75% tech damage reduction', 'Megid/Resta boost', 'Natural PP recovery'],
    stats: { hp: 65, pp: 102, attack: 32, defense: 6, accuracy: 97, evasion: 15, technique: 57 },
  },
];

export function getClassesByRace(race: string): ClassInfo[] {
  return ALL_CLASSES.filter((c) => c.race === race);
}

export function getClassById(id: string): ClassInfo | undefined {
  return ALL_CLASSES.find((c) => c.id === id);
}
