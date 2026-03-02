export interface NpcSlot {
  position: [number, number, number];
  rotationY: number;
}

export interface OfficeLayoutData {
  npcPosition: [number, number, number];
  npcRotationY: number;
  npcScale: number;
  roomScale: number;
  doorTrigger: { position: [number, number, number]; size: [number, number, number] };
  spawnPoint: { position: [number, number, number]; rotationY: number };
  /** Named NPC positions for quest briefing scenes */
  npcPositions: Record<string, NpcSlot>;
}

export type PlacementMode = 'none' | 'npc' | 'door' | 'spawn' | 'pos_1' | 'pos_2';
