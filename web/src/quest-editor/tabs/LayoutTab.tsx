/**
 * LayoutTab — Grid layout editing with toolbar, canvas, and inspector
 */

import { useState, useCallback } from 'react';
import type { QuestProject, EditorGridCell, ValidationIssue, Direction } from '../types';
import { generateGrid, type GenParams } from '../shared/grid-generation';
import GridCanvas from '../shared/GridCanvas';
import CellInspector from '../shared/CellInspector';
import StagePicker from '../shared/StagePicker';
import { getRotatedGates, getNeighbor, isValidPos, oppositeDirection } from '../hooks/useStageConfigs';

interface LayoutTabProps {
  project: QuestProject;
  onUpdateProject: (updater: (prev: QuestProject) => QuestProject) => void;
}

/** Validate the current layout and return issues */
function validateLayout(project: QuestProject): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  // Check for start/end
  if (!project.startPos) {
    issues.push({ severity: 'error', message: 'No start cell designated' });
  }
  if (!project.endPos) {
    issues.push({ severity: 'error', message: 'No end cell designated' });
  }

  // Check cell count
  const cellCount = Object.keys(project.cells).length;
  if (cellCount === 0) {
    issues.push({ severity: 'error', message: 'Grid is empty — no cells placed' });
    return issues;
  }

  // Check gate connections
  for (const [pos, cell] of Object.entries(project.cells)) {
    const [row, col] = pos.split(',').map(Number);
    const gates = getRotatedGates(cell.stageName, cell.rotation ?? 0);

    for (const dir of gates) {
      const [nr, nc] = getNeighbor(row, col, dir);

      if (!isValidPos(nr, nc, project.gridSize)) {
        // Gate to outside grid — warp candidate (info)
        issues.push({
          severity: 'info',
          message: `Gate at ${pos} points outside grid (${dir}) — warp candidate`,
          cellPos: pos,
        });
        continue;
      }

      const neighborKey = `${nr},${nc}`;
      const neighbor = project.cells[neighborKey];

      if (!neighbor) {
        // Gate to empty cell
        issues.push({
          severity: 'warning',
          message: `Gate at ${pos} (${dir}) leads to empty cell ${neighborKey}`,
          cellPos: pos,
        });
      } else {
        // Check for matching return gate
        const neighborGates = getRotatedGates(neighbor.stageName, neighbor.rotation ?? 0);
        if (!neighborGates.has(oppositeDirection(dir))) {
          issues.push({
            severity: 'error',
            message: `Orphan gate at ${pos} (${dir}) — neighbor ${neighborKey} has no return gate`,
            cellPos: pos,
          });
        }
      }
    }
  }

  // Check key-gate links
  for (const [gatePos, keyPos] of Object.entries(project.keyLinks)) {
    if (!project.cells[gatePos]) {
      issues.push({ severity: 'error', message: `Key-gate at ${gatePos} has no cell`, cellPos: gatePos });
    }
    if (!project.cells[keyPos]) {
      issues.push({ severity: 'error', message: `Key for gate ${gatePos} at ${keyPos} has no cell`, cellPos: keyPos });
    }
  }

  return issues;
}

export default function LayoutTab({ project, onUpdateProject }: LayoutTabProps) {
  const [selectedCell, setSelectedCell] = useState<string | null>(null);
  const [pickerTarget, setPickerTarget] = useState<string | null>(null);
  const [showGenDialog, setShowGenDialog] = useState(false);
  const [validationIssues, setValidationIssues] = useState<ValidationIssue[]>([]);
  const [genParams, setGenParams] = useState<GenParams>({
    gridSize: project.gridSize,
    usedCells: 8,
    keyGates: 1,
    branches: 2,
  });

  // Handle clicking an empty cell — open StagePicker
  const handleEmptyCellClick = useCallback((pos: string) => {
    setPickerTarget(pos);
    setSelectedCell(pos);
  }, []);

  // Handle clicking an occupied cell — select for inspector
  const handleCellSelect = useCallback((pos: string) => {
    setSelectedCell(pos);
  }, []);

  // Place a stage in a cell
  const handlePlaceStage = useCallback((stageName: string, rotation: number) => {
    if (!pickerTarget) return;
    onUpdateProject(prev => ({
      ...prev,
      cells: {
        ...prev.cells,
        [pickerTarget]: {
          stageName,
          rotation: rotation || undefined,
          role: 'transit',
          manual: true,
        },
      },
    }));
    setPickerTarget(null);
  }, [pickerTarget, onUpdateProject]);

  // Update a cell's properties
  const handleUpdateCell = useCallback((pos: string, updates: Partial<EditorGridCell>) => {
    onUpdateProject(prev => ({
      ...prev,
      cells: {
        ...prev.cells,
        [pos]: { ...prev.cells[pos], ...updates, manual: true },
      },
    }));
  }, [onUpdateProject]);

  // Set start cell
  const handleSetStart = useCallback((pos: string) => {
    onUpdateProject(prev => ({
      ...prev,
      startPos: prev.startPos === pos ? null : pos,
    }));
  }, [onUpdateProject]);

  // Set end cell
  const handleSetEnd = useCallback((pos: string) => {
    onUpdateProject(prev => ({
      ...prev,
      endPos: prev.endPos === pos ? null : pos,
    }));
  }, [onUpdateProject]);

  // Toggle key on cell — links this cell as key holder for an unlinked gate
  const handleToggleKey = useCallback((pos: string) => {
    onUpdateProject(prev => {
      const newLinks = { ...prev.keyLinks };
      // If this cell is already a key location, remove the link
      for (const [gate, key] of Object.entries(newLinks)) {
        if (key === pos) {
          delete newLinks[gate];
          return { ...prev, keyLinks: newLinks };
        }
      }
      // Find first unlinked key-gate and assign this cell as its key
      for (const [gate, key] of Object.entries(newLinks)) {
        if (!key) {
          newLinks[gate] = pos;
          return { ...prev, keyLinks: newLinks };
        }
      }
      return prev;
    });
  }, [onUpdateProject]);

  // Toggle key-gate on cell
  const handleToggleKeyGate = useCallback((pos: string) => {
    onUpdateProject(prev => {
      const newLinks = { ...prev.keyLinks };
      if (pos in newLinks) {
        // Remove key-gate and clear lockedGate
        delete newLinks[pos];
        const newCells = { ...prev.cells };
        if (newCells[pos]) {
          newCells[pos] = { ...newCells[pos], lockedGate: undefined };
        }
        return { ...prev, cells: newCells, keyLinks: newLinks };
      } else {
        newLinks[pos] = '';
      }
      return { ...prev, keyLinks: newLinks };
    });
  }, [onUpdateProject]);

  // Set which gate direction is locked on a key-gate cell
  const handleSetLockedGate = useCallback((pos: string, dir: Direction | undefined) => {
    onUpdateProject(prev => ({
      ...prev,
      cells: {
        ...prev.cells,
        [pos]: { ...prev.cells[pos], lockedGate: dir },
      },
    }));
  }, [onUpdateProject]);

  // Clear a cell
  const handleClearCell = useCallback((pos: string) => {
    onUpdateProject(prev => {
      const newCells = { ...prev.cells };
      delete newCells[pos];
      const newLinks = { ...prev.keyLinks };
      delete newLinks[pos];
      // Also remove any key links pointing to this cell
      for (const [gate, key] of Object.entries(newLinks)) {
        if (key === pos) delete newLinks[gate];
      }
      return {
        ...prev,
        cells: newCells,
        keyLinks: newLinks,
        startPos: prev.startPos === pos ? null : prev.startPos,
        endPos: prev.endPos === pos ? null : prev.endPos,
      };
    });
    setSelectedCell(null);
  }, [onUpdateProject]);

  // Change stage (reopen picker for occupied cell)
  const handleChangeStage = useCallback((pos: string) => {
    setPickerTarget(pos);
  }, []);

  // Generate grid
  const handleGenerate = useCallback(() => {
    const result = generateGrid(project.areaKey, project.variant, {
      ...genParams,
      gridSize: project.gridSize,
    });

    if (Object.keys(result.cells).length === 0) {
      alert('Generation failed — try different parameters or a larger grid.');
      return;
    }

    onUpdateProject(prev => ({
      ...prev,
      cells: result.cells,
      startPos: result.startPos,
      endPos: result.endPos,
      keyLinks: result.keyLinks,
    }));

    setShowGenDialog(false);
    setSelectedCell(null);
  }, [project.areaKey, project.variant, project.gridSize, genParams, onUpdateProject]);

  // Clear all cells
  const handleClear = useCallback(() => {
    if (!confirm('Clear all cells? This cannot be undone (but you can use Ctrl+Z).')) return;
    onUpdateProject(prev => ({
      ...prev,
      cells: {},
      startPos: null,
      endPos: null,
      keyLinks: {},
    }));
    setSelectedCell(null);
  }, [onUpdateProject]);

  // Validate
  const handleValidate = useCallback(() => {
    setValidationIssues(validateLayout(project));
  }, [project]);

  const cellCount = Object.keys(project.cells).length;

  return (
    <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
      {/* Main content */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'auto' }}>
        {/* Toolbar */}
        <div style={{
          display: 'flex',
          gap: '8px',
          padding: '12px 16px',
          borderBottom: '1px solid #333',
          background: '#151525',
          alignItems: 'center',
          flexWrap: 'wrap',
        }}>
          <button
            onClick={() => setShowGenDialog(true)}
            style={{
              padding: '8px 16px', background: '#5588ff', border: 'none',
              borderRadius: '6px', color: '#fff', fontSize: '13px',
              fontWeight: 600, cursor: 'pointer',
            }}
          >
            Generate
          </button>
          <button
            onClick={handleClear}
            style={{
              padding: '8px 16px', background: '#884444', border: 'none',
              borderRadius: '6px', color: '#fff', fontSize: '13px', cursor: 'pointer',
            }}
          >
            Clear
          </button>
          <button
            onClick={handleValidate}
            style={{
              padding: '8px 16px', background: '#448844', border: 'none',
              borderRadius: '6px', color: '#fff', fontSize: '13px', cursor: 'pointer',
            }}
          >
            Validate
          </button>
          <div style={{ flex: 1 }} />
          <span style={{ fontSize: '12px', color: '#888' }}>
            {cellCount} cells | {project.gridSize}x{project.gridSize}
          </span>
        </div>

        {/* Grid */}
        <div style={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '24px',
          overflow: 'auto',
        }}>
          <GridCanvas
            project={project}
            selectedCell={selectedCell}
            onCellClick={handleEmptyCellClick}
            onCellSelect={handleCellSelect}
          />
        </div>

        {/* Validation issues */}
        {validationIssues.length > 0 && (
          <div style={{
            padding: '12px 16px',
            borderTop: '1px solid #333',
            background: '#151525',
            maxHeight: '200px',
            overflowY: 'auto',
          }}>
            <div style={{
              fontSize: '11px', color: '#888', textTransform: 'uppercase',
              letterSpacing: '0.5px', marginBottom: '8px',
            }}>
              Validation ({validationIssues.length} issues)
            </div>
            {validationIssues.map((issue, i) => (
              <div
                key={i}
                onClick={() => issue.cellPos && setSelectedCell(issue.cellPos)}
                style={{
                  padding: '4px 8px',
                  fontSize: '12px',
                  color: issue.severity === 'error' ? '#ff8888' :
                         issue.severity === 'warning' ? '#ffcc66' : '#8888ff',
                  cursor: issue.cellPos ? 'pointer' : 'default',
                  borderRadius: '4px',
                }}
              >
                {issue.severity === 'error' ? '[E]' : issue.severity === 'warning' ? '[W]' : '[I]'} {issue.message}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Right panel — Inspector */}
      <div style={{
        width: '280px',
        borderLeft: '1px solid #333',
        background: '#151525',
        overflowY: 'auto',
      }}>
        {selectedCell ? (
          <CellInspector
            project={project}
            selectedCell={selectedCell}
            onUpdateCell={handleUpdateCell}
            onSetStart={handleSetStart}
            onSetEnd={handleSetEnd}
            onToggleKey={handleToggleKey}
            onToggleKeyGate={handleToggleKeyGate}
            onSetLockedGate={handleSetLockedGate}
            onClearCell={handleClearCell}
            onChangeStage={handleChangeStage}
          />
        ) : (
          <div style={{ padding: '1rem', color: '#888', fontSize: '13px' }}>
            Click a cell to inspect or edit it.
            <br /><br />
            Click an empty cell to place a stage.
          </div>
        )}
      </div>

      {/* Stage picker modal */}
      {pickerTarget && (
        <StagePicker
          project={project}
          targetPos={pickerTarget}
          onSelect={handlePlaceStage}
          onClose={() => setPickerTarget(null)}
        />
      )}

      {/* Generate dialog */}
      {showGenDialog && (
        <div
          style={{
            position: 'fixed', inset: 0, zIndex: 1000,
            background: 'rgba(0,0,0,0.7)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}
          onClick={() => setShowGenDialog(false)}
        >
          <div
            style={{
              background: '#1a1a2e',
              border: '1px solid #444',
              borderRadius: '12px',
              padding: '24px',
              width: '360px',
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ fontSize: '16px', fontWeight: 700, color: '#fff', marginBottom: '16px' }}>
              Generate Layout
            </div>
            <div style={{ fontSize: '12px', color: '#888', marginBottom: '16px' }}>
              This will replace all current cells. You can undo with Ctrl+Z.
            </div>

            <label style={{ display: 'block', marginBottom: '12px' }}>
              <div style={{ fontSize: '11px', color: '#888', marginBottom: '4px' }}>Path Length</div>
              <input
                type="number" min={3} max={project.gridSize * project.gridSize}
                value={genParams.usedCells}
                onChange={(e) => setGenParams(p => ({ ...p, usedCells: parseInt(e.target.value) || 8 }))}
                style={{
                  width: '100%', padding: '8px', background: '#2a2a4a',
                  border: '1px solid #444', borderRadius: '4px', color: '#fff', fontSize: '13px',
                }}
              />
            </label>

            <label style={{ display: 'block', marginBottom: '12px' }}>
              <div style={{ fontSize: '11px', color: '#888', marginBottom: '4px' }}>Key-Gates</div>
              <input
                type="number" min={0} max={5}
                value={genParams.keyGates}
                onChange={(e) => setGenParams(p => ({ ...p, keyGates: parseInt(e.target.value) || 0 }))}
                style={{
                  width: '100%', padding: '8px', background: '#2a2a4a',
                  border: '1px solid #444', borderRadius: '4px', color: '#fff', fontSize: '13px',
                }}
              />
            </label>

            <label style={{ display: 'block', marginBottom: '16px' }}>
              <div style={{ fontSize: '11px', color: '#888', marginBottom: '4px' }}>Dead-End Branches</div>
              <input
                type="number" min={0} max={5}
                value={genParams.branches}
                onChange={(e) => setGenParams(p => ({ ...p, branches: parseInt(e.target.value) || 0 }))}
                style={{
                  width: '100%', padding: '8px', background: '#2a2a4a',
                  border: '1px solid #444', borderRadius: '4px', color: '#fff', fontSize: '13px',
                }}
              />
            </label>

            <div style={{ display: 'flex', gap: '8px' }}>
              <button
                onClick={handleGenerate}
                style={{
                  flex: 1, padding: '10px', background: '#5588ff', border: 'none',
                  borderRadius: '6px', color: '#fff', fontSize: '14px',
                  fontWeight: 600, cursor: 'pointer',
                }}
              >
                Generate
              </button>
              <button
                onClick={() => setShowGenDialog(false)}
                style={{
                  flex: 1, padding: '10px', background: '#444', border: 'none',
                  borderRadius: '6px', color: '#fff', fontSize: '14px', cursor: 'pointer',
                }}
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
