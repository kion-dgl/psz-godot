/**
 * Weapon Gallery Data — uses psz-sketch weapon assets via symlink.
 * Weapon GLBs at /weapons/{id}/{id}/{variant}/{variant}.glb
 */

import { assetUrl } from '../utils/assets';

export interface WeaponInfo {
  id: string;
  name: string;
  textureCount: number;
  animationCount: number;
  variants: string[];
}

export interface WeaponCategory {
  id: string;
  label: string;
  prefix: string;
  description: string;
}

export const WEAPON_CATEGORIES: WeaponCategory[] = [
  { id: 'sword', label: 'Sword', prefix: 'wsw', description: 'Two-handed swords' },
  { id: 'saber', label: 'Saber', prefix: 'wsa', description: 'One-handed blades' },
  { id: 'dagger', label: 'Dagger', prefix: 'wda', description: 'Twin daggers' },
  { id: 'claw', label: 'Claw', prefix: 'wcl', description: 'Fist weapons' },
  { id: 'double-saber', label: 'Double Saber', prefix: 'wds', description: 'Staff-like blades' },
  { id: 'spear', label: 'Spear', prefix: 'wsp', description: 'Polearms' },
  { id: 'slicer', label: 'Slicer', prefix: 'wsl', description: 'Thrown discs' },
  { id: 'handgun', label: 'Handgun', prefix: 'whg', description: 'Single target ranged' },
  { id: 'rifle', label: 'Rifle', prefix: 'wrf', description: 'Long range precision' },
  { id: 'machinegun', label: 'Machinegun', prefix: 'wmg', description: 'Rapid fire ranged' },
  { id: 'launcher', label: 'Launcher', prefix: 'wlc', description: 'Area explosive' },
  { id: 'bazooka', label: 'Bazooka', prefix: 'wba', description: 'Heavy explosive' },
  { id: 'gunblade', label: 'Gunblade', prefix: 'wgb', description: 'Hybrid melee/ranged' },
  { id: 'rod', label: 'Rod', prefix: 'wro', description: 'Technique casting' },
  { id: 'wand', label: 'Wand', prefix: 'wwa', description: 'Support casting' },
  { id: 'shield', label: 'Shield', prefix: 'wsh', description: 'Defensive off-hand' },
  { id: 'mag', label: 'Mag', prefix: 'wma', description: 'Companion devices' },
];

export const RARITY_MAP: Record<string, { label: string; color: string }> = {
  'c': { label: 'Common', color: '#888888' },
  'h': { label: 'Uncommon', color: '#4a9eff' },
  'n': { label: 'Rare', color: '#ffcc00' },
  'r': { label: 'Very Rare', color: '#ff4444' },
};

export function getWeaponCategory(weaponId: string): WeaponCategory | null {
  const id = weaponId.toLowerCase();
  return WEAPON_CATEGORIES.find(cat => id.startsWith(cat.prefix)) || null;
}

export function getWeaponRarity(weaponId: string): { label: string; color: string } {
  const id = weaponId.toLowerCase();
  const rarityChar = id.charAt(3);
  return RARITY_MAP[rarityChar] || { label: 'Unknown', color: '#666666' };
}

export function getWeaponGlbPath(weaponId: string, variant: string): string {
  const id = weaponId.toLowerCase();
  return assetUrl(`/weapons/${id}/${id}/${variant}/${variant}.glb`);
}

export function getWeaponTexturePath(weaponId: string, variant: string): string {
  const id = weaponId.toLowerCase();
  return assetUrl(`/weapons/${id}/${id}/${variant}/${variant}.png`);
}

export function getWeaponInfoPath(weaponId: string): string {
  const id = weaponId.toLowerCase();
  return assetUrl(`/weapons/${id}/info.json`);
}

export const ALL_WEAPON_IDS = [
  'wbac01', 'wbac02', 'wbah01', 'wbar01', 'wbar02', 'wbar03',
  'wclc01', 'wclh01', 'wclh02', 'wclr01', 'wclr02', 'wclr03', 'wclr04',
  'wdac01', 'wdah01', 'wdan01', 'wdar01', 'wdar02', 'wdar03',
  'wdsc01', 'wdsn01', 'wdsn02', 'wdsn03', 'wdsr01', 'wdsr02', 'wdsr03',
  'wgbc01', 'wgbh01', 'wgbn01', 'wgbr01', 'wgbr02', 'wgbr03', 'wgbr04',
  'whgc01', 'whgh01', 'whgn01', 'whgn02', 'whgr01', 'whgr02', 'whgr03', 'whgr04', 'whgr05',
  'wlcc01', 'wlcn01', 'wlcn02', 'wlcr01', 'wlcr02', 'wlcr03',
  'wmgc01', 'wmgh01', 'wmgh02', 'wmgr01', 'wmgr02', 'wmgr03', 'wmgr04',
  'wmaa1', 'wmaa2', 'wmaa3', 'wmaa4', 'wmab2', 'wmab3', 'wmab4',
  'wmac2', 'wmac3', 'wmac4', 'wmad2', 'wmad3', 'wmad4', 'wmae5',
  'wrfc01', 'wrfh01', 'wrfn01', 'wrfr01', 'wrfr02', 'wrfr03', 'wrfr04', 'wrfr05', 'wrfr06',
  'wroh01', 'wron01', 'wron02', 'wror01', 'wror02', 'wror03', 'wror04', 'wror05', 'wror06',
  'wsac01', 'wsah01', 'wsan01', 'wsan02', 'wsar01', 'wsar02', 'wsar03', 'wsar04', 'wsar06',
  'wshh01', 'wshh02', 'wshn01', 'wshr01', 'wshr02', 'wshr03', 'wshr04', 'wshr05', 'wshr06', 'wshr07',
  'wslc01', 'wslc02', 'wsln01', 'wslr01', 'wslr02', 'wslr03', 'wslr04', 'wslr05',
  'wspc01', 'wsph01', 'wsph02', 'wspr01', 'wspr02', 'wspr03', 'wspr04',
  'wswc01', 'wswh01', 'wswn01', 'wswr01', 'wswr02', 'wswr03', 'wswr04', 'wswr05',
  'wwac01', 'wwah01', 'wwan01', 'wwar01', 'wwar02', 'wwar03', 'wwar04', 'wwar05', 'wwar06',
];

export function getWeaponsByCategory(): Map<string, string[]> {
  const grouped = new Map<string, string[]>();
  for (const category of WEAPON_CATEGORIES) {
    grouped.set(category.id, []);
  }
  grouped.set('other', []);
  for (const weaponId of ALL_WEAPON_IDS) {
    const category = getWeaponCategory(weaponId);
    if (category) {
      grouped.get(category.id)?.push(weaponId);
    } else {
      grouped.get('other')?.push(weaponId);
    }
  }
  return grouped;
}
