// Element components for traversal

// Gates
export { default as Gate, gateMeta, type GateState } from './Gate';
export { default as KeyGate, keyGateMeta, type KeyGateState } from './KeyGate';

// Fences
export { default as Fence, fenceMeta, type FenceState } from './Fence';
export { default as Fence4, fence4Meta, type Fence4State } from './Fence4';

// Switches
export { default as InteractSwitch, interactSwitchMeta, type SwitchState } from './InteractSwitch';
export { default as StepSwitch, stepSwitchMeta, type StepSwitchState } from './StepSwitch';
export { default as RemoteSwitch, remoteSwitchMeta, type RemoteSwitchState } from './RemoteSwitch';

// Pickups
export { default as Key, keyMeta, type KeyState } from './Key';
export { default as MessagePack, messagePackMeta, type MessagePackState } from './MessagePack';

// Drops
export { default as DropMeseta, dropMesetaMeta, type DropMesetaState } from './DropMeseta';
export { default as DropWeapon, dropWeaponMeta, type DropWeaponState } from './DropWeapon';
export { default as DropArmor, dropArmorMeta, type DropArmorState } from './DropArmor';
export { default as DropRare, dropRareMeta, type DropRareState } from './DropRare';
export { default as DropItem, dropItemMeta, type DropItemState } from './DropItem';

// Indicators
export { default as Waypoint, waypointMeta, type WaypointState } from './Waypoint';

// Containers
export { default as Box, boxMeta, type BoxState } from './Box';
export { default as RareBox, rareBoxMeta, type RareBoxState } from './RareBox';

// Walls
export { default as Wall, wallMeta, type WallState } from './Wall';

// Warps
export { default as StartWarp, startWarpMeta, type StartWarpState } from './StartWarp';
export { default as AreaWarp, areaWarpMeta, type AreaWarpState } from './AreaWarp';

// NPCs
export { default as NpcSarisa, npcSarisaMeta, type NpcSarisaState } from './NpcSarisa';
export { default as NpcKai, npcKaiMeta, type NpcKaiState } from './NpcKai';

// Story Objects
export { default as DropshipCrash, dropshipCrashMeta, type DropshipCrashState } from './DropshipCrash';

export type { ElementProps, StoryMeta } from './types';
