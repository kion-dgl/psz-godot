// useQuestObjects — load a quest plan and surface the per-cell quest objects
// (switches, fences, key drops, NPCs, dialog triggers) for whichever stage
// the editor is currently looking at. Used by QuestObjectOverlay to render
// markers on the 3D floor view so the user knows where to drop waypoints.

import { useEffect, useState } from 'react';
import { assetUrl } from '../utils/assets';

export type QuestObjectKind = 'switch' | 'fence' | 'key_drop' | 'npc' | 'dialog' | 'story_prop';

export interface QuestObjectMarker {
  kind: QuestObjectKind;
  position: [number, number, number];
  cellPos: string;
  label: string;
  linkId?: string;
}

interface QuestCell {
  pos: string;
  stageId: string;
  switches?: { position: [number, number, number]; linkId?: string }[];
  fences?: { position: [number, number, number]; linkId?: string }[];
  keyDrop?: { position?: [number, number, number]; targetCell?: string } | null;
  npcs?: { npcId: string; position: [number, number, number]; animation?: string | null }[];
  storyProps?: { propPath: string; position: [number, number, number] }[];
  dialogTriggers?: {
    position: [number, number, number];
    condition?: string | null;
    actions?: string[] | null;
  }[];
}

interface QuestPlan {
  questId: string;
  questName: string;
  areaId: string;
  sections: { type: string; area: string; cells: QuestCell[] }[];
}

/** Cache so flipping between stages doesn't re-fetch the same JSON. */
const cache = new Map<string, QuestPlan | null>();

async function loadQuestPlan(questId: string): Promise<QuestPlan | null> {
  if (cache.has(questId)) return cache.get(questId) ?? null;
  try {
    const resp = await fetch(assetUrl(`data/quest_plans/${questId}.json`));
    if (!resp.ok) {
      cache.set(questId, null);
      return null;
    }
    const data = (await resp.json()) as QuestPlan;
    cache.set(questId, data);
    return data;
  } catch {
    cache.set(questId, null);
    return null;
  }
}

/**
 * Returns the quest objects (switches / fences / key drops / NPCs / dialog
 * triggers / story props) for every cell in `questId` that uses `mapId`.
 * Empty when either is unset or the quest plan can't be fetched.
 */
export function useQuestObjects(questId: string | null, mapId: string): QuestObjectMarker[] {
  const [markers, setMarkers] = useState<QuestObjectMarker[]>([]);

  useEffect(() => {
    if (!questId) {
      setMarkers([]);
      return;
    }
    let cancelled = false;
    loadQuestPlan(questId).then((plan) => {
      if (cancelled) return;
      if (!plan) {
        setMarkers([]);
        return;
      }
      const out: QuestObjectMarker[] = [];
      for (const sect of plan.sections) {
        for (const cell of sect.cells) {
          if (cell.stageId !== mapId) continue;
          for (const sw of cell.switches ?? []) {
            out.push({ kind: 'switch', position: sw.position, cellPos: cell.pos, label: `switch ${cell.pos}${sw.linkId ? ` (${sw.linkId})` : ''}`, linkId: sw.linkId });
          }
          for (const fence of cell.fences ?? []) {
            out.push({ kind: 'fence', position: fence.position, cellPos: cell.pos, label: `fence ${cell.pos}${fence.linkId ? ` (${fence.linkId})` : ''}`, linkId: fence.linkId });
          }
          if (cell.keyDrop?.position) {
            out.push({ kind: 'key_drop', position: cell.keyDrop.position, cellPos: cell.pos, label: `key drop ${cell.pos}${cell.keyDrop.targetCell ? ` → ${cell.keyDrop.targetCell}` : ''}` });
          }
          for (const npc of cell.npcs ?? []) {
            out.push({ kind: 'npc', position: npc.position, cellPos: cell.pos, label: `${npc.npcId} ${cell.pos}` });
          }
          for (const prop of cell.storyProps ?? []) {
            out.push({ kind: 'story_prop', position: prop.position, cellPos: cell.pos, label: `${prop.propPath.split('/').pop()?.replace('.glb', '')} ${cell.pos}` });
          }
          for (const trig of cell.dialogTriggers ?? []) {
            out.push({ kind: 'dialog', position: trig.position, cellPos: cell.pos, label: `dialog ${cell.pos}${trig.condition ? ` (${trig.condition})` : ''}` });
          }
        }
      }
      setMarkers(out);
    });
    return () => {
      cancelled = true;
    };
  }, [questId, mapId]);

  return markers;
}
