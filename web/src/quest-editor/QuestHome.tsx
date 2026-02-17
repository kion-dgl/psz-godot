/**
 * QuestHome — Landing page for quest editor
 *
 * Shows two sections: "Create New Quest" and "Edit Existing Quest"
 * (game quests from data/quests/ + localStorage drafts)
 */

import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import type { QuestProject, QuestProjectSource } from './types';
import { createDefaultProject } from './types';
import { godotQuestToProject } from './utils/quest-io';
import { assetUrl } from '../utils/assets';

interface GameQuestInfo {
  filename: string;
  name: string;
  description: string;
  areaId: string;
  sectionCount: number;
}

interface DraftInfo {
  id: string;
  name: string;
  areaKey: string;
  variant: string;
  cellCount: number;
  lastModified: string;
}

const STORAGE_KEY = 'quest-editor-projects';

function loadDrafts(): DraftInfo[] {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (!stored) return [];
    const projects: Record<string, QuestProject> = JSON.parse(stored);
    return Object.values(projects).map(p => ({
      id: p.id,
      name: p.name,
      areaKey: p.areaKey,
      variant: p.variant,
      cellCount: Object.keys(p.cells).length,
      lastModified: p.lastModified,
    })).sort((a, b) => b.lastModified.localeCompare(a.lastModified));
  } catch {
    return [];
  }
}

export default function QuestHome() {
  const navigate = useNavigate();
  const [gameQuests, setGameQuests] = useState<GameQuestInfo[]>([]);
  const [drafts, setDrafts] = useState<DraftInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    setDrafts(loadDrafts());

    (async () => {
      try {
        const manifestUrl = assetUrl('/data/quests/manifest.json');
        const res = await fetch(manifestUrl);
        if (!res.ok) {
          setError('Could not load quest manifest');
          setLoading(false);
          return;
        }
        const filenames: string[] = await res.json();

        const quests: GameQuestInfo[] = [];
        for (const fn of filenames) {
          try {
            const questUrl = assetUrl(`/data/quests/${fn}.json`);
            const qRes = await fetch(questUrl);
            if (!qRes.ok) continue;
            const quest = await qRes.json();
            quests.push({
              filename: fn,
              name: quest.name || fn,
              description: quest.description || '',
              areaId: quest.area_id || '',
              sectionCount: quest.sections?.length || 0,
            });
          } catch {
            // skip broken quest files
          }
        }
        setGameQuests(quests);
      } catch {
        setError('Could not load quest manifest');
      }
      setLoading(false);
    })();
  }, []);

  const handleNewQuest = useCallback(() => {
    const fresh = createDefaultProject();
    fresh.source = { type: 'new' };
    saveAndNavigate(fresh);
  }, []);

  const handleOpenGameQuest = useCallback(async (filename: string) => {
    try {
      const questUrl = assetUrl(`/data/quests/${filename}.json`);
      const res = await fetch(questUrl);
      if (!res.ok) throw new Error('Fetch failed');
      const quest = await res.json();
      const project = godotQuestToProject(quest);
      project.source = { type: 'game', filename };
      saveAndNavigate(project);
    } catch (e) {
      setError(`Failed to load ${filename}: ${e}`);
    }
  }, []);

  const handleOpenDraft = useCallback((id: string) => {
    // Mark the draft as active and navigate
    localStorage.setItem('quest-editor-active', id);
    // Add source info to the draft
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        const projects: Record<string, QuestProject> = JSON.parse(stored);
        if (projects[id]) {
          projects[id].source = { type: 'draft', id };
          localStorage.setItem(STORAGE_KEY, JSON.stringify(projects));
        }
      }
    } catch { /* ok */ }
    navigate('/quest-editor/edit');
  }, [navigate]);

  function saveAndNavigate(project: QuestProject) {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      const projects: Record<string, QuestProject> = stored ? JSON.parse(stored) : {};
      projects[project.id] = { ...project, lastModified: new Date().toISOString() };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(projects));
      localStorage.setItem('quest-editor-active', project.id);
    } catch { /* ok */ }
    navigate('/quest-editor/edit');
  }

  const cardStyle = {
    padding: '12px 16px',
    background: '#1e1e3a',
    border: '1px solid #333',
    borderRadius: '8px',
    cursor: 'pointer',
    transition: 'border-color 0.15s',
  };

  return (
    <div style={{
      height: '100%',
      overflow: 'auto',
      background: '#1a1a2e',
      color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
      padding: '32px',
    }}>
      <div style={{ maxWidth: '720px', margin: '0 auto' }}>
        <h1 style={{ fontSize: '22px', fontWeight: 700, marginBottom: '8px' }}>
          Quest Editor
        </h1>
        <p style={{ color: '#888', fontSize: '13px', marginBottom: '32px' }}>
          Create new quests or edit existing ones from the game files.
        </p>

        {/* Create New */}
        <button
          onClick={handleNewQuest}
          style={{
            width: '100%',
            padding: '16px',
            background: '#2a4a2a',
            border: '1px solid #446644',
            borderRadius: '8px',
            color: '#fff',
            fontSize: '15px',
            fontWeight: 600,
            cursor: 'pointer',
            marginBottom: '32px',
            textAlign: 'left',
          }}
          onMouseEnter={e => (e.currentTarget.style.borderColor = '#66aa66')}
          onMouseLeave={e => (e.currentTarget.style.borderColor = '#446644')}
        >
          + Create New Quest
          <div style={{ fontSize: '12px', fontWeight: 400, color: '#88cc88', marginTop: '4px' }}>
            Start from scratch with an empty project
          </div>
        </button>

        {/* Game Quests */}
        <h2 style={{ fontSize: '15px', fontWeight: 600, marginBottom: '12px', color: '#aaa' }}>
          Game Quests
          <span style={{ fontSize: '11px', fontWeight: 400, color: '#666', marginLeft: '8px' }}>
            from data/quests/
          </span>
        </h2>

        {loading && (
          <div style={{ color: '#888', fontSize: '13px', padding: '12px' }}>Loading...</div>
        )}
        {error && (
          <div style={{ color: '#ff8888', fontSize: '13px', padding: '12px' }}>{error}</div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginBottom: '32px' }}>
          {gameQuests.map(q => (
            <div
              key={q.filename}
              style={cardStyle}
              onClick={() => handleOpenGameQuest(q.filename)}
              onMouseEnter={e => (e.currentTarget.style.borderColor = '#5588ff')}
              onMouseLeave={e => (e.currentTarget.style.borderColor = '#333')}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span style={{
                  padding: '2px 6px',
                  background: '#334',
                  borderRadius: '4px',
                  fontSize: '10px',
                  color: '#88aaff',
                }}>
                  game
                </span>
                <span style={{ fontWeight: 600, fontSize: '14px' }}>{q.name}</span>
                <span style={{ color: '#666', fontSize: '11px', marginLeft: 'auto' }}>
                  {q.filename}.json
                </span>
              </div>
              {q.description && (
                <div style={{ color: '#888', fontSize: '12px', marginTop: '4px' }}>
                  {q.description}
                </div>
              )}
              <div style={{ color: '#666', fontSize: '11px', marginTop: '4px' }}>
                {q.areaId} &middot; {q.sectionCount} section{q.sectionCount !== 1 ? 's' : ''}
              </div>
            </div>
          ))}
          {!loading && gameQuests.length === 0 && !error && (
            <div style={{ color: '#666', fontSize: '13px', padding: '12px' }}>
              No game quests found
            </div>
          )}
        </div>

        {/* Drafts */}
        <h2 style={{ fontSize: '15px', fontWeight: 600, marginBottom: '12px', color: '#aaa' }}>
          Editor Drafts
          <span style={{ fontSize: '11px', fontWeight: 400, color: '#666', marginLeft: '8px' }}>
            from localStorage
          </span>
        </h2>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {drafts.map(d => (
            <div
              key={d.id}
              style={cardStyle}
              onClick={() => handleOpenDraft(d.id)}
              onMouseEnter={e => (e.currentTarget.style.borderColor = '#5588ff')}
              onMouseLeave={e => (e.currentTarget.style.borderColor = '#333')}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span style={{
                  padding: '2px 6px',
                  background: '#343',
                  borderRadius: '4px',
                  fontSize: '10px',
                  color: '#88cc88',
                }}>
                  draft
                </span>
                <span style={{ fontWeight: 600, fontSize: '14px' }}>{d.name}</span>
                <span style={{ color: '#666', fontSize: '11px', marginLeft: 'auto' }}>
                  {new Date(d.lastModified).toLocaleDateString()}
                </span>
              </div>
              <div style={{ color: '#666', fontSize: '11px', marginTop: '4px' }}>
                {d.areaKey}-{d.variant} &middot; {d.cellCount} cells
              </div>
            </div>
          ))}
          {drafts.length === 0 && (
            <div style={{ color: '#666', fontSize: '13px', padding: '12px' }}>
              No drafts saved yet
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
