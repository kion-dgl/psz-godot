export interface OfficeLayoutData {
  npcPosition: [number, number, number];
  npcRotationY: number;
  npcScale: number;
  roomScale: number;
  doorTrigger: { position: [number, number, number]; size: [number, number, number] };
  spawnPoint: { position: [number, number, number]; rotationY: number };
}

export type PlacementMode = 'none' | 'npc' | 'door' | 'spawn';
