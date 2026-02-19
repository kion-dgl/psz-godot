/**
 * CellInspector — Right panel for editing a selected cell
 *
 * Shows stage info, gate visualization, role dropdown,
 * start/end toggle, key/key-gate controls, notes.
 */

import type { QuestProject, EditorGridCell, Direction, SectionType } from '../types';
import { getRotatedGates, getStageSuffix } from '../hooks/useStageConfigs';

interface CellInspectorProps {
  project: QuestProject;
  selectedCell: string;
  onUpdateCell: (pos: string, updates: Partial<EditorGridCell>) => void;
  onSetStart: (pos: string) => void;
  onSetEnd: (pos: string) => void;
  onToggleKey: (pos: string) => void;
  onToggleKeyGate: (pos: string) => void;
  onSetLockedGate: (pos: string, dir: Direction | undefined) => void;
  onClearCell: (pos: string) => void;
  onChangeStage: (pos: string) => void;
  sectionType?: SectionType;
  entryDirection?: Direction;
  exitDirection?: Direction;
  onSetSectionDirection?: (field: 'entryDirection' | 'exitDirection', dir: Direction | undefined) => void;
}



const labelStyle: React.CSSProperties = {
  fontSize: '11px',
  color: '#888',
  textTransform: 'uppercase' as const,
  letterSpacing: '0.5px',
  marginBottom: '4px',
};

const sectionStyle: React.CSSProperties = {
  marginBottom: '16px',
};

export default function CellInspector({
  project,
  selectedCell,
  onUpdateCell,
  onSetStart,
  onSetEnd,
  onToggleKey,
  onToggleKeyGate,
  onSetLockedGate,
  onClearCell,
  onChangeStage,
  sectionType,
  entryDirection,
  exitDirection,
  onSetSectionDirection,
}: CellInspectorProps) {
  const cell = project.cells[selectedCell];
  if (!cell) {
    return (
      <div style={{ padding: '1rem', color: '#888' }}>
        <div style={labelStyle}>Empty Cell</div>
        <p style={{ fontSize: '13px' }}>Click an empty cell to place a stage, or select an occupied cell to edit it.</p>
        <p style={{ fontSize: '12px', color: '#666', marginTop: '8px' }}>
          Position: {selectedCell}
        </p>
      </div>
    );
  }

  const gates = getRotatedGates(cell.stageName, cell.rotation ?? 0);
  const suffix = getStageSuffix(cell.stageName);
  const isStart = project.startPos === selectedCell;
  const isEnd = project.endPos === selectedCell;
  const hasKey = Object.values(project.keyLinks).includes(selectedCell);
  const isKeyGate = selectedCell in project.keyLinks;

  return (
    <div style={{ padding: '1rem', overflowY: 'auto', maxHeight: 'calc(100vh - 200px)' }}>
      {/* Header */}
      <div style={sectionStyle}>
        <div style={{ fontSize: '18px', fontWeight: 700, color: '#fff', marginBottom: '4px' }}>
          {suffix}
        </div>
        <div style={{ fontSize: '12px', color: '#888' }}>
          {cell.stageName} at {selectedCell}
        </div>
        {cell.manual && (
          <div style={{ fontSize: '10px', color: '#88aaff', marginTop: '4px' }}>
            Manually placed
          </div>
        )}
        {/* Rotation control */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '8px' }}>
          <span style={{ fontSize: '11px', color: '#888' }}>Rotation:</span>
          {[0, 90, 180, 270].map(rot => (
            <button
              key={rot}
              onClick={() => onUpdateCell(selectedCell, { rotation: rot || undefined })}
              style={{
                padding: '3px 8px',
                background: (cell.rotation ?? 0) === rot ? '#5588ff' : '#2a2a4a',
                border: `1px solid ${(cell.rotation ?? 0) === rot ? '#88aaff' : '#444'}`,
                borderRadius: '4px',
                color: '#fff',
                fontSize: '11px',
                cursor: 'pointer',
              }}
            >
              {rot}&deg;
            </button>
          ))}
        </div>
      </div>

      {/* Gates visualization — click a gate to toggle key-lock */}
      <div style={sectionStyle}>
        <div style={labelStyle}>Gates {isKeyGate && '(click gate to lock)'}</div>
        <div style={{
          display: 'grid',
          gridTemplateColumns: '1fr 1fr 1fr',
          gridTemplateRows: '1fr 1fr 1fr',
          width: '100px',
          height: '100px',
          gap: '2px',
          margin: '0 auto',
        }}>
          {(['north', 'west', 'east', 'south'] as Direction[]).map(dir => {
            const hasGate = gates.has(dir);
            const isLocked = cell.lockedGate === dir;
            const bg = isLocked ? '#ff66ff' : hasGate ? '#88ff88' : '#333';
            const clickable = isKeyGate && hasGate;
            const gridArea = dir === 'north' ? '1/2' : dir === 'west' ? '2/1' : dir === 'east' ? '2/3' : '3/2';
            return (
              <div
                key={dir}
                onClick={clickable ? () => onSetLockedGate(selectedCell, isLocked ? undefined : dir) : undefined}
                style={{
                  gridArea,
                  background: bg,
                  borderRadius: '2px',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: '8px', color: '#fff',
                  cursor: clickable ? 'pointer' : 'default',
                  border: isLocked ? '2px solid #ff88ff' : '2px solid transparent',
                }}
              >{dir[0].toUpperCase()}</div>
            );
          })}
          <div style={{
            gridArea: '2/2',
            background: '#556',
            borderRadius: '2px',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: '9px', color: '#fff', fontWeight: 600,
          }}>{suffix}</div>
        </div>
      </div>

      {/* Start / End — for grids: set start/end cell; for transition/boss: set entry/exit direction */}
      {(sectionType === 'transition' || sectionType === 'boss') && onSetSectionDirection ? (
        <div style={sectionStyle}>
          <div style={labelStyle}>Entry Direction</div>
          <div style={{ display: 'flex', gap: '4px', marginBottom: '12px' }}>
            {(['north', 'south'] as Direction[]).map(dir => {
              const active = entryDirection === dir;
              return (
                <button
                  key={dir}
                  onClick={() => onSetSectionDirection('entryDirection', active ? undefined : dir)}
                  style={{
                    flex: 1,
                    padding: '8px',
                    background: active ? '#66aaff' : '#2a2a4a',
                    border: `1px solid ${active ? '#88ccff' : '#444'}`,
                    borderRadius: '4px',
                    color: '#fff',
                    fontSize: '12px',
                    fontWeight: active ? 700 : 400,
                    cursor: 'pointer',
                    textTransform: 'capitalize',
                  }}
                >
                  {dir}
                </button>
              );
            })}
          </div>
          <div style={labelStyle}>Exit Direction</div>
          <div style={{ display: 'flex', gap: '4px' }}>
            {(['north', 'south'] as Direction[]).map(dir => {
              const active = exitDirection === dir;
              return (
                <button
                  key={dir}
                  onClick={() => onSetSectionDirection('exitDirection', active ? undefined : dir)}
                  style={{
                    flex: 1,
                    padding: '8px',
                    background: active ? '#ffaa66' : '#2a2a4a',
                    border: `1px solid ${active ? '#ffcc88' : '#444'}`,
                    borderRadius: '4px',
                    color: '#fff',
                    fontSize: '12px',
                    fontWeight: active ? 700 : 400,
                    cursor: 'pointer',
                    textTransform: 'capitalize',
                  }}
                >
                  {dir}
                </button>
              );
            })}
          </div>
        </div>
      ) : (
        <div style={sectionStyle}>
          <div style={labelStyle}>Markers</div>
          <div style={{ display: 'flex', gap: '8px' }}>
            <button
              onClick={() => onSetStart(selectedCell)}
              style={{
                flex: 1,
                padding: '8px',
                background: isStart ? '#66aaff' : '#2a2a4a',
                border: `1px solid ${isStart ? '#88ccff' : '#444'}`,
                borderRadius: '4px',
                color: '#fff',
                fontSize: '12px',
                fontWeight: isStart ? 700 : 400,
                cursor: 'pointer',
              }}
            >
              {isStart ? 'Start' : 'Set Start'}
            </button>
            <button
              onClick={() => onSetEnd(selectedCell)}
              style={{
                flex: 1,
                padding: '8px',
                background: isEnd ? '#ffaa66' : '#2a2a4a',
                border: `1px solid ${isEnd ? '#ffcc88' : '#444'}`,
                borderRadius: '4px',
                color: '#fff',
                fontSize: '12px',
                fontWeight: isEnd ? 700 : 400,
                cursor: 'pointer',
              }}
            >
              {isEnd ? 'End' : 'Set End'}
            </button>
          </div>
        </div>
      )}

      {/* Key & Key-Gate */}
      <div style={sectionStyle}>
        <div style={labelStyle}>Keys</div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <button
            onClick={() => onToggleKey(selectedCell)}
            style={{
              flex: 1,
              padding: '8px',
              background: hasKey ? '#ff66aa' : '#2a2a4a',
              border: `1px solid ${hasKey ? '#ff88cc' : '#444'}`,
              borderRadius: '4px',
              color: '#fff',
              fontSize: '12px',
              fontWeight: hasKey ? 700 : 400,
              cursor: 'pointer',
            }}
          >
            {hasKey ? 'Has Key' : 'Add Key'}
          </button>
          <button
            onClick={() => onToggleKeyGate(selectedCell)}
            style={{
              flex: 1,
              padding: '8px',
              background: isKeyGate ? '#ff66ff' : '#2a2a4a',
              border: `1px solid ${isKeyGate ? '#ff88ff' : '#444'}`,
              borderRadius: '4px',
              color: '#fff',
              fontSize: '12px',
              fontWeight: isKeyGate ? 700 : 400,
              cursor: 'pointer',
            }}
          >
            {isKeyGate ? 'Key-Gate' : 'Add Gate'}
          </button>
        </div>
        {isKeyGate && (
          <>
            <div style={{ fontSize: '11px', color: '#cc88ff', marginTop: '4px' }}>
              Locked: {cell.lockedGate ? `${cell.lockedGate} gate` : 'click a gate above to lock'}
            </div>
            <div style={{ fontSize: '11px', color: '#cc88ff', marginTop: '2px' }}>
              Key at: {project.keyLinks[selectedCell] || 'unlinked'}
            </div>
          </>
        )}
        {hasKey && (
          <div style={{ fontSize: '11px', color: '#ff88aa', marginTop: '4px' }}>
            Unlocks: {Object.entries(project.keyLinks).find(([_, v]) => v === selectedCell)?.[0] || 'unlinked'}
          </div>
        )}
      </div>

      {/* Notes */}
      <div style={sectionStyle}>
        <div style={labelStyle}>Notes</div>
        <textarea
          value={cell.notes || ''}
          onChange={(e) => onUpdateCell(selectedCell, { notes: e.target.value || undefined })}
          placeholder="Optional designer notes..."
          rows={3}
          style={{
            width: '100%',
            padding: '8px',
            background: '#2a2a4a',
            border: '1px solid #444',
            borderRadius: '4px',
            color: '#fff',
            fontSize: '12px',
            resize: 'vertical',
            fontFamily: 'inherit',
          }}
        />
      </div>

      {/* Actions */}
      <div style={{ display: 'flex', gap: '8px' }}>
        <button
          onClick={() => onChangeStage(selectedCell)}
          style={{
            flex: 1,
            padding: '8px',
            background: '#555588',
            border: 'none',
            borderRadius: '4px',
            color: '#fff',
            fontSize: '12px',
            cursor: 'pointer',
          }}
        >
          Change Stage
        </button>
        <button
          onClick={() => onClearCell(selectedCell)}
          style={{
            flex: 1,
            padding: '8px',
            background: '#884444',
            border: 'none',
            borderRadius: '4px',
            color: '#fff',
            fontSize: '12px',
            cursor: 'pointer',
          }}
        >
          Clear Cell
        </button>
      </div>
    </div>
  );
}
