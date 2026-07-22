// Per-shop content + NPC binding for the 3D shop menus.
//
// The NPC model / idle-clip mappings are the real Godot city NPCs (np_0XX rig,
// idles from npc_idles.glb). The list content mirrors each shop's ACTUAL UX as
// implemented in scripts/2d/shops/* — the right tabs, the right currency
// (photon collector spends Photon Drops, not meseta; guild counter spends
// nothing), and representative rows in the real row format. It's sample data
// for a visual mock, not a live inventory.
import { assetUrl } from '../utils/assets';

export type Currency = 'meseta' | 'photon' | 'none';
export type AreaId = 'market' | 'counter' | 'underground';

// The real Godot city stage each shop lives in (identity-transform GLBs, same
// paths the .tscn scenes instance). NPCs are placed at their in-game world
// coordinates inside these so the fixed shop camera frames the actual location.
export interface StageDef {
  models: string[];   // visual GLB(s), drawn at identity
  floorY: number;     // ground height in this area (player/NPC feet sit here)
}

export const STAGES: Record<AreaId, StageDef> = {
  market: {
    models: [
      assetUrl('assets/stages/city_e/market/dairon2.glb'),
      assetUrl('assets/stages/city_e/market/wall_extension.glb'),
    ],
    floorY: 0,
  },
  counter: {
    models: [assetUrl('assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb')],
    floorY: -10.67,
  },
  underground: {
    models: [assetUrl('assets/stages/city_e/s00e_sa4/lndmd/s00e_sa4_m.glb')],
    floorY: 0,
  },
};

// The player character that walks up to the shop (HUmar, pc_000), plus its idle
// clip. Stands in front of the NPC during the "talk" shot; can be ghosted or
// hidden when it obstructs the shopkeeper.
export const PLAYER = {
  model: assetUrl('assets/player/pc_000/pc_000_000.glb'),
  tex: assetUrl('assets/player/pc_000/textures/pc_000_000.png'),
  animGlb: assetUrl('assets/player/animations/saber_m.glb'),
  idleClip: 'pmsa_wait',
};

export interface ShopItem {
  name: string;
  right?: string;          // right-aligned price / qty / grind
  sub?: string;            // small secondary line under the name
  rarity?: 'rare' | 'common';
  marker?: 'E' | 'x';      // [E] equipped, ✕ class-cannot-use
  detail: {
    subtitle?: string;
    stats?: [string, string][];
    desc?: string;
    action?: string;       // label for the confirm button
  };
}

export interface ShopTab { label: string; items: ShopItem[] }

export interface ShopDef {
  id: string;
  label: string;           // nav / picker label
  title: string;           // in-game panel title
  blurb: string;           // one-line greeting shown in some variations
  area: AreaId;            // which city stage the shop lives in
  npc: {
    model: string; tex: string; idle?: string;
    pos: [number, number, number];  // in-game world position
    rot: number;                    // in-game model.rotation.y (radians)
  };
  accent: number;          // hex tint for the 3D stage + UI accents
  currency: Currency;
  meseta: number;
  photons?: number;
  hint: string;
  tabs: ShopTab[];         // single-list shops use one tab with label ''
}

function npc(id: string, idle: string | undefined, pos: [number, number, number], rot: number) {
  const base = `assets/npcs/${id}/${id}`;
  return { model: assetUrl(`${base}.glb`), tex: assetUrl(`${base}.png`), idle, pos, rot };
}

export const SHOPS: ShopDef[] = [
  {
    id: 'photon',
    area: 'underground',
    label: 'Photon Collector',
    title: 'Photon Collector',
    blurb: 'Bring me Photon Drops — I trade them for things meseta can’t buy.',
    npc: npc('np_018_00_0', 'pso_f_ro_stand', [-6.32, 0, -5.35], 0),
    accent: 0x9a56d6,
    currency: 'photon',
    meseta: 12450,
    photons: 27,
    hint: 'Spend Photon Drops · A Exchange · B Back',
    tabs: [{
      label: '',
      items: [
        { name: 'Monogrinder', right: '1 PD', sub: 'Grinder', detail: { subtitle: 'Grinder', stats: [['Cost', '1 Photon Drop'], ['You have', 'x4']], desc: 'A basic grinding material for low-rarity weapons.', action: 'Exchange (1 PD)' } },
        { name: 'Digrinder', right: '3 PD', sub: 'Grinder', detail: { subtitle: 'Grinder', stats: [['Cost', '3 Photon Drops'], ['You have', 'x1']], desc: 'Grinds mid-rarity weapons.', action: 'Exchange (3 PD)' } },
        { name: 'Trigrinder', right: '6 PD', sub: 'Grinder', detail: { subtitle: 'Grinder', stats: [['Cost', '6 Photon Drops'], ['You have', 'x0']], desc: 'Grinds high-rarity weapons.', action: 'Exchange (6 PD)' } },
        { name: 'Im Photon', right: '5 PD', sub: 'Crystal', rarity: 'rare', detail: { subtitle: 'Photon Crystal', stats: [['Element', 'Fire'], ['Cost', '5 Photon Drops']], desc: 'A synthesis crystal that imbues a Fire element when crafting.', action: 'Exchange (5 PD)' } },
        { name: 'El Photon', right: '5 PD', sub: 'Crystal', rarity: 'rare', detail: { subtitle: 'Photon Crystal', stats: [['Element', 'Ice'], ['Cost', '5 Photon Drops']], desc: 'Imbues an Ice element when crafting.', action: 'Exchange (5 PD)' } },
        { name: 'Grinder Base C', right: '10 PD', sub: 'Material', detail: { subtitle: 'Material', stats: [['Cost', '10 Photon Drops']], desc: 'Refined into higher grinders at the synth bench.', action: 'Exchange (10 PD)' } },
        { name: 'Mag POW +50', right: '15 PD', sub: 'Mag Boost', detail: { subtitle: 'Mag Feed', stats: [['Effect', 'POW +50'], ['Cost', '15 Photon Drops']], desc: 'Feeds your Mag 50 points of raw power instantly.', action: 'Exchange (15 PD)' } },
      ],
    }],
  },
  {
    id: 'synth',
    area: 'underground',
    label: 'Synthesis Shop',
    title: 'Synthesis Shop',
    blurb: 'Bring the boards and materials — I’ll forge you a photon weapon.',
    npc: npc('np_017_00_0', 'pso_ro_stand', [8.38, 0, -4.81], 0),
    accent: 0x25b39a,
    currency: 'meseta',
    meseta: 12450,
    photons: 27,
    hint: 'A Choose photon · A Craft · B Back',
    tabs: [
      {
        label: 'Craft',
        items: [
          { name: 'Saber', right: '400 M', sub: '★ · Saber', detail: { subtitle: '★ · Saber-type', stats: [['Monomate', '2 / 2'], ['Grinder Base C', '1 / 1'], ['Cost', '400 M'], ['+ Photon', '×1']], desc: 'Craft a Saber. A photon crystal sets its element and special.', action: 'Craft (400 M)' } },
          { name: 'Buster', right: '1,200 M', sub: '★★ · Sword', detail: { subtitle: '★★ · Sword-type', stats: [['Photon Steel', '3 / 2'], ['Grinder Base B', '1 / 1'], ['Cost', '1,200 M'], ['+ Photon', '×1']], desc: 'A heavy two-handed sword. Materials short: Photon Steel.', action: 'Craft (1,200 M)' } },
          { name: 'Handgun', right: '650 M', sub: '★ · Handgun', marker: 'x', detail: { subtitle: '★ · Handgun-type', stats: [['Sinow Cell', '1 / 1'], ['Cost', '650 M'], ['+ Photon', '×1']], desc: 'Your class cannot equip Handguns, but you may still craft one.', action: 'Craft (650 M)' } },
          { name: 'Vjaya', right: '3,400 M', sub: '★★★ · Saber', rarity: 'rare', detail: { subtitle: '★★★ · Saber-type', stats: [['Mag Cell', '1 / 0'], ['Cost', '3,400 M'], ['+ Photon', '×1']], desc: 'A rare photon saber. Requires a Mag Cell (you have none).', action: 'Craft (3,400 M)' } },
        ],
      },
      {
        label: 'Boards',
        items: [
          { name: 'Vjaya Board', right: '★★★', rarity: 'rare', detail: { subtitle: 'Rare Recipe Board', desc: 'Learn this board to unlock the Vjaya recipe in the Craft tab.', action: 'Learn Board' } },
          { name: 'Rico’s Parasol Board', right: '★★★★', rarity: 'rare', detail: { subtitle: 'Rare Recipe Board', desc: 'An unusual recipe board recovered from the ruins.', action: 'Learn Board' } },
        ],
      },
    ],
  },
  {
    id: 'grind',
    area: 'market',
    label: 'Grind Shop',
    title: 'Tekker',
    blurb: 'Hand me a weapon and a grinder — I’ll push its edge a little further.',
    npc: npc('np_004_00_0', undefined, [6.25, 0, 23.45], -0.7533),
    accent: 0xd08334,
    currency: 'meseta',
    meseta: 12450,
    hint: 'A Grind (+1) · B Back',
    tabs: [{
      label: 'Grind',
      items: [
        { name: 'Saber', right: '300 M', sub: '+0 / +9  [Monogrinder]', detail: { subtitle: 'Current grind +0', stats: [['ATK', '40 → 42 (+2)'], ['ACC', '35 → 36 (+1)'], ['Grinder', 'Monogrinder x4'], ['Cost', '300 M']], desc: 'Grinding always succeeds in PSZ. Consumes 1 Monogrinder.', action: 'Grind (300 M)' } },
        { name: 'Brand', right: '600 M', sub: '+3 / +12  [Monogrinder]', detail: { subtitle: 'Current grind +3', stats: [['ATK', '58 → 60 (+2)'], ['ACC', '41 → 42 (+1)'], ['Grinder', 'Monogrinder x4'], ['Cost', '600 M']], desc: 'Consumes 1 Monogrinder.', action: 'Grind (600 M)' } },
        { name: 'Buster', right: '1,500 M', sub: '+1 / +15  [Digrinder]', detail: { subtitle: 'Current grind +1', stats: [['ATK', '84 → 88 (+4)'], ['ACC', '30 → 31 (+1)'], ['Grinder', 'Digrinder x1'], ['Cost', '1,500 M']], desc: 'Consumes 1 Digrinder.', action: 'Grind (1,500 M)' } },
        { name: 'Vjaya', right: '—', sub: '+7 / +7  MAX', marker: 'x', rarity: 'rare', detail: { subtitle: 'Fully ground', desc: 'This weapon is already at its maximum grind.', } },
      ],
    }],
  },
  {
    id: 'item',
    area: 'market',
    label: 'Item Shop',
    title: 'Item Shop',
    blurb: 'Stock up before you head out — mates, fluids, whatever you need.',
    npc: npc('np_003_00_0', 'pso_f_sh_stand', [-10.34, 0, 27.67], 1.4207),
    accent: 0x44aa66,
    currency: 'meseta',
    meseta: 12450,
    hint: 'A Buy · ◀▶ Tab · B Back',
    tabs: [
      {
        label: 'Items',
        items: [
          { name: 'Monomate', right: '50 M', detail: { subtitle: 'Recovery', stats: [['Cost', '50 M'], ['You have', 'x8']], desc: 'Restores a small amount of HP.', action: 'Buy (50 M)' } },
          { name: 'Dimate', right: '300 M', detail: { subtitle: 'Recovery', stats: [['Cost', '300 M'], ['You have', 'x3']], desc: 'Restores a moderate amount of HP.', action: 'Buy (300 M)' } },
          { name: 'Trimate', right: '2,000 M', detail: { subtitle: 'Recovery', stats: [['Cost', '2,000 M'], ['You have', 'x1']], desc: 'Fully restores HP.', action: 'Buy (2,000 M)' } },
          { name: 'Monofluid', right: '100 M', detail: { subtitle: 'Recovery', stats: [['Cost', '100 M'], ['You have', 'x5']], desc: 'Restores a small amount of PP.', action: 'Buy (100 M)' } },
          { name: 'Telepipe', right: '350 M', detail: { subtitle: 'Utility', stats: [['Cost', '350 M'], ['You have', 'x4']], desc: 'Opens a warp back to the city from the field.', action: 'Buy (350 M)' } },
          { name: 'Moon Atomizer', right: '500 M', detail: { subtitle: 'Utility', stats: [['Cost', '500 M'], ['You have', 'x1']], desc: 'Revives a fallen ally.', action: 'Buy (500 M)' } },
        ],
      },
      { label: 'Materials', items: [
        { name: 'Grinder Base C', right: '120 M', detail: { subtitle: 'Material', stats: [['Cost', '120 M'], ['You have', 'x2']], desc: 'A synthesis material for grinders.', action: 'Buy (120 M)' } },
        { name: 'Photon Booster', right: '900 M', detail: { subtitle: 'Material', stats: [['Cost', '900 M'], ['You have', 'x0']], desc: 'Enhances a photon weapon during synthesis.', action: 'Buy (900 M)' } },
      ] },
      { label: 'Disks', items: [
        { name: 'Foie Lv.3', right: '800 M', detail: { subtitle: 'Technique Disk', stats: [['Element', 'Fire'], ['Power', '96'], ['PP Cost', '5'], ['Req. Level', '8'], ['Known', 'Lv.2']], desc: 'Fires a bolt of flame at a single target.', action: 'Buy (800 M)' } },
        { name: 'Resta Lv.3', right: '750 M', marker: 'x', detail: { subtitle: 'Technique Disk', stats: [['Element', '—'], ['Target', 'Allies'], ['Req. Level', '10']], desc: 'Your class can never learn this technique.', } },
      ] },
      { label: 'Sell', items: [
        { name: 'Saber', right: '25 M', sub: 'x1', detail: { subtitle: 'Saber-type', stats: [['Sell price', '25 M']], desc: 'Sell this weapon for 25% of its buy price.', action: 'Sell (25 M)' } },
        { name: 'Monomate', right: '12 M', sub: 'x8', detail: { subtitle: 'Recovery', stats: [['Sell price', '12 M ea']], desc: 'Sell from the stack.', action: 'Sell…' } },
        { name: 'Brand', right: '88 M', sub: 'x1', marker: 'E', detail: { subtitle: 'Saber-type (equipped)', desc: 'Unequip before selling.', } },
      ] },
    ],
  },
  {
    id: 'weapon',
    area: 'market',
    label: 'Weapon Shop',
    title: 'Weapon Shop',
    blurb: 'Looking to gear up? Best blades and frames in the colony, right here.',
    npc: npc('np_002_00_0', 'pso_ro_stand', [-6.78, 0, 21.81], 0.7835),
    accent: 0xc0504d,
    currency: 'meseta',
    meseta: 12450,
    hint: 'A Buy · ◀▶ Tab · B Back',
    tabs: [
      {
        label: 'Weapons',
        items: [
          { name: 'Saber', right: '100 M', sub: 'Saber', detail: { subtitle: 'Saber-type', stats: [['ATK', '40–48'], ['ACC', '35'], ['Max Grind', '+9'], ['Buy / Sell', '100 / 25 M'], ['Can equip', 'Yes']], desc: 'A standard photon saber issued to new hunters.', action: 'Buy (100 M)' } },
          { name: 'Brand', right: '350 M', sub: 'Saber', detail: { subtitle: 'Saber-type', stats: [['ATK', '56–64'], ['ACC', '41'], ['Max Grind', '+12'], ['Buy / Sell', '350 / 88 M'], ['Can equip', 'Yes']], desc: 'An improved saber with a keener photon edge.', action: 'Buy (350 M)' } },
          { name: 'Buster', right: '800 M', sub: 'Sword', detail: { subtitle: 'Sword-type', stats: [['ATK', '82–96'], ['ACC', '30'], ['Max Grind', '+15'], ['Buy / Sell', '800 / 200 M'], ['Can equip', 'Yes']], desc: 'A heavy two-handed sword with wide reach.', action: 'Buy (800 M)' } },
          { name: 'Handgun', right: '450 M', sub: 'Handgun', marker: 'x', detail: { subtitle: 'Handgun-type', stats: [['ATK', '38–44'], ['ACC', '60'], ['Buy / Sell', '450 / 112 M'], ['Can equip', 'No']], desc: 'Your class cannot equip Handguns.', action: 'Buy (450 M)' } },
        ],
      },
      { label: 'Armor', items: [
        { name: 'Hunter Field', right: '300 M', sub: 'Frame', detail: { subtitle: 'Frame', stats: [['DEF', '18–24'], ['EVA', '10–14'], ['Unit Slots', '2'], ['Buy / Sell', '300 / 75 M']], desc: 'Standard-issue body frame with two unit slots.', action: 'Buy (300 M)' } },
        { name: 'Rabbit Wear', right: '1,100 M', sub: 'Robe', rarity: 'rare', detail: { subtitle: 'Robe', stats: [['DEF', '30–38'], ['EVA', '26–32'], ['Unit Slots', '4'], ['Fire res', '+10']], desc: 'A rare robe favoured by Forces.', action: 'Buy (1,100 M)' } },
      ] },
      { label: 'Units', items: [
        { name: 'Resist/Fire', right: '250 M', detail: { subtitle: 'Unit', stats: [['Category', 'Resist'], ['Effect', 'EFR +15']], desc: 'Reduces Fire damage taken.', action: 'Buy (250 M)' } },
        { name: 'Ace/Power', right: '600 M', detail: { subtitle: 'Unit', stats: [['Category', 'Stat'], ['Effect', 'ATP +20']], desc: 'Raises attack power.', action: 'Buy (600 M)' } },
      ] },
      { label: 'Sell', items: [
        { name: 'Gigush', right: '138 M', sub: 'x1', detail: { subtitle: 'Sword-type', stats: [['Sell price', '138 M']], desc: 'Sell for 25% of buy price.', action: 'Sell (138 M)' } },
        { name: 'Brand', right: '88 M', sub: 'x1', marker: 'E', detail: { subtitle: 'Saber-type (equipped)', desc: 'Unequip before selling.', } },
      ] },
    ],
  },
  {
    id: 'storage',
    area: 'counter',
    label: 'Item Counter (Storage)',
    title: 'Storage',
    blurb: 'I’ll keep your gear and meseta safe while you’re out there.',
    npc: npc('np_000_00_0', 'pso_f_sa_stand', [-10.53, -10.67, 114.15], 0.94),
    accent: 0x4b8fd6,
    currency: 'meseta',
    meseta: 12450,
    hint: 'A Deposit / Withdraw · ◀▶ Tab · B Back',
    tabs: [
      { label: 'Deposit Items', items: [
        { name: 'Monomate', right: 'x8', detail: { subtitle: 'Recovery', stats: [['Storable', 'Yes']], desc: 'Move from your inventory into shared storage.', action: 'Deposit…' } },
        { name: 'Saber', right: 'x1', detail: { subtitle: 'Saber-type', stats: [['ATK', '40'], ['Grind', '+0'], ['Storable', 'Yes']], desc: 'Deposit this weapon into storage.', action: 'Deposit' } },
        { name: 'Brand', right: 'x1', marker: 'E', detail: { subtitle: 'Saber-type (equipped)', desc: 'Equipped gear cannot be deposited.', } },
      ] },
      { label: 'Withdraw Items', items: [
        { name: 'DB’s Saber', right: 'x1', rarity: 'rare', detail: { subtitle: 'Saber-type', stats: [['ATK', '120'], ['Grind', '+5']], desc: 'Withdraw this rare saber from storage.', action: 'Withdraw' } },
        { name: 'Photon Drop', right: 'x6', detail: { subtitle: 'Material', desc: 'Withdraw from storage.', action: 'Withdraw…' } },
        { name: 'Mag Cell', right: 'x1', rarity: 'rare', detail: { subtitle: 'Material', desc: 'A rare synthesis material.', action: 'Withdraw' } },
      ] },
      { label: 'Deposit Meseta', items: [
        { name: 'Deposit Meseta…', sub: 'Wallet: 12,450 M  ·  Bank: 84,000 M', detail: { subtitle: 'Bank', stats: [['Wallet', '12,450 M'], ['Bank', '84,000 M']], desc: 'Choose an amount to move into the bank.', action: 'Deposit…' } },
      ] },
      { label: 'Withdraw Meseta', items: [
        { name: 'Withdraw Meseta…', sub: 'Wallet: 12,450 M  ·  Bank: 84,000 M', detail: { subtitle: 'Bank', stats: [['Wallet', '12,450 M'], ['Bank', '84,000 M']], desc: 'Choose an amount to withdraw to your wallet.', action: 'Withdraw…' } },
      ] },
    ],
  },
  {
    id: 'guild',
    area: 'counter',
    label: 'Guild Counter',
    title: 'Guild Counter',
    blurb: 'Welcome, hunter. Here are the missions the guild has posted today.',
    npc: npc('np_001_00_0', 'pso_f_sa_stand', [-7.86, -10.67, 111.39], 0.64),
    accent: 0xcfa738,
    currency: 'none',
    meseta: 12450,
    hint: 'A Accept · B Back',
    tabs: [{
      label: '',
      items: [
        { name: 'Search and Rescue', right: '[CLEAR]', sub: 'Gurhacia Valley', detail: { subtitle: 'Area: Valley · Normal', stats: [['Type', 'Quest'], ['Rank', 'C'], ['Reward', '500 M']], desc: 'Already cleared. Patrol the valley and rescue the missing scouts.', action: 'Replay' } },
        { name: 'Pioneer Patrol', right: '', sub: 'Gurhacia Valley', detail: { subtitle: 'Area: Valley · Normal', stats: [['Type', 'Quest'], ['Rank', 'C'], ['Reward', '600 M']], desc: 'Sweep the valley perimeter and eliminate hostile creatures.', action: 'Accept Quest' } },
        { name: 'Alpine Survey', right: '', sub: 'Rioh Snowfield', detail: { subtitle: 'Area: Snowfield · Normal', stats: [['Type', 'Quest'], ['Rank', 'B'], ['Reward', '1,200 M']], desc: 'Investigate unusual readings in the snowfield.', action: 'Accept Quest' } },
        { name: 'Wetland Cleanup', right: '[LOCKED]', sub: 'Ozette Wetlands', detail: { subtitle: 'Area: Wetlands', desc: 'Complete “Alpine Survey” to unlock this mission.', } },
        { name: 'Tower Ascent', right: '[LOCKED]', sub: 'Eternal Tower', rarity: 'rare', detail: { subtitle: 'Area: Eternal Tower', desc: 'Complete “Wetland Cleanup” to unlock this mission.', } },
      ],
    }],
  },
];

export function shopById(id: string | undefined): ShopDef | undefined {
  return SHOPS.find((s) => s.id === id);
}
