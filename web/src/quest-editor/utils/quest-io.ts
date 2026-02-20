/**
 * Quest I/O utilities — shared import/export logic for Godot quest JSON
 *
 * Extracted from ExportTab so both QuestHome and ExportTab can use them.
 */

import type { QuestProject, QuestSection, EditorGridCell, CellObject, SectionType } from '../types';
import { getProjectSections } from '../types';
import { AREA_KEY_TO_ID } from '../constants';
import {
  getRotatedGates,
  getNeighbor,
  isValidPos,
} from '../hooks/useStageConfigs';

const AREA_ID_TO_KEY: Record<string, string> = Object.fromEntries(
  Object.entries(AREA_KEY_TO_ID).map(([k, v]) => [v, k])
);

// ============================================================================
// Export: QuestProject → Godot Quest JSON
// ============================================================================

/** BFS from startPos to assign path_order within a section */
function buildSectionPathOrder(
  cells: Record<string, EditorGridCell>,
  startPos: string | null,
  _gridSize: number,
): Map<string, number> {
  const order = new Map<string, number>();
  if (!startPos || !cells[startPos]) return order;

  const visited = new Set<string>();
  const queue: string[] = [startPos];
  visited.add(startPos);
  let idx = 0;

  while (queue.length > 0) {
    const pos = queue.shift()!;
    order.set(pos, idx++);

    const cell = cells[pos];
    if (!cell) continue;

    const [row, col] = pos.split(',').map(Number);
    const gates = getRotatedGates(cell.stageName, cell.rotation ?? 0);

    for (const dir of gates) {
      const [nr, nc] = getNeighbor(row, col, dir);
      const nk = `${nr},${nc}`;
      if (!visited.has(nk) && cells[nk]) {
        visited.add(nk);
        queue.push(nk);
      }
    }
  }

  return order;
}

/** Export a single section's cells to Godot format */
function exportSectionCells(
  sectionCells: Record<string, EditorGridCell>,
  sectionStartPos: string | null,
  sectionEndPos: string | null,
  sectionKeyLinks: Record<string, string>,
  sectionGridSize: number,
): object[] {
  const cells: object[] = [];
  const pathOrder = buildSectionPathOrder(sectionCells, sectionStartPos, sectionGridSize);

  for (const [pos, cell] of Object.entries(sectionCells)) {
    const [row, col] = pos.split(',').map(Number);
    const gates = getRotatedGates(cell.stageName, cell.rotation ?? 0);

    const connections: Record<string, string> = {};
    for (const worldDir of gates) {
      const [nr, nc] = getNeighbor(row, col, worldDir);
      const nk = `${nr},${nc}`;
      if (sectionCells[nk]) {
        connections[worldDir] = nk;
      }
    }

    let warpEdge = '';
    if (sectionEndPos === pos) {
      for (const worldDir of gates) {
        const [nr, nc] = getNeighbor(row, col, worldDir);
        if (!isValidPos(nr, nc, sectionGridSize) || !sectionCells[`${nr},${nc}`]) {
          warpEdge = worldDir;
          break;
        }
      }
    }

    let keyGateDirection = '';
    if (pos in sectionKeyLinks && cell.lockedGate) {
      keyGateDirection = cell.lockedGate;
    }

    const cellData: Record<string, unknown> = {
      pos,
      stage_id: cell.stageName,
      rotation: cell.rotation ?? 0,
      connections,
      is_start: sectionStartPos === pos,
      is_end: sectionEndPos === pos,
      is_branch: Object.keys(connections).length > 2,
      has_key: Object.values(sectionKeyLinks).includes(pos),
      key_for_cell: Object.entries(sectionKeyLinks).find(([_, v]) => v === pos)?.[0] || '',
      is_key_gate: pos in sectionKeyLinks,
      key_gate_direction: keyGateDirection,
      warp_edge: warpEdge,
      path_order: pathOrder.get(pos) ?? -1,
    };

    if (cell.keyPosition) {
      cellData.key_position = cell.keyPosition;
    }

    if (cell.objects && cell.objects.length > 0) {
      cellData.objects = cell.objects.map(obj => {
        const exported: Record<string, unknown> = {
          type: obj.type,
          position: obj.position,
        };
        if (obj.rotation) exported.rotation = obj.rotation;
        if (obj.enemy_id) exported.enemy_id = obj.enemy_id;
        if (obj.link_id) exported.link_id = obj.link_id;
        if (obj.wave && obj.wave > 1) exported.wave = obj.wave;
        if (obj.text !== undefined && obj.text !== '') exported.text = obj.text;
        if (obj.prop_path) exported.prop_path = obj.prop_path;
        if (obj.prop_scale && obj.prop_scale !== 1.0) exported.prop_scale = obj.prop_scale;
        if (obj.npc_id) exported.npc_id = obj.npc_id;
        if (obj.npc_name) exported.npc_name = obj.npc_name;
        if (obj.trigger_id) exported.trigger_id = obj.trigger_id;
        if (obj.trigger_size) exported.trigger_size = obj.trigger_size;
        if (obj.trigger_condition && obj.trigger_condition !== 'enter') exported.trigger_condition = obj.trigger_condition;
        if (obj.actions && obj.actions.length > 0) exported.actions = obj.actions;
        if (obj.dialog && obj.dialog.length > 0) exported.dialog = obj.dialog;
        if (obj.animation) exported.animation = obj.animation;
        if (obj.animation_frame !== undefined) exported.animation_frame = obj.animation_frame;
        if (obj.spawn_condition && obj.spawn_condition !== 'immediate') exported.spawn_condition = obj.spawn_condition;
        if (obj.quest_item_id) exported.item_id = obj.quest_item_id;
        if (obj.quest_item_label) exported.item_label = obj.quest_item_label;
        return exported;
      }).filter(obj => obj.type !== 'warp_dest');
    }

    cells.push(cellData);
  }

  cells.sort((a: any, b: any) => (a.path_order ?? 999) - (b.path_order ?? 999));
  return cells;
}

export function projectToGodotQuest(project: QuestProject): object {
  const projectSections = getProjectSections(project);

  const godotSections = projectSections.map(sec => {
    // Auto-fix start/end for single-cell sections (transition/boss)
    let { startPos, endPos } = sec;
    const cellKeys = Object.keys(sec.cells);
    if (cellKeys.length === 1 && (!startPos || !endPos)) {
      startPos = cellKeys[0];
      endPos = cellKeys[0];
    }

    const cells = exportSectionCells(
      sec.cells, startPos, endPos, sec.keyLinks, sec.gridSize
    );
    const section: Record<string, unknown> = {
      type: sec.type,
      area: sec.variant,
      start_pos: startPos || '',
      end_pos: endPos || '',
      cells,
    };
    if (sec.entryDirection) section.entry_direction = sec.entryDirection;
    if (sec.exitDirection) section.exit_direction = sec.exitDirection;
    if (sec.warpRequires && sec.warpRequires.length > 0) section.warp_requires = sec.warpRequires;
    return section;
  });

  // Warp link resolution: scan all sections for warp_dest objects, then inject
  // warp_section/warp_cell/warp_position into matching warp objects
  const warpDestMap = new Map<string, { sectionIndex: number; cellPos: string; position: [number, number, number] }>();
  for (let si = 0; si < projectSections.length; si++) {
    for (const [cellPos, cell] of Object.entries(projectSections[si].cells)) {
      for (const obj of cell.objects || []) {
        if (obj.type === 'warp_dest' && obj.link_id) {
          warpDestMap.set(obj.link_id, { sectionIndex: si, cellPos, position: obj.position });
        }
      }
    }
  }
  for (const godotSection of godotSections) {
    for (const cell of (godotSection as any).cells) {
      if (!cell.objects) continue;
      for (const obj of cell.objects) {
        if (obj.type === 'warp' && obj.link_id) {
          const dest = warpDestMap.get(obj.link_id);
          if (dest) {
            obj.warp_section = dest.sectionIndex;
            obj.warp_cell = dest.cellPos;
            obj.warp_position = dest.position;
          }
        }
      }
    }
  }

  const quest: Record<string, unknown> = {
    id: project.id,
    name: project.name,
    description: project.metadata?.description || '',
    area_id: AREA_KEY_TO_ID[project.areaKey] || project.areaKey,
    sections: godotSections,
  };

  if (project.metadata?.companions && project.metadata.companions.length > 0) {
    quest.companions = project.metadata.companions;
  }

  if (project.metadata?.cityDialog && project.metadata.cityDialog.length > 0) {
    // Flatten scenes back to Godot's flat city_dialog format
    quest.city_dialog = project.metadata.cityDialog.flatMap(scene =>
      (scene.dialog || []).map(page => ({ speaker: page.speaker, text: page.text }))
    );
  }

  if (project.metadata?.objectives && project.metadata.objectives.length > 0) {
    quest.objectives = project.metadata.objectives;
  }

  return quest;
}

// ============================================================================
// Import: Godot Quest JSON → QuestProject
// ============================================================================

export function importGodotSection(section: any): QuestSection {
  const cells: Record<string, EditorGridCell> = {};
  let startPos: string | null = null;
  let endPos: string | null = null;
  const keyLinks: Record<string, string> = {};
  let maxRow = 0, maxCol = 0;

  for (const cell of section.cells || []) {
    const [r, c] = cell.pos.split(',').map(Number);
    maxRow = Math.max(maxRow, r);
    maxCol = Math.max(maxCol, c);
    const editorCell: EditorGridCell = {
      stageName: cell.stage_id,
      rotation: cell.rotation || undefined,
      lockedGate: cell.key_gate_direction || undefined,
      manual: true,
    };
    if (cell.key_position && Array.isArray(cell.key_position)) {
      editorCell.keyPosition = cell.key_position as [number, number, number];
    }
    if (cell.objects && Array.isArray(cell.objects)) {
      editorCell.objects = cell.objects.map((obj: any, idx: number) => {
        const co: CellObject = {
          id: obj.id || `${obj.type}_${idx}`,
          type: obj.type,
          position: obj.position as [number, number, number],
        };
        if (obj.rotation) co.rotation = obj.rotation;
        if (obj.enemy_id) co.enemy_id = obj.enemy_id;
        if (obj.link_id) co.link_id = obj.link_id;
        if (obj.wave) co.wave = obj.wave;
        if (obj.text) co.text = obj.text;
        if (obj.prop_path) co.prop_path = obj.prop_path;
        if (obj.prop_scale) co.prop_scale = obj.prop_scale;
        if (obj.npc_id) co.npc_id = obj.npc_id;
        if (obj.npc_name) co.npc_name = obj.npc_name;
        if (obj.trigger_id) co.trigger_id = obj.trigger_id;
        if (obj.trigger_size && Array.isArray(obj.trigger_size)) co.trigger_size = obj.trigger_size as [number, number, number];
        if (obj.trigger_condition) co.trigger_condition = obj.trigger_condition;
        if (obj.actions && Array.isArray(obj.actions)) co.actions = obj.actions;
        if (obj.dialog && Array.isArray(obj.dialog)) co.dialog = obj.dialog;
        if (obj.animation) co.animation = obj.animation;
        if (obj.animation_frame !== undefined) co.animation_frame = obj.animation_frame;
        if (obj.spawn_condition) co.spawn_condition = obj.spawn_condition;
        if (obj.item_id) co.quest_item_id = obj.item_id;
        if (obj.item_label) co.quest_item_label = obj.item_label;
        // warp_section, warp_cell, warp_position are export-only (resolved at export time) — skip on import
        return co;
      });
    }
    cells[cell.pos] = editorCell;
    if (cell.is_start) startPos = cell.pos;
    if (cell.is_end) endPos = cell.pos;
    if (cell.is_key_gate && cell.key_for_cell) {
      keyLinks[cell.pos] = cell.key_for_cell;
    }
  }

  const sectionType: SectionType = section.type === 'transition' ? 'transition'
    : section.type === 'boss' ? 'boss' : 'grid';

  const result: QuestSection = {
    type: sectionType,
    variant: section.area || 'a',
    gridSize: Math.max(3, Math.max(maxRow, maxCol) + 1),
    cells,
    startPos,
    endPos,
    keyLinks,
  };
  if (section.entry_direction) result.entryDirection = section.entry_direction;
  if (section.exit_direction) result.exitDirection = section.exit_direction;
  if (section.warp_requires && Array.isArray(section.warp_requires)) result.warpRequires = section.warp_requires;
  return result;
}

/** Convert Godot city_dialog (flat pages) to editor CityDialogScene format.
 *  Groups consecutive pages by speaker into scenes. */
function importCityDialog(raw: any): Array<{ npc_id: string; npc_name: string; dialog: Array<{ speaker: string; text: string }> }> {
  if (!Array.isArray(raw) || raw.length === 0) return [];

  // If already in scene format (has dialog array), pass through
  if (raw[0].dialog && Array.isArray(raw[0].dialog)) {
    return raw;
  }

  // Flat pages: group consecutive pages by speaker into scenes
  const scenes: Array<{ npc_id: string; npc_name: string; dialog: Array<{ speaker: string; text: string }> }> = [];
  let currentScene: typeof scenes[0] | null = null;

  for (const page of raw) {
    const speaker = page.speaker || '';
    if (!currentScene || currentScene.npc_name !== speaker) {
      currentScene = { npc_id: '', npc_name: speaker, dialog: [] };
      scenes.push(currentScene);
    }
    currentScene.dialog.push({ speaker: page.speaker || '', text: page.text || '' });
  }

  return scenes;
}

export function godotQuestToProject(quest: any): QuestProject {
  const rawSections = quest.sections || [];
  const importedSections: QuestSection[] = rawSections.map(importGodotSection);
  const firstSection = importedSections[0] || { variant: 'a', gridSize: 5, cells: {}, startPos: null, endPos: null, keyLinks: {} };

  const areaKey = AREA_ID_TO_KEY[quest.area_id] || 'valley';

  const result: QuestProject = {
    id: quest.id || crypto.randomUUID(),
    name: quest.name || 'Imported Quest',
    areaKey,
    variant: firstSection.variant,
    gridSize: firstSection.gridSize,
    cells: firstSection.cells,
    startPos: firstSection.startPos,
    endPos: firstSection.endPos,
    keyLinks: firstSection.keyLinks,
    metadata: {
      questName: quest.name || '',
      description: quest.description || '',
      companions: Array.isArray(quest.companions) ? quest.companions : [],
      cityDialog: importCityDialog(quest.city_dialog),
      objectives: Array.isArray(quest.objectives) ? quest.objectives : [],
    },
    cellContents: {},
    lastModified: new Date().toISOString(),
    version: 1,
  };

  if (importedSections.length > 1) {
    result.sections = importedSections;
  }

  return result;
}
