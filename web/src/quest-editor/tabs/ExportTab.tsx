/**
 * ExportTab — JSON export with validation
 *
 * Two formats:
 * 1. Quest Layout JSON — the QuestProject data, re-importable
 * 2. Godot Quest JSON — cell format matching grid_generator output
 *
 * Plus: Import Godot Quest JSON back into a QuestProject for editing.
 */

import { useState, useCallback, useMemo, useRef } from 'react';
import type { QuestProject, QuestSection, ValidationIssue, EditorGridCell, CellObject, SectionType } from '../types';
import { getProjectSections } from '../types';
import { AREA_KEY_TO_ID } from '../constants';
import {
  getOriginalGates,
  getRotatedGates,
  getNeighbor,
  isValidPos,
  oppositeDirection,
  getStageConfig,
  getStageSuffix,
} from '../hooks/useStageConfigs';

interface ExportTabProps {
  project: QuestProject;
  setProject?: (project: QuestProject) => void;
}

const AREA_ID_TO_KEY: Record<string, string> = Object.fromEntries(
  Object.entries(AREA_KEY_TO_ID).map(([k, v]) => [v, k])
);

// ============================================================================
// Export: QuestProject → Godot Quest JSON
// ============================================================================

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
        if (obj.npc_id) exported.npc_id = obj.npc_id;
        if (obj.npc_name) exported.npc_name = obj.npc_name;
        if (obj.trigger_id) exported.trigger_id = obj.trigger_id;
        if (obj.dialog && obj.dialog.length > 0) exported.dialog = obj.dialog;
        return exported;
      });
    }

    cells.push(cellData);
  }

  cells.sort((a: any, b: any) => (a.path_order ?? 999) - (b.path_order ?? 999));
  return cells;
}

function projectToGodotQuest(project: QuestProject): object {
  const projectSections = getProjectSections(project);

  const godotSections = projectSections.map(sec => {
    const cells = exportSectionCells(
      sec.cells, sec.startPos, sec.endPos, sec.keyLinks, sec.gridSize
    );
    return {
      type: sec.type,
      area: sec.variant,
      start_pos: sec.startPos || '',
      end_pos: sec.endPos || '',
      cells,
    };
  });

  return {
    id: project.id,
    name: project.name,
    description: project.metadata?.description || '',
    area_id: AREA_KEY_TO_ID[project.areaKey] || project.areaKey,
    sections: godotSections,
  };
}

/** BFS from startPos to assign path_order (legacy, wraps section version) */
function buildPathOrder(project: QuestProject): Map<string, number> {
  return buildSectionPathOrder(project.cells, project.startPos, project.gridSize);
}

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

// ============================================================================
// Import: Godot Quest JSON → QuestProject
// ============================================================================

function importGodotSection(section: any): QuestSection {
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
      role: cell.is_end ? 'boss' : cell.is_start ? 'transit' : 'guard',
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
        if (obj.npc_id) co.npc_id = obj.npc_id;
        if (obj.npc_name) co.npc_name = obj.npc_name;
        if (obj.trigger_id) co.trigger_id = obj.trigger_id;
        if (obj.dialog && Array.isArray(obj.dialog)) co.dialog = obj.dialog;
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

  return {
    type: sectionType,
    variant: section.area || 'a',
    gridSize: Math.max(3, Math.max(maxRow, maxCol) + 1),
    cells,
    startPos,
    endPos,
    keyLinks,
  };
}

function godotQuestToProject(quest: any): QuestProject {
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
      questType: 'exploration',
      difficulty: 'normal',
      recommendedLevel: 1,
    },
    cellContents: {},
    lastModified: new Date().toISOString(),
    version: 1,
  };

  // Only set sections[] if there are multiple sections
  if (importedSections.length > 1) {
    result.sections = importedSections;
  }

  return result;
}

// ============================================================================
// Validation
// ============================================================================

/** Validate a single section */
function validateSection(
  cells: Record<string, EditorGridCell>,
  startPos: string | null,
  endPos: string | null,
  gridSize: number,
  sectionLabel: string,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  if (!startPos) issues.push({ severity: 'error', message: `${sectionLabel}: No start cell` });
  if (!endPos) issues.push({ severity: 'error', message: `${sectionLabel}: No end cell` });
  if (Object.keys(cells).length === 0) issues.push({ severity: 'error', message: `${sectionLabel}: No cells` });

  for (const [pos, cell] of Object.entries(cells)) {
    const [row, col] = pos.split(',').map(Number);
    const gates = getRotatedGates(cell.stageName, cell.rotation ?? 0);

    for (const dir of gates) {
      const [nr, nc] = getNeighbor(row, col, dir);
      if (!isValidPos(nr, nc, gridSize)) continue;

      const neighborKey = `${nr},${nc}`;
      const neighbor = cells[neighborKey];

      if (neighbor) {
        const neighborGates = getRotatedGates(neighbor.stageName, neighbor.rotation ?? 0);
        if (!neighborGates.has(oppositeDirection(dir))) {
          issues.push({
            severity: 'error',
            message: `${sectionLabel}: Orphan gate: ${pos} (${dir}) → ${neighborKey}`,
            cellPos: pos,
          });
        }
      }
    }
  }

  return issues;
}

/** Validate for export */
function validateForExport(project: QuestProject): ValidationIssue[] {
  const sections = getProjectSections(project);
  const issues: ValidationIssue[] = [];

  for (let i = 0; i < sections.length; i++) {
    const sec = sections[i];
    const label = sections.length > 1 ? `Section ${i + 1} (${sec.variant.toUpperCase()})` : '';
    issues.push(...validateSection(sec.cells, sec.startPos, sec.endPos, sec.gridSize, label));
  }

  return issues;
}

// ============================================================================
// Component
// ============================================================================

export default function ExportTab({ project, setProject }: ExportTabProps) {
  const [copyStatus, setCopyStatus] = useState('');
  const [importText, setImportText] = useState('');
  const [importError, setImportError] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  const issues = useMemo(() => validateForExport(project), [project]);
  const hasErrors = issues.some(i => i.severity === 'error');

  const layoutJson = useMemo(() => JSON.stringify(project, null, 2), [project]);
  const godotJson = useMemo(() => {
    if (hasErrors) return '';
    return JSON.stringify(projectToGodotQuest(project), null, 2);
  }, [project, hasErrors]);

  const copyToClipboard = useCallback(async (text: string, label: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopyStatus(`${label} copied!`);
      setTimeout(() => setCopyStatus(''), 2000);
    } catch {
      setCopyStatus('Copy failed');
      setTimeout(() => setCopyStatus(''), 2000);
    }
  }, []);

  const downloadJson = useCallback((text: string, filename: string) => {
    const blob = new Blob([text], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }, []);

  const handleImport = useCallback((jsonText: string) => {
    setImportError('');
    try {
      const parsed = JSON.parse(jsonText);

      // Detect format: Godot quest has "sections", QuestProject has "cells"
      if (parsed.sections && Array.isArray(parsed.sections)) {
        // Godot quest JSON → convert to QuestProject
        const imported = godotQuestToProject(parsed);
        if (setProject) {
          setProject(imported);
          setCopyStatus('Imported Godot quest!');
          setTimeout(() => setCopyStatus(''), 2000);
          setImportText('');
        } else {
          setImportError('Import not available (setProject not provided)');
        }
      } else if (parsed.cells && parsed.areaKey) {
        // Already a QuestProject
        if (setProject) {
          setProject(parsed as QuestProject);
          setCopyStatus('Imported quest project!');
          setTimeout(() => setCopyStatus(''), 2000);
          setImportText('');
        } else {
          setImportError('Import not available (setProject not provided)');
        }
      } else {
        setImportError('Unrecognized JSON format. Expected Godot quest (with "sections") or QuestProject (with "cells").');
      }
    } catch (e) {
      setImportError(`Parse error: ${e}`);
    }
  }, [setProject]);

  const handleFileImport = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === 'string') {
        handleImport(reader.result);
      }
    };
    reader.readAsText(file);
    // Reset so same file can be re-selected
    if (fileInputRef.current) fileInputRef.current.value = '';
  }, [handleImport]);

  const buttonStyle = {
    padding: '8px 16px', background: '#555588', border: 'none',
    borderRadius: '6px', color: '#fff', fontSize: '12px', cursor: 'pointer',
  };

  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      overflow: 'auto', padding: '24px', gap: '24px',
    }}>
      {/* Import Quest JSON */}
      {setProject && (
        <div>
          <div style={{
            fontSize: '14px', fontWeight: 600, color: '#fff', marginBottom: '8px',
            display: 'flex', alignItems: 'center', gap: '8px',
          }}>
            Import Quest JSON
            <span style={{ fontSize: '11px', color: '#888', fontWeight: 400 }}>
              (Godot quest or QuestProject format)
            </span>
          </div>
          <div style={{ display: 'flex', gap: '8px', marginBottom: '8px' }}>
            <button
              onClick={() => handleImport(importText)}
              disabled={!importText.trim()}
              style={{
                ...buttonStyle,
                background: !importText.trim() ? '#444' : '#448844',
                cursor: !importText.trim() ? 'not-allowed' : 'pointer',
              }}
            >
              Import from Text
            </button>
            <input
              ref={fileInputRef}
              type="file"
              accept=".json"
              onChange={handleFileImport}
              style={{ display: 'none' }}
            />
            <button
              onClick={() => fileInputRef.current?.click()}
              style={buttonStyle}
            >
              Import from File
            </button>
          </div>
          <textarea
            value={importText}
            onChange={(e) => setImportText(e.target.value)}
            placeholder="Paste Godot quest JSON or QuestProject JSON here..."
            style={{
              width: '100%',
              height: '80px',
              background: '#111',
              border: '1px solid #333',
              borderRadius: '6px',
              padding: '8px',
              fontSize: '11px',
              color: '#aaa',
              fontFamily: 'monospace',
              resize: 'vertical',
            }}
          />
          {importError && (
            <div style={{ color: '#ff8888', fontSize: '12px', marginTop: '4px' }}>
              {importError}
            </div>
          )}
        </div>
      )}

      {/* Validation */}
      <div>
        <div style={{
          fontSize: '14px', fontWeight: 600, color: '#fff', marginBottom: '8px',
        }}>
          Validation
        </div>
        {issues.length === 0 ? (
          <div style={{ color: '#88ff88', fontSize: '13px' }}>
            No issues found — ready to export
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
            {issues.map((issue, i) => (
              <div key={i} style={{
                padding: '4px 8px',
                fontSize: '12px',
                color: issue.severity === 'error' ? '#ff8888' :
                       issue.severity === 'warning' ? '#ffcc66' : '#8888ff',
              }}>
                {issue.severity === 'error' ? '[ERROR]' : issue.severity === 'warning' ? '[WARN]' : '[INFO]'} {issue.message}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Status */}
      {copyStatus && (
        <div style={{ color: '#88ff88', fontSize: '13px', textAlign: 'center' }}>
          {copyStatus}
        </div>
      )}

      {/* Godot Quest JSON */}
      <div>
        <div style={{
          fontSize: '14px', fontWeight: 600, color: '#fff', marginBottom: '8px',
          display: 'flex', alignItems: 'center', gap: '8px',
        }}>
          Godot Quest JSON
          <span style={{ fontSize: '11px', color: '#888', fontWeight: 400 }}>
            (copy to psz-godot/data/quests/)
          </span>
        </div>
        <div style={{ display: 'flex', gap: '8px', marginBottom: '8px' }}>
          <button
            onClick={() => copyToClipboard(godotJson, 'Godot quest')}
            disabled={hasErrors}
            style={{
              ...buttonStyle,
              background: hasErrors ? '#444' : '#448844',
              cursor: hasErrors ? 'not-allowed' : 'pointer',
            }}
          >
            Copy to Clipboard
          </button>
          <button
            onClick={() => {
              const id = (project.name || 'quest').toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '');
              downloadJson(godotJson, `${id}.json`);
            }}
            disabled={hasErrors}
            style={{
              ...buttonStyle,
              background: hasErrors ? '#444' : buttonStyle.background,
              cursor: hasErrors ? 'not-allowed' : 'pointer',
            }}
          >
            Download
          </button>
        </div>
        {!hasErrors && godotJson && (
          <pre style={{
            background: '#111',
            border: '1px solid #333',
            borderRadius: '6px',
            padding: '12px',
            fontSize: '10px',
            color: '#aaa',
            maxHeight: '300px',
            overflow: 'auto',
            fontFamily: 'monospace',
          }}>
            {godotJson}
          </pre>
        )}
      </div>

      {/* Quest Layout JSON */}
      <div>
        <div style={{
          fontSize: '14px', fontWeight: 600, color: '#fff', marginBottom: '8px',
          display: 'flex', alignItems: 'center', gap: '8px',
        }}>
          Quest Layout JSON
          <span style={{ fontSize: '11px', color: '#888', fontWeight: 400 }}>
            (re-importable by editor)
          </span>
        </div>
        <div style={{ display: 'flex', gap: '8px', marginBottom: '8px' }}>
          <button
            onClick={() => copyToClipboard(layoutJson, 'Layout')}
            style={buttonStyle}
          >
            Copy to Clipboard
          </button>
          <button
            onClick={() => downloadJson(layoutJson, `quest-${project.name.toLowerCase().replace(/\s+/g, '-')}.json`)}
            style={buttonStyle}
          >
            Download
          </button>
        </div>
        <pre style={{
          background: '#111',
          border: '1px solid #333',
          borderRadius: '6px',
          padding: '12px',
          fontSize: '10px',
          color: '#aaa',
          maxHeight: '300px',
          overflow: 'auto',
          fontFamily: 'monospace',
        }}>
          {layoutJson}
        </pre>
      </div>

    </div>
  );
}
