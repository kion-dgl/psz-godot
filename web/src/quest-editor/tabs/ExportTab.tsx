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
import type { QuestProject, ValidationIssue, EditorGridCell } from '../types';
import { getProjectSections } from '../types';
import { projectToGodotQuest, godotQuestToProject } from '../utils/quest-io';
import {
  getRotatedGates,
  getNeighbor,
  isValidPos,
  oppositeDirection,
} from '../hooks/useStageConfigs';

interface ExportTabProps {
  project: QuestProject;
  setProject?: (project: QuestProject) => void;
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

/** Get the default download filename based on the project source */
function getDefaultFilename(project: QuestProject): string {
  if (project.source?.type === 'game') {
    return `${project.source.filename}.json`;
  }
  return (project.name || 'quest').toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '') + '.json';
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

  const defaultFilename = useMemo(() => getDefaultFilename(project), [project]);

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
      {/* Source info */}
      {project.source?.type === 'game' && (
        <div style={{
          padding: '10px 14px',
          background: '#1a2a3a',
          border: '1px solid #334',
          borderRadius: '6px',
          fontSize: '13px',
          color: '#88aaff',
        }}>
          Editing game quest: <strong>{project.source.filename}.json</strong>
          <span style={{ color: '#666', marginLeft: '8px', fontSize: '11px' }}>
            Download will use this filename by default
          </span>
        </div>
      )}

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
            onClick={() => downloadJson(godotJson, defaultFilename)}
            disabled={hasErrors}
            style={{
              ...buttonStyle,
              background: hasErrors ? '#444' : buttonStyle.background,
              cursor: hasErrors ? 'not-allowed' : 'pointer',
            }}
          >
            Download ({defaultFilename})
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
