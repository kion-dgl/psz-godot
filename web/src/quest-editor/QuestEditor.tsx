/**
 * QuestEditor — Main component with tab shell and header controls
 *
 * Milestone 1: Grid Layout Editor
 */

import { useState, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import type { QuestProject, QuestSection, SectionType, Direction } from './types';
import {
  EDITOR_AREAS, getProjectSections, createSection,
  SECTION_TYPE_LABELS, SECTION_VARIANT_SUGGESTIONS,
} from './types';
import { useQuestProject } from './hooks/useQuestProject';
import LayoutTab from './tabs/LayoutTab';
import ContentTab from './tabs/ContentTab';
import MetadataTab from './tabs/MetadataTab';
import ExportTab from './tabs/ExportTab';

type TabId = 'layout' | 'content' | 'metadata' | 'export';

const TABS: { id: TabId; label: string; disabled?: boolean }[] = [
  { id: 'layout', label: 'Layout' },
  { id: 'content', label: 'Content' },
  { id: 'metadata', label: 'Metadata' },
  { id: 'export', label: 'Export' },
];

export default function QuestEditor() {
  const {
    project,
    updateProject,
    setProject,
    undo,
    redo,
    canUndo,
    canRedo,
    newProject,
    savedProjectIds,
    loadProject,
    deleteProject,
    getSavedProject,
  } = useQuestProject();

  const navigate = useNavigate();

  const [activeTab, setActiveTab] = useState<TabId>(
    project.source?.type === 'new' ? 'metadata' : 'layout'
  );
  const [showProjectMenu, setShowProjectMenu] = useState(false);
  const [currentSectionIdx, setCurrentSectionIdx] = useState(0);

  const sourceLabel = useMemo(() => {
    const src = project.source;
    if (!src) return null;
    if (src.type === 'game') return { text: src.filename + '.json', badge: 'game', color: '#88aaff', bg: '#334' };
    if (src.type === 'new') return { text: 'New Quest', badge: 'new', color: '#88cc88', bg: '#343' };
    if (src.type === 'draft') return { text: 'Draft', badge: 'draft', color: '#88cc88', bg: '#343' };
    return null;
  }, [project.source]);

  const availableAreas = EDITOR_AREAS.filter(a => a.available);

  const sections = useMemo(() => getProjectSections(project), [project]);
  const hasMultipleSections = !!(project.sections && project.sections.length > 0);

  // Clamp section index
  const sectionIdx = Math.min(currentSectionIdx, sections.length - 1);
  const activeSection = sections[sectionIdx];

  // Build a "virtual project" that maps the active section's fields to top-level
  const sectionProject = useMemo<QuestProject>(() => {
    if (!hasMultipleSections) return project;
    return {
      ...project,
      variant: activeSection.variant,
      gridSize: activeSection.gridSize,
      cells: activeSection.cells,
      startPos: activeSection.startPos,
      endPos: activeSection.endPos,
      keyLinks: activeSection.keyLinks,
    };
  }, [project, activeSection, hasMultipleSections]);

  // Route updates to the correct section
  const updateSectionProject = useCallback((updater: (prev: QuestProject) => QuestProject) => {
    if (!hasMultipleSections) {
      updateProject(updater);
      return;
    }
    updateProject(prev => {
      // Create a virtual project from the active section
      const sec = prev.sections![sectionIdx];
      const virtualPrev: QuestProject = {
        ...prev,
        variant: sec.variant,
        gridSize: sec.gridSize,
        cells: sec.cells,
        startPos: sec.startPos,
        endPos: sec.endPos,
        keyLinks: sec.keyLinks,
      };
      const virtualNext = updater(virtualPrev);
      // Write section fields back
      const newSections = [...prev.sections!];
      newSections[sectionIdx] = {
        ...newSections[sectionIdx],
        variant: virtualNext.variant,
        gridSize: virtualNext.gridSize,
        cells: virtualNext.cells,
        startPos: virtualNext.startPos,
        endPos: virtualNext.endPos,
        keyLinks: virtualNext.keyLinks,
      };
      return { ...virtualNext, sections: newSections, variant: prev.variant, gridSize: prev.gridSize, cells: prev.cells, startPos: prev.startPos, endPos: prev.endPos, keyLinks: prev.keyLinks };
    });
  }, [updateProject, hasMultipleSections, sectionIdx]);

  const handleSetSectionDirection = useCallback((field: 'entryDirection' | 'exitDirection', dir: Direction | undefined) => {
    if (!hasMultipleSections) return;
    updateProject(prev => {
      const newSections = [...prev.sections!];
      newSections[sectionIdx] = { ...newSections[sectionIdx], [field]: dir };
      return { ...prev, sections: newSections };
    });
  }, [updateProject, hasMultipleSections, sectionIdx]);

  const handleAddSection = useCallback((type: SectionType) => {
    const variant = SECTION_VARIANT_SUGGESTIONS[type];
    const newSec = createSection(type, variant);
    updateProject(prev => {
      const existingSections = getProjectSections(prev);
      return {
        ...prev,
        sections: [...existingSections, newSec],
      };
    });
    setCurrentSectionIdx(sections.length);
  }, [updateProject, sections.length]);

  const handleDeleteSection = useCallback((idx: number) => {
    updateProject(prev => {
      const secs = getProjectSections(prev);
      if (secs.length <= 1) return prev; // Don't delete last section
      const newSections = secs.filter((_, i) => i !== idx);
      return { ...prev, sections: newSections };
    });
    if (currentSectionIdx >= sections.length - 1) {
      setCurrentSectionIdx(Math.max(0, sections.length - 2));
    }
  }, [updateProject, currentSectionIdx, sections.length]);

  const handleEnableMultiSection = useCallback(() => {
    updateProject(prev => ({
      ...prev,
      sections: getProjectSections(prev),
    }));
  }, [updateProject]);

  const handleAreaChange = useCallback((areaKey: string) => {
    updateProject(prev => ({
      ...prev,
      areaKey,
      cells: {},
      startPos: null,
      endPos: null,
      keyLinks: {},
      sections: prev.sections ? prev.sections.map(s => ({ ...s, cells: {}, startPos: null, endPos: null, keyLinks: {} })) : undefined,
    }));
  }, [updateProject]);

  const handleVariantChange = useCallback((variant: string) => {
    if (hasMultipleSections) {
      updateSectionProject(prev => ({
        ...prev,
        variant,
        cells: {},
        startPos: null,
        endPos: null,
        keyLinks: {},
      }));
    } else {
      updateProject(prev => ({
        ...prev,
        variant,
        cells: {},
        startPos: null,
        endPos: null,
        keyLinks: {},
      }));
    }
  }, [updateProject, updateSectionProject, hasMultipleSections]);

  const handleGridSizeChange = useCallback((gridSize: number) => {
    if (hasMultipleSections) {
      updateSectionProject(prev => ({
        ...prev,
        gridSize,
        cells: {},
        startPos: null,
        endPos: null,
        keyLinks: {},
      }));
    } else {
      updateProject(prev => ({
        ...prev,
        gridSize,
        cells: {},
        startPos: null,
        endPos: null,
        keyLinks: {},
      }));
    }
  }, [updateProject, updateSectionProject, hasMultipleSections]);

  const handleNameChange = useCallback((name: string) => {
    updateProject(prev => ({ ...prev, name }));
  }, [updateProject]);

  const currentArea = EDITOR_AREAS.find(a => a.key === project.areaKey);

  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: '#1a1a2e',
      color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      {/* Header */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: '12px',
        padding: '10px 16px',
        background: '#151525',
        borderBottom: '1px solid #333',
        flexWrap: 'wrap',
      }}>
        {/* Back button */}
        <button
          onClick={() => navigate('/quest-editor')}
          style={{
            padding: '4px 10px',
            background: '#2a2a4a',
            border: '1px solid #444',
            borderRadius: '4px',
            color: '#888',
            fontSize: '12px',
            cursor: 'pointer',
          }}
          title="Back to quest list"
        >
          &larr; Quests
        </button>

        {/* Source badge */}
        {sourceLabel && (
          <span style={{
            padding: '2px 8px',
            background: sourceLabel.bg,
            borderRadius: '4px',
            fontSize: '11px',
            color: sourceLabel.color,
          }}>
            {sourceLabel.text}
          </span>
        )}

        {/* Project name */}
        <input
          type="text"
          value={project.name}
          onChange={(e) => handleNameChange(e.target.value)}
          style={{
            background: 'transparent',
            border: '1px solid transparent',
            borderRadius: '4px',
            color: '#fff',
            fontSize: '15px',
            fontWeight: 700,
            padding: '4px 8px',
            width: '200px',
          }}
          onFocus={(e) => e.currentTarget.style.borderColor = '#444'}
          onBlur={(e) => e.currentTarget.style.borderColor = 'transparent'}
        />

        {/* Separator */}
        <div style={{ width: '1px', height: '24px', background: '#333' }} />

        {/* Area selector */}
        <select
          value={project.areaKey}
          onChange={(e) => handleAreaChange(e.target.value)}
          style={{
            padding: '6px 10px',
            background: '#2a2a4a',
            border: '1px solid #444',
            borderRadius: '4px',
            color: '#fff',
            fontSize: '12px',
          }}
        >
          {EDITOR_AREAS.map(area => (
            <option key={area.key} value={area.key} disabled={!area.available}>
              {area.name} ({area.prefix}){!area.available ? ' — no config' : ''}
            </option>
          ))}
        </select>

        {/* Variant selector */}
        {currentArea && currentArea.variants.length > 0 && (
          <select
            value={sectionProject.variant}
            onChange={(e) => handleVariantChange(e.target.value)}
            style={{
              padding: '6px 10px',
              background: '#2a2a4a',
              border: '1px solid #444',
              borderRadius: '4px',
              color: '#fff',
              fontSize: '12px',
            }}
          >
            {currentArea.variants.map(v => (
              <option key={v} value={v}>Variant {v.toUpperCase()}</option>
            ))}
          </select>
        )}

        {/* Grid size */}
        <select
          value={sectionProject.gridSize}
          onChange={(e) => handleGridSizeChange(parseInt(e.target.value))}
          style={{
            padding: '6px 10px',
            background: '#2a2a4a',
            border: '1px solid #444',
            borderRadius: '4px',
            color: '#fff',
            fontSize: '12px',
          }}
        >
          {[3, 4, 5, 6, 7].map(n => (
            <option key={n} value={n}>{n}x{n}</option>
          ))}
        </select>

        <div style={{ flex: 1 }} />

        {/* Undo/Redo */}
        <button
          onClick={undo}
          disabled={!canUndo}
          title="Undo (Ctrl+Z)"
          style={{
            padding: '4px 10px',
            background: canUndo ? '#2a2a4a' : '#222',
            border: '1px solid #444',
            borderRadius: '4px',
            color: canUndo ? '#fff' : '#555',
            fontSize: '12px',
            cursor: canUndo ? 'pointer' : 'default',
          }}
        >
          Undo
        </button>
        <button
          onClick={redo}
          disabled={!canRedo}
          title="Redo (Ctrl+Y)"
          style={{
            padding: '4px 10px',
            background: canRedo ? '#2a2a4a' : '#222',
            border: '1px solid #444',
            borderRadius: '4px',
            color: canRedo ? '#fff' : '#555',
            fontSize: '12px',
            cursor: canRedo ? 'pointer' : 'default',
          }}
        >
          Redo
        </button>

        {/* Project menu */}
        <div style={{ position: 'relative' }}>
          <button
            onClick={() => setShowProjectMenu(!showProjectMenu)}
            style={{
              padding: '4px 10px',
              background: '#2a2a4a',
              border: '1px solid #444',
              borderRadius: '4px',
              color: '#fff',
              fontSize: '12px',
              cursor: 'pointer',
            }}
          >
            Projects
          </button>
          {showProjectMenu && (
            <div
              style={{
                position: 'absolute',
                top: '100%',
                right: 0,
                marginTop: '4px',
                background: '#1a1a2e',
                border: '1px solid #444',
                borderRadius: '8px',
                padding: '8px',
                width: '260px',
                zIndex: 100,
                boxShadow: '0 8px 24px rgba(0,0,0,0.5)',
              }}
            >
              <button
                onClick={() => { newProject(); setShowProjectMenu(false); }}
                style={{
                  width: '100%', padding: '8px', background: '#448844',
                  border: 'none', borderRadius: '4px', color: '#fff',
                  fontSize: '12px', cursor: 'pointer', marginBottom: '8px',
                }}
              >
                New Project
              </button>
              {savedProjectIds.length === 0 && (
                <div style={{ color: '#888', fontSize: '12px', padding: '8px' }}>
                  No saved projects
                </div>
              )}
              {savedProjectIds.map(id => {
                const saved = getSavedProject(id);
                if (!saved) return null;
                const isCurrent = id === project.id;
                return (
                  <div
                    key={id}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: '8px',
                      padding: '6px 8px',
                      borderRadius: '4px',
                      background: isCurrent ? '#333366' : 'transparent',
                      marginBottom: '2px',
                    }}
                  >
                    <div
                      style={{ flex: 1, cursor: 'pointer', fontSize: '12px', color: '#fff' }}
                      onClick={() => { loadProject(id); setShowProjectMenu(false); }}
                    >
                      {saved.name}
                      <div style={{ fontSize: '10px', color: '#888' }}>
                        {saved.areaKey}-{saved.variant} | {Object.keys(saved.cells).length} cells
                      </div>
                    </div>
                    {!isCurrent && (
                      <button
                        onClick={() => deleteProject(id)}
                        style={{
                          background: 'none', border: 'none', color: '#884444',
                          fontSize: '14px', cursor: 'pointer', padding: '2px',
                        }}
                        title="Delete project"
                      >
                        ✕
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* Tab bar */}
      <div style={{
        display: 'flex',
        gap: '0',
        background: '#151525',
        borderBottom: '1px solid #333',
      }}>
        {TABS.map(tab => (
          <button
            key={tab.id}
            onClick={() => !tab.disabled && setActiveTab(tab.id)}
            disabled={tab.disabled}
            style={{
              padding: '10px 20px',
              background: activeTab === tab.id ? '#1a1a2e' : 'transparent',
              border: 'none',
              borderBottom: activeTab === tab.id ? '2px solid #5588ff' : '2px solid transparent',
              color: tab.disabled ? '#555' : activeTab === tab.id ? '#fff' : '#888',
              fontSize: '13px',
              fontWeight: activeTab === tab.id ? 600 : 400,
              cursor: tab.disabled ? 'default' : 'pointer',
              transition: 'all 0.1s',
            }}
          >
            {tab.label}
            {tab.disabled && <span style={{ fontSize: '10px', marginLeft: '4px' }}>(M{tab.id === 'content' ? '2' : '3'})</span>}
          </button>
        ))}
      </div>

      {/* Section bar (multi-section mode) */}
      {(activeTab === 'layout' || activeTab === 'content') && (
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: '4px',
          padding: '6px 16px',
          background: '#1a1a30',
          borderBottom: '1px solid #333',
          fontSize: '11px',
        }}>
          <span style={{ color: '#888', marginRight: '4px' }}>Sections:</span>
          {sections.map((sec, idx) => (
            <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '0' }}>
              <button
                onClick={() => setCurrentSectionIdx(idx)}
                style={{
                  padding: '4px 10px',
                  background: idx === sectionIdx ? '#3a3a6a' : '#222',
                  border: `1px solid ${idx === sectionIdx ? '#5588ff' : '#444'}`,
                  borderRadius: hasMultipleSections ? '4px 0 0 4px' : '4px',
                  color: idx === sectionIdx ? '#fff' : '#888',
                  fontSize: '11px',
                  fontWeight: idx === sectionIdx ? 600 : 400,
                  cursor: 'pointer',
                }}
              >
                {hasMultipleSections
                  ? `${SECTION_TYPE_LABELS[sec.type]} ${sec.variant.toUpperCase()}`
                  : `Section ${sec.variant.toUpperCase()}`
                }
                {sec.type === 'grid' && ` (${sec.gridSize}x${sec.gridSize})`}
              </button>
              {hasMultipleSections && sections.length > 1 && (
                <button
                  onClick={() => handleDeleteSection(idx)}
                  title="Remove section"
                  style={{
                    padding: '4px 6px',
                    background: '#442222',
                    border: '1px solid #444',
                    borderLeft: 'none',
                    borderRadius: '0 4px 4px 0',
                    color: '#aa6666',
                    fontSize: '10px',
                    cursor: 'pointer',
                  }}
                >
                  X
                </button>
              )}
            </div>
          ))}

          {/* Add section buttons */}
          {hasMultipleSections ? (
            <div style={{ display: 'flex', gap: '2px', marginLeft: '8px' }}>
              {(['grid', 'transition', 'boss'] as SectionType[]).map(type => (
                <button
                  key={type}
                  onClick={() => handleAddSection(type)}
                  style={{
                    padding: '3px 8px',
                    background: '#224422',
                    border: '1px solid #446644',
                    borderRadius: '4px',
                    color: '#88cc88',
                    fontSize: '10px',
                    cursor: 'pointer',
                  }}
                >
                  + {SECTION_TYPE_LABELS[type]}
                </button>
              ))}
            </div>
          ) : (
            <button
              onClick={handleEnableMultiSection}
              style={{
                padding: '3px 8px',
                background: '#2a2a4a',
                border: '1px solid #444',
                borderRadius: '4px',
                color: '#888',
                fontSize: '10px',
                cursor: 'pointer',
                marginLeft: '8px',
              }}
            >
              Enable Multi-Section
            </button>
          )}
        </div>
      )}

      {/* Active tab content */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {activeTab === 'layout' && (
          <LayoutTab
            project={sectionProject}
            onUpdateProject={updateSectionProject}
            sectionType={activeSection.type}
            entryDirection={activeSection.entryDirection}
            exitDirection={activeSection.exitDirection}
            onSetSectionDirection={handleSetSectionDirection}
          />
        )}
        {activeTab === 'content' && <ContentTab project={sectionProject} onUpdateProject={updateSectionProject} />}
        {activeTab === 'metadata' && <MetadataTab project={project} onUpdateProject={updateProject} />}
        {activeTab === 'export' && <ExportTab project={project} setProject={setProject} />}
      </div>
    </div>
  );
}
