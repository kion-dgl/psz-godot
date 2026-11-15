import { useState } from 'react';
import { assetUrl } from '../../../utils/assets';
import { SCANLINES } from '../pszui';
import { ItemDetailCard, type DetailChrome, type DetailSpec } from './ItemDetailCard';

interface TypeEntry {
  id: string;
  label: string;
  shops: string;
  portrait: string;
  shopTitle: string;
  shopTabs: string[];
  activeTab: number;
  balanceLabel: string;
  variants: {
    label: string;
    rowMarker?: '✕' | '[E]';
    rowMuted?: boolean;
    rowRight: string;
    spec: DetailSpec;
  }[];
}

const TYPE_CATALOG: TypeEntry[] = [
  {
    id: 'weapon',
    label: '1. Weapon',
    shops: 'Weapon Shop (Buy/Sell) · Item Shop (Sell) · Storage',
    portrait: 'weapon-shop',
    shopTitle: 'WEAPON SHOP',
    shopTabs: ['Weapons', 'Armor', 'Units', 'Sell'],
    activeTab: 0,
    balanceLabel: '12,450 M',
    variants: [
      {
        label: 'Buy (vs Saber +1)',
        rowRight: '90 M',
        spec: {
          kind: 'weapon',
          name: 'Sword',
          icon: 'assets/ui/pso2/icon_sword.png',
          rarity: 2,
          weaponType: 'Sword · Melee',
          grindLabel: 'Max +9',
          stats: [
            { stat: 'ATK', itemVal: '40', equipFrom: 146, equipTo: 152, diff: 6 },
            { stat: 'ACC', itemVal: '35', equipFrom: 123, equipTo: 118, diff: -5 },
          ],
          element: { name: 'Fire Lv.1', color: '#e05545' },
          footerStats: [
            { label: 'Buy', value: '90 M', accent: 'gold' },
            { label: 'Sell', value: '45 M', accent: 'muted' },
            { label: 'Held', value: '0' },
          ],
          status: { text: '✓ Can equip (HUmar)', tone: 'ok' },
          legacyLines: [
            'Type: Sword',
            'Rarity: **',
            'ATK: 40 - 48',
            'ACC: 35',
            'Element: Fire Lv.1',
            'Max Grind: +9',
            '',
            'Buy: 90 M',
            'Sell: 45 M',
            'You have: 0',
            'Can equip',
          ],
        },
      },
      {
        label: 'Owned +4 / PA (Sell/Bank)',
        rowRight: '620 M',
        spec: {
          kind: 'weapon',
          name: 'Fenrir +4',
          icon: 'assets/ui/pso2/icon_twin_daggers.png',
          rarity: 5,
          weaponType: 'Daggers · Melee',
          grindLabel: '+4 / +9',
          stats: [
            { stat: 'ATK', itemVal: '92', equipFrom: 146, equipTo: 204, diff: 58 },
            { stat: 'ACC', itemVal: '54', equipFrom: 123, equipTo: 137, diff: 14 },
          ],
          element: { name: 'Ice Lv.2', color: '#3da0e3' },
          photonArt: 'Air Ride',
          footerStats: [
            { label: 'Sell', value: '620 M', accent: 'gold' },
            { label: 'Held', value: '1' },
          ],
          status: { text: '✓ Can equip · Storable', tone: 'ok' },
          legacyLines: [
            'Fenrir +4',
            'Owned: x1',
            '',
            'Sell: 620 M',
          ],
        },
      },
      {
        label: 'Class Blocked ✕',
        rowMarker: '✕',
        rowMuted: true,
        rowRight: '1,400 M',
        spec: {
          kind: 'weapon',
          name: 'Psycho Wand',
          icon: 'assets/ui/pso2/icon_rod.png',
          rarity: 7,
          weaponType: 'Rod · Force',
          grindLabel: 'Max +5',
          stats: [
            { stat: 'ATK', itemVal: '54', equipNote: '✕ Class' },
            { stat: 'ACC', itemVal: '42', equipNote: '✕ Class' },
          ],
          element: { name: 'Light Lv.3', color: '#78b84a' },
          photonArt: 'Rodeo Drive',
          footerStats: [
            { label: 'Buy', value: '1,400 M', accent: 'gold' },
            { label: 'Held', value: '0' },
          ],
          status: { text: '✕ Cannot equip: HUcast', tone: 'blocked' },
          legacyLines: [
            'Type: Rod',
            'Rarity: *******',
            'ATK: 54 - 66',
            'ACC: 42',
            'Element: Light Lv.3',
            'Max Grind: +5',
            '',
            'Buy: 1400 M',
            'Cannot equip: HUcast',
          ],
        },
      },
    ],
  },
  {
    id: 'armor',
    label: '2. Armor / Frame / Robe',
    shops: 'Weapon Shop (Armor/Sell) · Item Shop (Sell) · Storage',
    portrait: 'weapon-shop',
    shopTitle: 'WEAPON SHOP',
    shopTabs: ['Weapons', 'Armor', 'Units', 'Sell'],
    activeTab: 1,
    balanceLabel: '12,450 M',
    variants: [
      {
        label: '2-Slot Armor (Upgrade)',
        rowRight: '110 M',
        spec: {
          kind: 'armor',
          name: 'Psy Armor',
          icon: 'assets/ui/pso2/icon_costume.png',
          rarity: 3,
          armorType: 'Armor',
          slotsUsed: 0,
          slotsMax: 2,
          stats: [
            { stat: 'DEF', itemVal: '20', equipFrom: 84, equipTo: 92, diff: 8 },
            { stat: 'EVA', itemVal: '18', equipFrom: 76, equipTo: 82, diff: 6 },
            { stat: 'Fire Res.', itemVal: '+8', equipFrom: 4, equipTo: 8, diff: 4 },
            { stat: 'Ice Res.', itemVal: '+8', equipFrom: 0, equipTo: 8, diff: 8 },
            { stat: 'Light Res.', itemVal: '+4', equipFrom: 0, equipTo: 4, diff: 4 },
          ],
          footerStats: [
            { label: 'Buy', value: '110 M', accent: 'gold' },
            { label: 'Sell', value: '55 M', accent: 'muted' },
            { label: 'Held', value: '0' },
          ],
          status: { text: '✓ Can equip (HUmar)', tone: 'ok' },
          legacyLines: [
            'Rarity: ***',
            'DEF: 20',
            'EVA: 18',
            'Unit Slots: 2',
            'Resist: Fire 8  Ice 8  Light 4',
            '',
            'Buy: 110 M',
            'Sell: 55 M',
            'Can equip',
          ],
        },
      },
      {
        label: 'Equipped [E] (All 5 Resists)',
        rowMarker: '[E]',
        rowMuted: true,
        rowRight: 'x1',
        spec: {
          kind: 'armor',
          name: 'Carbinierir Frame',
          icon: 'assets/ui/pso2/icon_costume.png',
          rarity: 6,
          armorType: 'Frame',
          slotsUsed: 3,
          slotsMax: 4,
          stats: [
            { stat: 'DEF', itemVal: '48', equipNote: '132 [E]' },
            { stat: 'EVA', itemVal: '36', equipNote: '112 [E]' },
            { stat: 'Fire Res.', itemVal: '+12', equipNote: '+12 [E]' },
            { stat: 'Ice Res.', itemVal: '+6', equipNote: '+6 [E]' },
            { stat: 'Bolt Res.', itemVal: '+12', equipNote: '+12 [E]' },
            { stat: 'Light Res.', itemVal: '+10', equipNote: '+10 [E]' },
            { stat: 'Dark Res.', itemVal: '+6', equipNote: '+6 [E]' },
          ],
          footerStats: [{ label: 'In Pack', value: '1 (3/4 slots filled)' }],
          status: { text: '[E] Equipped — cannot deposit', tone: 'equipped' },
          legacyLines: [
            'Carbinierir Frame',
            'Type: Armor',
            'DEF: 48   EVA: 36',
            'Slots: 4',
            'Rarity: ******',
          ],
        },
      },
      {
        label: 'Robe (Force Only ✕)',
        rowMarker: '✕',
        rowMuted: true,
        rowRight: '420 M',
        spec: {
          kind: 'armor',
          name: 'Spirit Robe',
          icon: 'assets/ui/pso2/icon_costume.png',
          rarity: 4,
          armorType: 'Robe',
          slotsUsed: 0,
          slotsMax: 3,
          stats: [
            { stat: 'DEF', itemVal: '24', equipNote: '✕ Class' },
            { stat: 'EVA', itemVal: '42', equipNote: '✕ Class' },
            { stat: 'Fire Res.', itemVal: '+10', equipNote: '✕ Class' },
            { stat: 'Light Res.', itemVal: '+14', equipNote: '✕ Class' },
            { stat: 'Dark Res.', itemVal: '+14', equipNote: '✕ Class' },
          ],
          footerStats: [
            { label: 'Buy', value: '420 M', accent: 'gold' },
            { label: 'Held', value: '0' },
          ],
          status: { text: '✕ Cannot equip: HUcast', tone: 'blocked' },
          legacyLines: [
            'Rarity: ****',
            'DEF: 24',
            'EVA: 42',
            'Unit Slots: 3',
            'Resist: Fire 10  Ice 10  Lightning 10  Light 14  Dark 14',
            '',
            'Buy: 420 M',
            'Cannot equip: HUcast',
          ],
        },
      },
    ],
  },
  {
    id: 'unit',
    label: '3. Unit (Armor Slot)',
    shops: 'Weapon Shop (Units/Sell) · Photon Collector · Storage',
    portrait: 'weapon-shop',
    shopTitle: 'WEAPON SHOP',
    shopTabs: ['Weapons', 'Armor', 'Units', 'Sell'],
    activeTab: 2,
    balanceLabel: '12,450 M',
    variants: [
      {
        label: 'Stat Boost (Open Slot)',
        rowRight: '500 M',
        spec: {
          kind: 'unit',
          name: 'Ace / Power',
          icon: 'assets/ui/pso2/icon_unit.png',
          rarity: 4,
          category: 'Power Unit',
          stats: [{ stat: 'ATK', itemVal: '+15', equipFrom: 152, equipTo: 167, diff: 15 }],
          description:
            'Installs into an open Armor unit slot (Slot 2 free) to raise melee & ranged attack power.',
          footerStats: [
            { label: 'Buy', value: '500 M', accent: 'gold' },
            { label: 'Sell', value: '250 M', accent: 'muted' },
            { label: 'Held', value: '1' },
          ],
          status: { text: '✓ Fits open Unit Slot 2 (1/2 used)', tone: 'ok' },
          legacyLines: [
            'Rarity: ****',
            'Category: Power',
            'Effect: +15 ATP',
            '',
            'Buy: 500 M',
            'Sell: 250 M',
            'You have: 1',
          ],
        },
      },
      {
        label: 'Elemental Resist Unit',
        rowRight: '250 M',
        spec: {
          kind: 'unit',
          name: 'Heat Resist Lv.3',
          icon: 'assets/ui/pso2/icon_unit.png',
          rarity: 3,
          category: 'Resist Unit',
          stats: [
            { stat: 'Fire Res.', itemVal: '+12%', equipFrom: 8, equipTo: 20, diff: 12, diffSuffix: '%' },
          ],
          description: 'Shields the wearer against thermal traps and fire-aligned techniques.',
          footerStats: [
            { label: 'Buy', value: '250 M', accent: 'gold' },
            { label: 'Held', value: '0' },
          ],
          status: { text: '✓ Fits open Unit Slot 2 (1/2 used)', tone: 'ok' },
          legacyLines: [
            'Rarity: ***',
            'Category: Resist',
            'Effect: Fire resist +12%',
            '',
            'Buy: 250 M',
          ],
        },
      },
      {
        label: 'Rare Special Unit',
        rowRight: '12 PD',
        spec: {
          kind: 'unit',
          name: 'Compress PA',
          icon: 'assets/ui/pso2/icon_unit.png',
          rarity: 7,
          category: 'Special Unit',
          stats: [{ stat: 'PA Charge', itemVal: '−25%', equipNote: '75% time' }],
          description: 'Compresses Photon Art charge focus so heavy arts unleash faster in combat.',
          footerStats: [
            { label: 'Exchange', value: '12 PD', accent: 'pd' },
            { label: 'Held', value: '0' },
          ],
          status: { text: '✓ Fits any slotted Armor', tone: 'ok' },
          legacyLines: [
            'Compress PA',
            'Cost: 12 Photon Drops',
            'You have: 0',
          ],
        },
      },
    ],
  },
  {
    id: 'disk',
    label: '4. Technique Disk',
    shops: 'Item Shop (Disks/Sell) · Storage',
    portrait: 'item-shop',
    shopTitle: 'ITEM SHOP',
    shopTabs: ['Items', 'Materials', 'Disks', 'Sell'],
    activeTab: 2,
    balanceLabel: '12,450 M',
    variants: [
      {
        label: 'Learnable Upgrade',
        rowRight: '600 M',
        spec: {
          kind: 'disk',
          name: 'Disk: Foie Lv.3',
          icon: 'assets/ui/pso2/icon_photon_art.png',
          element: { name: 'Fire', color: '#e05545' },
          target: 'Single',
          power: '95 → 145 (+50)',
          ppCost: '8 → 10 (+2)',
          reqLevel: 'Lv. 6 (You: Lv. 12)',
          knownState: 'Lv.1 → Lv.3 ↑',
          knownUpgrade: true,
          note: 'Use from Pack to learn permanently. Buy 1 at a time.',
          footerStats: [
            { label: 'Buy', value: '600 M', accent: 'gold' },
            { label: 'Held', value: '0' },
          ],
          status: { text: '✓ Learnable upgrade (Lv.1 → Lv.3)', tone: 'ok' },
          legacyLines: [
            'Foie Lv.3',
            'Element: Fire',
            'Target: Single',
            'Power: 145',
            'PP Cost: 10',
            'Req. Level: 6',
            'Known: Lv.1',
            '',
            'Price: 600 M',
            'Use from inventory to learn',
          ],
        },
      },
      {
        label: 'Req. Level Too High',
        rowMuted: true,
        rowRight: '1,800 M',
        spec: {
          kind: 'disk',
          name: 'Disk: Grants Lv.5',
          icon: 'assets/ui/pso2/icon_photon_art.png',
          element: { name: 'Light', color: '#78b84a' },
          target: 'Single',
          power: '310',
          ppCost: '22',
          reqLevel: 'Lv. 18 (You: Lv. 12)',
          knownState: 'Unlearned',
          note: 'Still buyable now; usable once character reaches Lv. 18.',
          footerStats: [
            { label: 'Buy', value: '1,800 M', accent: 'gold' },
            { label: 'Held', value: '0' },
          ],
          status: { text: 'Requires Character Lv. 18', tone: 'warn' },
          legacyLines: [
            'Grants Lv.5',
            'Element: Light',
            'Target: Single',
            'Power: 310',
            'PP Cost: 22',
            'Req. Level: 18',
            'Known: None',
            '',
            'Price: 1800 M',
            'Requires Lv. 18',
          ],
        },
      },
      {
        label: 'CAST Blocked ✕',
        rowMarker: '✕',
        rowMuted: true,
        rowRight: '300 M',
        spec: {
          kind: 'disk',
          name: 'Disk: Resta Lv.2',
          icon: 'assets/ui/pso2/icon_photon_art.png',
          element: { name: 'Light', color: '#78b84a' },
          target: 'Party Area',
          power: '120 HP',
          ppCost: '14',
          reqLevel: 'Lv. 4',
          knownState: 'N/A (CAST)',
          note: 'CASTs have no Technique access; may still buy for shared Storage.',
          footerStats: [
            { label: 'Buy', value: '300 M', accent: 'gold' },
            { label: 'Held', value: '0' },
          ],
          status: { text: '✕ Cannot learn: CAST race', tone: 'blocked' },
          legacyLines: [
            'Resta Lv.2',
            'Element: Heal',
            'Target: Multi',
            'Power: 120',
            'PP Cost: 14',
            'Req. Level: 4',
            '',
            'Price: 300 M',
            'Cannot learn: HUcast',
          ],
        },
      },
    ],
  },
  {
    id: 'consumable',
    label: '5. Consumable',
    shops: 'Item Shop (Items/Sell) · Photon Collector · Storage',
    portrait: 'item-shop',
    shopTitle: 'ITEM SHOP',
    shopTabs: ['Items', 'Materials', 'Disks', 'Sell'],
    activeTab: 0,
    balanceLabel: '12,450 M',
    variants: [
      {
        label: 'Standard Healing',
        rowRight: '300 M',
        spec: {
          kind: 'consumable',
          name: 'Dimate',
          icon: 'assets/ui/pso2/icon_dimate.png',
          rarity: 2,
          category: 'Consumable · Recovery',
          held: 4,
          maxStack: 10,
          description: 'Restores 60% of maximum HP to the user. Reliable mid-tier recovery medicine.',
          footerStats: [
            { label: 'Buy', value: '300 M', accent: 'gold' },
            { label: 'Sell', value: '150 M', accent: 'muted' },
          ],
          status: { text: '✓ Qty Stepper (up to +6 room)', tone: 'ok' },
          legacyLines: [
            'Dimate',
            'Category: Consumable',
            'Cost: 300 Meseta',
            'You have: 4',
            '',
            'Restores 60% of maximum HP to the user.',
          ],
        },
      },
      {
        label: 'Long Wrapping Text',
        rowRight: '350 M',
        spec: {
          kind: 'consumable',
          name: 'Telepipe',
          icon: 'assets/ui/pso2/icon_telepipe.png',
          rarity: 2,
          category: 'Consumable · Field Warp',
          held: 10,
          maxStack: 10,
          description:
            'Deploys a temporary return gate from a field expedition back to Dairon City. Stepping back through the city warp resumes the exact room.',
          footerStats: [
            { label: 'Buy', value: '350 M', accent: 'gold' },
            { label: 'Held', value: '10 / 10' },
          ],
          status: { text: 'Stack Full (10 / 10 in Pack)', tone: 'warn' },
          legacyLines: [
            'Telepipe',
            'Category: Consumable',
            'Cost: 350 Meseta',
            'You have: 10',
            '',
            'Deploys a temporary return gate from a field expedition back to Dairon City. Stepping back through the city warp resumes the exact room.',
          ],
        },
      },
      {
        label: 'Sell Tab (Half Price)',
        rowRight: '250 M',
        spec: {
          kind: 'consumable',
          name: 'Moon Atomizer',
          icon: 'assets/ui/pso2/icon_moon_atomizer.png',
          rarity: 3,
          category: 'Consumable · Revive',
          held: 3,
          maxStack: 10,
          description: 'Revives an incapacitated party member or companion nearby with half HP.',
          footerStats: [
            { label: 'Sell (50%)', value: '250 M ea', accent: 'gold' },
            { label: 'Held', value: '3 / 10' },
          ],
          status: { text: '✓ Sell Stepper (1–3)', tone: 'ok' },
          legacyLines: [
            'Moon Atomizer',
            'Owned: x3',
            '',
            'Sell: 250 M',
          ],
        },
      },
    ],
  },
  {
    id: 'material',
    label: '6. Material / Modifier / Photon',
    shops: 'Photon Collector · Synthesis · Item Shop · Storage',
    portrait: 'photon-collector',
    shopTitle: 'PHOTON COLLECTOR',
    shopTabs: ['Exchange'],
    activeTab: 0,
    balanceLabel: '14 PD',
    variants: [
      {
        label: 'Stat Material (PD Shop)',
        rowRight: '5 PD',
        spec: {
          kind: 'material',
          name: 'Power Material',
          icon: 'assets/ui/pso2/icon_material.png',
          rarity: 4,
          subkind: 'Stat Material',
          held: 3,
          maxStack: 99,
          effectSummary: 'Permanent +2 ATP',
          description:
            'Consumed from Pack to permanently raise character Attack Power toward the material cap.',
          footerStats: [
            { label: 'Exchange', value: '5 PD', accent: 'pd' },
            { label: 'You Hold', value: '14 PD' },
          ],
          status: { text: '✓ Exchangeable (14 PD held)', tone: 'ok' },
          legacyLines: [
            'Power Material',
            'Cost: 5 Photon Drops',
            'You have: 3',
          ],
        },
      },
      {
        label: 'Elemental Photon',
        rowRight: 'x4',
        spec: {
          kind: 'material',
          name: 'Im-Photon',
          icon: 'assets/ui/pso2/icon_material.png',
          rarity: 3,
          subkind: 'Synthesis Modifier',
          held: 4,
          maxStack: 99,
          effectSummary: 'Weapon Element',
          elementTag: { name: 'Fire', color: '#e05545' },
          description:
            'Crystallized thermal photon added during weapon synthesis to grant a Fire attribute.',
          footerStats: [
            { label: 'Sell', value: '100 M', accent: 'gold' },
            { label: 'Held', value: '4 / 99' },
          ],
          status: { text: 'Used at Synthesis Counter', tone: 'neutral' },
          legacyLines: [
            'Im-Photon',
            'Count: x4',
          ],
        },
      },
      {
        label: 'Short on PD (Greyed)',
        rowMuted: true,
        rowRight: '20 PD',
        spec: {
          kind: 'material',
          name: 'Trigrinder',
          icon: 'assets/ui/pso2/icon_material.png',
          rarity: 5,
          subkind: 'Weapon Grinder',
          held: 1,
          maxStack: 99,
          effectSummary: 'Weapon Grind +1 to +3',
          description: 'High-grade grinding compound used by the Tekker to reinforce rare blades.',
          footerStats: [
            { label: 'Exchange', value: '20 PD', accent: 'pd' },
            { label: 'You Hold', value: '14 PD', accent: 'muted' },
          ],
          status: { text: 'Need 6 more Photon Drops', tone: 'warn' },
          legacyLines: [
            'Trigrinder',
            'Cost: 20 Photon Drops',
            'You have: 1',
            'Not enough Photon Drops',
          ],
        },
      },
    ],
  },
  {
    id: 'mag',
    label: '7. Mag (Sell & Storage)',
    shops: 'Storage (Deposit/Withdraw) · Item & Weapon Shop (Sell)',
    portrait: 'item-shop',
    shopTitle: 'STORAGE COUNTER',
    shopTabs: ['Deposit', 'Withdraw', 'Dep. M', 'Wdr. M'],
    activeTab: 0,
    balanceLabel: 'Bank: 45,000 M',
    variants: [
      {
        label: 'Stage 2 Mag (vs Equipped)',
        rowRight: 'Lv.34',
        spec: {
          kind: 'mag',
          name: 'Yul',
          icon: 'assets/ui/pso2/icon_mag.png',
          level: 34,
          stageLabel: 'Stage 2',
          personality: 'Breezy',
          colorName: 'Sky Blue',
          stats: [
            { stat: 'POW (ATK)', itemVal: '20', equipFrom: 146, equipTo: 158, diff: 12 },
            { stat: 'GRD (DEF)', itemVal: '4', equipFrom: 84, equipTo: 82, diff: -2 },
            { stat: 'HIT (ACC)', itemVal: '10', equipFrom: 123, equipTo: 129, diff: 6 },
            { stat: 'MND (TEC)', itemVal: '0', equipFrom: 64, equipTo: 64, diff: 0 },
          ],
          syncIq: '85% · IQ 48',
          photonBlast: 'Granir',
          footerStats: [
            { label: 'Sell', value: '500 M', accent: 'gold' },
            { label: 'Storage', value: '12 / 100' },
          ],
          status: { text: '✓ Storable in Shared Trunk', tone: 'ok' },
          legacyLines: [
            'Yul',
            'Type: Mag',
          ],
        },
      },
      {
        label: 'Equipped Mag [E]',
        rowMarker: '[E]',
        rowMuted: true,
        rowRight: 'Lv.68',
        spec: {
          kind: 'mag',
          name: 'femini',
          icon: 'assets/ui/pso2/icon_mag.png',
          level: 68,
          stageLabel: 'Stage 4',
          personality: 'Eccentric',
          colorName: 'Amber',
          stats: [
            { stat: 'POW (ATK)', itemVal: '8', equipNote: '146 [E]' },
            { stat: 'GRD (DEF)', itemVal: '14', equipNote: '84 [E]' },
            { stat: 'HIT (ACC)', itemVal: '12', equipNote: '123 [E]' },
            { stat: 'MND (TEC)', itemVal: '34', equipNote: '98 [E]' },
          ],
          syncIq: '120% · IQ 160',
          photonBlast: 'Flozir',
          footerStats: [{ label: 'Slot', value: 'Equipped Mag' }],
          status: { text: '[E] Equipped — cannot deposit/sell', tone: 'equipped' },
          legacyLines: [
            'femini',
            'Type: Mag',
            'Equipped — cannot deposit',
          ],
        },
      },
    ],
  },
  {
    id: 'synthesis',
    label: '8. Synthesis (Craft & Board)',
    shops: 'Crafting / Synthesis Counter (Craft · Boards)',
    portrait: 'custom-shop',
    shopTitle: 'SYNTHESIS SHOP',
    shopTabs: ['Craft', 'Boards'],
    activeTab: 0,
    balanceLabel: '12,450 M',
    variants: [
      {
        label: 'Craft Ready',
        rowRight: '400 M',
        spec: {
          kind: 'synthesis',
          mode: 'craft',
          name: 'Brand',
          icon: 'assets/ui/pso2/icon_sword.png',
          rarity: 2,
          outputType: 'Output: Saber',
          outputStats: [
            { stat: 'ATK', itemVal: '52', equipFrom: 146, equipTo: 164, diff: 18 },
            { stat: 'ACC', itemVal: '38', equipFrom: 123, equipTo: 126, diff: 3 },
          ],
          ingredients: [
            { name: '[B] Brand', have: 1, need: 1 },
            { name: 'Monogrinder', have: 5, need: 2 },
            { name: 'Im-Photon (Fire)', have: 2, need: 1, optional: true },
          ],
          footerStats: [
            { label: 'Craft Cost', value: '400 M', accent: 'gold' },
            { label: 'Output Held', value: '0' },
          ],
          status: { text: '✓ All Materials Met — Ready', tone: 'ok' },
          legacyLines: [
            'Brand',
            '** · Saber',
            '',
            '[B] Brand  1/1',
            'Monogrinder  5/2',
            '',
            'Cost: 400 M',
          ],
        },
      },
      {
        label: 'Missing Materials',
        rowMuted: true,
        rowRight: '1,200 M',
        spec: {
          kind: 'synthesis',
          mode: 'craft',
          name: 'Durandal',
          icon: 'assets/ui/pso2/icon_sword.png',
          rarity: 6,
          outputType: 'Output: Saber',
          outputStats: [
            { stat: 'ATK', itemVal: '128', equipFrom: 146, equipTo: 240, diff: 94 },
            { stat: 'ACC', itemVal: '52', equipFrom: 123, equipTo: 140, diff: 17 },
          ],
          ingredients: [
            { name: '[B] Durandal', have: 1, need: 1 },
            { name: 'Trigrinder', have: 1, need: 3 },
            { name: 'Rappy Soul', have: 0, need: 1 },
          ],
          footerStats: [
            { label: 'Craft Cost', value: '1,200 M', accent: 'gold' },
            { label: 'Output Held', value: '0' },
          ],
          status: { text: 'Missing 2× Trigrinder, 1× Rappy Soul', tone: 'blocked' },
          legacyLines: [
            'Durandal',
            '****** · Saber',
            '',
            '[B] Durandal  1/1',
            'Trigrinder  1/3',
            'Rappy Soul  0/1',
            '',
            'Cost: 1200 M',
          ],
        },
      },
      {
        label: 'Owned Recipe Board',
        rowRight: 'x1',
        spec: {
          kind: 'synthesis',
          mode: 'board',
          name: '[B] Brand',
          icon: 'assets/ui/pso2/icon_material.png',
          rarity: 2,
          outputType: 'Yields: Brand (Saber)',
          outputStats: [
            { stat: 'ATK', itemVal: '52', equipFrom: 146, equipTo: 164, diff: 18 },
            { stat: 'ACC', itemVal: '38', equipFrom: 123, equipTo: 126, diff: 3 },
          ],
          ingredients: [
            { name: '[B] Brand (Held)', have: 1, need: 1 },
            { name: 'Monogrinder', have: 5, need: 2 },
          ],
          footerStats: [
            { label: 'Craft Cost', value: '400 M', accent: 'gold' },
            { label: 'Boards Held', value: '1' },
          ],
          status: { text: 'Switch to Craft tab to build', tone: 'neutral' },
          legacyLines: [
            '[B] Brand',
            '★★',
            'Owned: 1',
          ],
        },
      },
    ],
  },
  {
    id: 'tekker',
    label: '9. Tekker Grind',
    shops: 'Tekker Counter (Weapon Grind)',
    portrait: 'custom-shop',
    shopTitle: 'TEKKER',
    shopTabs: ['Grind'],
    activeTab: 0,
    balanceLabel: '12,450 M',
    variants: [
      {
        label: 'Grind +2 → +3',
        rowRight: '350 M',
        spec: {
          kind: 'tekker',
          name: 'Fenrir +2',
          icon: 'assets/ui/pso2/icon_twin_daggers.png',
          rarity: 5,
          weaponType: 'Daggers · Equipped',
          grindMax: 9,
          rows: [
            { label: 'Grind', before: '+2', after: '+3', delta: '+1', positive: true },
            { label: 'Weapon ATK', before: '88', after: '90', delta: '+2', positive: true },
            { label: 'Total ATK', before: '200', after: '202', delta: '+2', positive: true },
            { label: 'Weapon ACC', before: '54', after: '56', delta: '+2', positive: true },
          ],
          requiredGrinder: { name: 'Digrinder', held: 4 },
          allGrinders: [
            { short: 'Mono', held: 7 },
            { short: 'Di', held: 4, active: true },
            { short: 'Tri', held: 1 },
          ],
          footerStats: [
            { label: 'Grind Cost', value: '350 M', accent: 'gold' },
            { label: 'Meseta', value: '12,450 M', accent: 'muted' },
          ],
          status: { text: '✓ Ready to Grind (+2 → +3)', tone: 'ok' },
          legacyLines: [
            'Grinders:',
            'Monogrinder: x7',
            'Digrinder: x4',
            'Trigrinder: x1',
            '',
            'After Grind:',
            'ATK: 88 -> 90 (+2)',
            'ACC: 54 -> 56 (+2)',
            '',
            'Cost: 350 M',
          ],
        },
      },
      {
        label: 'Missing Grinder',
        rowMuted: true,
        rowRight: '600 M',
        spec: {
          kind: 'tekker',
          name: 'Pallasch +5',
          icon: 'assets/ui/pso2/icon_sword.png',
          rarity: 6,
          weaponType: 'Saber · In Pack',
          grindMax: 9,
          rows: [
            { label: 'Grind', before: '+5', after: '+6', delta: '+1', positive: true },
            { label: 'Weapon ATK', before: '112', after: '114', delta: '+2', positive: true },
            { label: 'Weapon ACC', before: '60', after: '61', delta: '+1', positive: true },
          ],
          requiredGrinder: { name: 'Trigrinder', held: 0 },
          allGrinders: [
            { short: 'Mono', held: 7 },
            { short: 'Di', held: 4 },
            { short: 'Tri', held: 0, active: true },
          ],
          footerStats: [{ label: 'Grind Cost', value: '600 M', accent: 'gold' }],
          status: { text: 'Missing Required Trigrinder', tone: 'blocked' },
          legacyLines: [
            'Grinders:',
            'Monogrinder: x7',
            'Digrinder: x4',
            'Trigrinder: x0',
            '',
            'After Grind:',
            'ATK: 112 -> 114 (+2)',
            'Cost: 600 M',
            'Need Trigrinder',
          ],
        },
      },
      {
        label: 'Max Grind Reached',
        rowMuted: true,
        rowRight: 'MAX',
        spec: {
          kind: 'tekker',
          name: 'Saber +9',
          icon: 'assets/ui/pso2/icon_sword.png',
          rarity: 1,
          weaponType: 'Saber · Equipped',
          grindMax: 9,
          rows: [
            { label: 'Grind', before: '+9 / +9 (MAX)' },
            { label: 'Weapon ATK', before: '50 (Max)' },
            { label: 'Weapon ACC', before: '36 (Max)' },
          ],
          allGrinders: [
            { short: 'Mono', held: 7 },
            { short: 'Di', held: 4 },
            { short: 'Tri', held: 1 },
          ],
          footerStats: [{ label: 'Grind Cap', value: '+9 / +9 (Max)' }],
          status: { text: 'Maximum Grind Reached', tone: 'neutral' },
          legacyLines: [
            'Saber +9',
            'Already at maximum grind (+9)',
          ],
        },
      },
    ],
  },
];

function SegButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        padding: '6px 12px',
        fontSize: 12,
        fontWeight: 700,
        borderRadius: 5,
        cursor: 'pointer',
        border: active ? '1px solid #f0a020' : '1px solid #30363d',
        background: active ? 'linear-gradient(90deg, #f0a020 0%, #f8c840 100%)' : '#161b22',
        color: active ? '#141a24' : '#c9d1d9',
        fontFamily: 'inherit',
      }}
    >
      {children}
    </button>
  );
}

export default function ShopDetailGallery() {
  const [chrome, setChrome] = useState<DetailChrome>('blue-glass');
  const [viewMode, setViewMode] = useState<'grid' | 'in-shop'>('grid');
  const [narrow43, setNarrow43] = useState(false);
  const [compareBefore, setCompareBefore] = useState(false);

  const [variantByType, setVariantByType] = useState<Record<string, number>>({});
  const [activeTypeIdx, setActiveTypeIdx] = useState(0);

  const cardWidth = narrow43 ? 268 : 320;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 18, margin: '16px 0 36px' }}>
      {/* TOP WORKBENCH TOOLBAR */}
      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 12,
          padding: '12px 16px',
          background: '#0d1117',
          border: '1px solid #30363d',
          borderRadius: 8,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 11, fontWeight: 700, color: '#8b949e', textTransform: 'uppercase' }}>
            Card Chrome:
          </span>
          <SegButton active={chrome === 'blue-glass'} onClick={() => setChrome('blue-glass')}>
            Style A · PSZ Blue Glass (Recommended)
          </SegButton>
          <SegButton active={chrome === 'chamfer-plate'} onClick={() => setChrome('chamfer-plate')}>
            Style B · DS Chamfered Plate
          </SegButton>
          <SegButton active={chrome === 'legacy-white'} onClick={() => setChrome('legacy-white')}>
            Legacy White (#772 Before)
          </SegButton>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 11, fontWeight: 700, color: '#8b949e', textTransform: 'uppercase' }}>
            Layout:
          </span>
          <SegButton active={viewMode === 'grid'} onClick={() => setViewMode('grid')}>
            All 9 Types Grid
          </SegButton>
          <SegButton active={viewMode === 'in-shop'} onClick={() => setViewMode('in-shop')}>
            In-Shop Live Frame
          </SegButton>
          <SegButton active={narrow43} onClick={() => setNarrow43((v) => !v)}>
            {narrow43 ? 'Aspect: 4:3 Narrow (268px)' : 'Aspect: 16:9 Native (320px)'}
          </SegButton>
          {viewMode === 'grid' && chrome !== 'legacy-white' && (
            <SegButton active={compareBefore} onClick={() => setCompareBefore((v) => !v)}>
              {compareBefore ? 'Hide Before' : 'Compare vs #772 Before'}
            </SegButton>
          )}
        </div>
      </div>

      {/* MODE 1: ALL 9 ITEM TYPES SIDE-BY-SIDE GRID */}
      {viewMode === 'grid' ? (
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: compareBefore
              ? 'repeat(auto-fill, minmax(580px, 1fr))'
              : 'repeat(auto-fill, minmax(356px, 1fr))',
            gap: 16,
          }}
        >
          {TYPE_CATALOG.map((entry, entryIdx) => {
            const vIdx = variantByType[entry.id] ?? 0;
            const currentVariant = entry.variants[vIdx] ?? entry.variants[0];
            return (
              <div
                key={entry.id}
                style={{
                  background: '#11161f',
                  border: '1px solid #2b3442',
                  borderRadius: 8,
                  padding: 14,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 10,
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
                  <div>
                    <div style={{ fontSize: 14, fontWeight: 800, color: '#e6edf3' }}>{entry.label}</div>
                    <div style={{ fontSize: 11, color: '#8b949e', marginTop: 2 }}>{entry.shops}</div>
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      setActiveTypeIdx(entryIdx);
                      setViewMode('in-shop');
                    }}
                    style={{
                      fontSize: 11,
                      padding: '3px 8px',
                      borderRadius: 4,
                      border: '1px solid #384454',
                      background: '#1a2230',
                      color: '#88b8ff',
                      cursor: 'pointer',
                      flexShrink: 0,
                    }}
                  >
                    View in Shop ↗
                  </button>
                </div>

                {/* Variant state pills */}
                <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap' }}>
                  {entry.variants.map((v, idx) => {
                    const isOn = idx === vIdx;
                    return (
                      <button
                        key={v.label}
                        type="button"
                        onClick={() => setVariantByType((prev) => ({ ...prev, [entry.id]: idx }))}
                        style={{
                          fontSize: 11,
                          fontWeight: isOn ? 700 : 500,
                          padding: '3px 8px',
                          borderRadius: 99,
                          cursor: 'pointer',
                          border: isOn ? '1px solid #58a6ff' : '1px solid #2d3542',
                          background: isOn ? 'rgba(56, 139, 253, 0.2)' : '#161b22',
                          color: isOn ? '#a5d6ff' : '#9ca7b4',
                        }}
                      >
                        {v.label}
                      </button>
                    );
                  })}
                </div>

                {/* Card Stage */}
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: 12,
                    flexWrap: 'wrap',
                    padding: '14px 10px',
                    borderRadius: 6,
                    background: 'radial-gradient(circle at 75% 30%, #33475e 0%, #1a2433 65%, #111822 100%)',
                    border: '1px solid #243040',
                  }}
                >
                  {compareBefore && chrome !== 'legacy-white' && (
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
                      <span style={{ fontSize: 10, fontWeight: 700, color: '#f08888', letterSpacing: '0.05em' }}>
                        BEFORE (#772 WHITE BOX)
                      </span>
                      <ItemDetailCard spec={currentVariant.spec} chrome="legacy-white" width={248} height={288} />
                    </div>
                  )}
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
                    {compareBefore && chrome !== 'legacy-white' && (
                      <span style={{ fontSize: 10, fontWeight: 700, color: '#7ee787', letterSpacing: '0.05em' }}>
                        PROPOSED ({chrome === 'blue-glass' ? 'BLUE GLASS' : 'CHAMFER PLATE'})
                      </span>
                    )}
                    <ItemDetailCard spec={currentVariant.spec} chrome={chrome} width={cardWidth} height={288} />
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        /* MODE 2: LIVE IN-SHOP DIEGETIC FRAME */
        (() => {
          const entry = TYPE_CATALOG[activeTypeIdx] ?? TYPE_CATALOG[0];
          const vIdx = variantByType[entry.id] ?? 0;
          const activeVariant = entry.variants[vIdx] ?? entry.variants[0];

          return (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {TYPE_CATALOG.map((t, idx) => (
                  <SegButton key={t.id} active={idx === activeTypeIdx} onClick={() => setActiveTypeIdx(idx)}>
                    {t.label}
                  </SegButton>
                ))}
              </div>

              <div style={{ overflowX: 'auto' }}>
                <div
                  style={{
                    width: narrow43 ? 960 : 1120,
                    height: 630,
                    position: 'relative',
                    borderRadius: 8,
                    overflow: 'hidden',
                    border: '1px solid #30363d',
                    background:
                      'radial-gradient(ellipse at 76% 42%, #475a70 0%, #243144 45%, #131b26 100%)',
                    fontFamily: "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace",
                    boxShadow: '0 10px 28px rgba(0,0,0,0.45)',
                  }}
                >
                  <div
                    style={{
                      position: 'absolute',
                      top: 8,
                      right: 12,
                      fontSize: 11,
                      color: 'rgba(220,235,255,0.65)',
                      background: 'rgba(10,16,24,0.55)',
                      padding: '2px 8px',
                      borderRadius: 4,
                      zIndex: 5,
                    }}
                  >
                    {narrow43 ? '4:3 Viewport (1280×960 / 960×720)' : '16:9 Viewport (1280×720)'}
                  </div>

                  <img
                    src={assetUrl(`assets/ui/shop-previews/${entry.portrait}.png`)}
                    alt="Shopkeeper"
                    style={{
                      position: 'absolute',
                      right: narrow43 ? 12 : 42,
                      bottom: 0,
                      width: narrow43 ? 250 : 320,
                      height: narrow43 ? 250 : 320,
                      objectFit: 'contain',
                      objectPosition: 'bottom right',
                      imageRendering: 'pixelated',
                      opacity: 0.92,
                      pointerEvents: 'none',
                    }}
                  />

                  <div
                    style={{
                      position: 'absolute',
                      left: 20,
                      top: 24,
                      bottom: 24,
                      width: narrow43 ? 378 : 420,
                      background: 'rgba(168, 204, 232, 0.86)',
                      backgroundImage: SCANLINES,
                      border: '3px solid #2a3448',
                      borderRadius: 7,
                      display: 'flex',
                      flexDirection: 'column',
                      overflow: 'hidden',
                      boxShadow: '0 6px 18px rgba(0,0,0,0.32)',
                    }}
                  >
                    <div
                      style={{
                        background: 'linear-gradient(90deg, #1e2838 0%, #2a3850 100%)',
                        borderBottom: '2px solid #f0a020',
                        color: '#f8c840',
                        fontWeight: 800,
                        fontSize: 14,
                        letterSpacing: '0.05em',
                        padding: '7px 12px',
                      }}
                    >
                      {entry.shopTitle}
                    </div>

                    <div style={{ display: 'flex', gap: 4, padding: '8px 10px 6px' }}>
                      {entry.shopTabs.map((tab, tIdx) => {
                        const on = tIdx === entry.activeTab;
                        return (
                          <span
                            key={tab}
                            style={{
                              padding: '4px 11px',
                              fontSize: 11.5,
                              fontWeight: 800,
                              borderRadius: 4,
                              background: on
                                ? 'linear-gradient(90deg, #f0a020 0%, #f8c840 100%)'
                                : 'rgba(255,255,255,0.82)',
                              border: on ? '2px solid #d08010' : '1px solid rgba(130,165,198,0.55)',
                              color: '#1a1a2a',
                            }}
                          >
                            {tab}
                          </span>
                        );
                      })}
                    </div>

                    <div
                      style={{
                        flex: 1,
                        margin: '2px 10px 8px',
                        padding: 6,
                        borderRadius: 5,
                        background: 'rgba(232, 242, 252, 0.65)',
                        border: '1px solid rgba(118, 152, 186, 0.45)',
                        display: 'flex',
                        flexDirection: 'column',
                        gap: 4,
                      }}
                    >
                      {entry.variants.map((v, idx) => {
                        const selected = idx === vIdx;
                        return (
                          <div
                            key={v.label}
                            onClick={() => setVariantByType((prev) => ({ ...prev, [entry.id]: idx }))}
                            style={{
                              display: 'flex',
                              alignItems: 'center',
                              gap: 6,
                              padding: '6px 9px',
                              borderRadius: 4,
                              cursor: 'pointer',
                              background: selected
                                ? 'linear-gradient(90deg, #f0a020 0%, #f8c840 100%)'
                                : 'rgba(255,255,255,0.88)',
                              border: selected ? '2px solid #d08010' : '1px solid rgba(140,172,204,0.5)',
                              color: v.rowMuted ? 'rgba(26,32,44,0.48)' : '#182232',
                              fontWeight: 700,
                              fontSize: 12.5,
                            }}
                          >
                            <span
                              style={{
                                width: 22,
                                textAlign: 'center',
                                fontWeight: 800,
                                fontSize: 11,
                                color: v.rowMarker === '✕' ? '#b32424' : '#32527b',
                                flexShrink: 0,
                              }}
                            >
                              {v.rowMarker ?? ''}
                            </span>
                            <img
                              src={assetUrl(v.spec.icon)}
                              alt=""
                              style={{
                                width: 16,
                                height: 16,
                                imageRendering: 'pixelated',
                                opacity: v.rowMuted ? 0.45 : 1,
                                flexShrink: 0,
                              }}
                            />
                            <span
                              style={{
                                flex: 1,
                                overflow: 'hidden',
                                textOverflow: 'ellipsis',
                                whiteSpace: 'nowrap',
                              }}
                            >
                              {v.spec.name}
                            </span>
                            <span style={{ fontSize: 11.5, flexShrink: 0 }}>{v.rowRight}</span>
                          </div>
                        );
                      })}
                      <div style={{ marginTop: 'auto', fontSize: 10.5, color: '#4c627a', padding: '4px 4px 2px' }}>
                        Click rows above to preview each item state in-context.
                      </div>
                    </div>

                    <div
                      style={{
                        background: 'rgba(30, 40, 56, 0.92)',
                        color: '#ffd460',
                        fontWeight: 800,
                        fontSize: 12,
                        padding: '6px 12px',
                        textAlign: 'right',
                      }}
                    >
                      {entry.balanceLabel}
                    </div>
                  </div>

                  <div
                    style={{
                      position: 'absolute',
                      left: (narrow43 ? 378 : 420) + 32,
                      top: 24,
                    }}
                  >
                    <ItemDetailCard
                      spec={activeVariant.spec}
                      chrome={chrome}
                      width={narrow43 ? 268 : 320}
                      height={288}
                    />
                  </div>
                </div>
              </div>
            </div>
          );
        })()
      )}
    </div>
  );
}
