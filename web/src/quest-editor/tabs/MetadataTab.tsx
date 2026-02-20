/**
 * MetadataTab — Edit quest metadata: name, description, companions, city dialog
 */

import { useCallback } from 'react';
import type { QuestProject, QuestMetadata, CityDialogScene, QuestObjective } from '../types';
import { AVAILABLE_COMPANIONS } from '../types';

interface MetadataTabProps {
  project: QuestProject;
  onUpdateProject: (updater: (prev: QuestProject) => QuestProject) => void;
}

const NPC_OPTIONS = [
  { id: 'guild_counter', name: 'Guild Counter' },
  { id: 'kai', name: 'Kai' },
  { id: 'sarisa', name: 'Sarisa' },
];

export default function MetadataTab({ project, onUpdateProject }: MetadataTabProps) {
  const meta = project.metadata;
  const cityDialog = meta.cityDialog || [];
  const objectives = meta.objectives || [];

  const updateMeta = useCallback(<K extends keyof QuestMetadata>(key: K, value: QuestMetadata[K]) => {
    onUpdateProject(prev => ({
      ...prev,
      metadata: { ...prev.metadata, [key]: value },
    }));
  }, [onUpdateProject]);

  const updateName = useCallback((name: string) => {
    onUpdateProject(prev => ({ ...prev, name }));
  }, [onUpdateProject]);

  const toggleCompanion = useCallback((companionId: string) => {
    onUpdateProject(prev => {
      const current = prev.metadata.companions || [];
      const next = current.includes(companionId)
        ? current.filter(id => id !== companionId)
        : [...current, companionId];
      return { ...prev, metadata: { ...prev.metadata, companions: next } };
    });
  }, [onUpdateProject]);

  const addScene = useCallback(() => {
    const newScene: CityDialogScene = { npc_id: '', npc_name: '', dialog: [{ speaker: '', text: '' }] };
    updateMeta('cityDialog', [...cityDialog, newScene]);
  }, [cityDialog, updateMeta]);

  const updateScene = useCallback((idx: number, updates: Partial<CityDialogScene>) => {
    const next = cityDialog.map((s, i) => i === idx ? { ...s, ...updates } : s);
    updateMeta('cityDialog', next);
  }, [cityDialog, updateMeta]);

  const removeScene = useCallback((idx: number) => {
    updateMeta('cityDialog', cityDialog.filter((_, i) => i !== idx));
  }, [cityDialog, updateMeta]);

  const moveScene = useCallback((idx: number, dir: -1 | 1) => {
    const next = [...cityDialog];
    const target = idx + dir;
    if (target < 0 || target >= next.length) return;
    [next[idx], next[target]] = [next[target], next[idx]];
    updateMeta('cityDialog', next);
  }, [cityDialog, updateMeta]);

  const updateDialogPage = useCallback((sceneIdx: number, pageIdx: number, field: 'speaker' | 'text', value: string) => {
    const scene = cityDialog[sceneIdx];
    const pages = (scene.dialog || []).map((p, i) => i === pageIdx ? { ...p, [field]: value } : p);
    updateScene(sceneIdx, { dialog: pages });
  }, [cityDialog, updateScene]);

  const addDialogPage = useCallback((sceneIdx: number) => {
    const scene = cityDialog[sceneIdx];
    updateScene(sceneIdx, { dialog: [...(scene.dialog || []), { speaker: scene.npc_name || '', text: '' }] });
  }, [cityDialog, updateScene]);

  const removeDialogPage = useCallback((sceneIdx: number, pageIdx: number) => {
    const scene = cityDialog[sceneIdx];
    updateScene(sceneIdx, { dialog: (scene.dialog || []).filter((_, i) => i !== pageIdx) });
  }, [cityDialog, updateScene]);

  const addObjective = useCallback(() => {
    updateMeta('objectives', [...objectives, { item_id: '', label: '', target: 1 }]);
  }, [objectives, updateMeta]);

  const updateObjective = useCallback((idx: number, updates: Partial<QuestObjective>) => {
    const next = objectives.map((o, i) => i === idx ? { ...o, ...updates } : o);
    updateMeta('objectives', next);
  }, [objectives, updateMeta]);

  const removeObjective = useCallback((idx: number) => {
    updateMeta('objectives', objectives.filter((_, i) => i !== idx));
  }, [objectives, updateMeta]);

  return (
    <div style={{
      flex: 1, display: 'flex', justifyContent: 'center',
      overflow: 'auto', padding: '32px 24px',
    }}>
      <div style={{ maxWidth: '560px', width: '100%', display: 'flex', flexDirection: 'column', gap: '24px' }}>

        {/* Quest Name */}
        <div>
          <label style={labelStyle}>Quest Name</label>
          <input
            type="text"
            value={project.name}
            onChange={(e) => updateName(e.target.value)}
            placeholder="e.g. Valley Expedition"
            style={inputStyle}
          />
        </div>

        {/* Description */}
        <div>
          <label style={labelStyle}>Mission Description</label>
          <textarea
            value={meta.description}
            onChange={(e) => updateMeta('description', e.target.value)}
            placeholder="Describe the mission objective and story context..."
            rows={4}
            style={{ ...inputStyle, resize: 'vertical', lineHeight: 1.6 }}
          />
          <div style={{ fontSize: '11px', color: '#666', marginTop: '4px' }}>
            Shown to the player on the quest board and mission briefing screen.
          </div>
        </div>

        {/* Companions */}
        <div>
          <label style={labelStyle}>Companions</label>
          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            {AVAILABLE_COMPANIONS.map(c => {
              const active = (meta.companions || []).includes(c.id);
              return (
                <button
                  key={c.id}
                  onClick={() => toggleCompanion(c.id)}
                  style={{
                    padding: '8px 16px',
                    background: active ? '#3a5a3a' : '#1a1a2e',
                    border: `1px solid ${active ? '#66aa66' : '#333'}`,
                    borderRadius: '6px',
                    color: active ? '#88ff88' : '#888',
                    fontSize: '13px',
                    fontWeight: active ? 600 : 400,
                    cursor: 'pointer',
                  }}
                >
                  {c.name}
                </button>
              );
            })}
          </div>
          <div style={{ fontSize: '11px', color: '#666', marginTop: '4px' }}>
            NPCs that join the player's party for this quest.
          </div>
        </div>

        {/* Quest Objectives */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
            <label style={{ ...labelStyle, marginBottom: 0 }}>Quest Objectives</label>
            <button
              onClick={addObjective}
              style={{
                padding: '4px 10px',
                background: '#224422',
                border: '1px solid #446644',
                borderRadius: '4px',
                color: '#88cc88',
                fontSize: '11px',
                cursor: 'pointer',
              }}
            >
              + Objective
            </button>
          </div>
          <div style={{ fontSize: '11px', color: '#666', marginBottom: '8px' }}>
            Item collection objectives shown on the field HUD. Place matching quest_item objects in cells.
          </div>

          {objectives.length === 0 && (
            <div style={{
              padding: '16px',
              background: '#1a1a2e',
              border: '1px dashed #333',
              borderRadius: '6px',
              color: '#555',
              fontSize: '12px',
              textAlign: 'center',
            }}>
              No objectives. Click "+ Objective" to add one.
            </div>
          )}

          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            {objectives.map((obj, oi) => (
              <div
                key={oi}
                style={{
                  display: 'flex', gap: '6px', alignItems: 'center',
                  padding: '8px',
                  background: '#1a1a2e',
                  border: '1px solid #333',
                  borderRadius: '6px',
                }}
              >
                <input
                  type="text"
                  value={obj.item_id}
                  onChange={(e) => updateObjective(oi, { item_id: e.target.value })}
                  placeholder="item_id"
                  style={{
                    width: '120px', padding: '4px 6px', background: '#111',
                    border: '1px solid #444', borderRadius: '3px',
                    color: '#ffdd44', fontSize: '11px', fontFamily: 'monospace',
                  }}
                />
                <input
                  type="text"
                  value={obj.label}
                  onChange={(e) => updateObjective(oi, { label: e.target.value })}
                  placeholder="Display label"
                  style={{
                    flex: 1, padding: '4px 6px', background: '#111',
                    border: '1px solid #444', borderRadius: '3px',
                    color: '#fff', fontSize: '12px',
                  }}
                />
                <input
                  type="number"
                  value={obj.target}
                  onChange={(e) => updateObjective(oi, { target: Math.max(1, parseInt(e.target.value) || 1) })}
                  min={1}
                  style={{
                    width: '50px', padding: '4px 6px', background: '#111',
                    border: '1px solid #444', borderRadius: '3px',
                    color: '#fff', fontSize: '12px', textAlign: 'center',
                  }}
                />
                <button
                  onClick={() => removeObjective(oi)}
                  style={{
                    padding: '2px 6px', background: '#442222',
                    border: '1px solid #664444', borderRadius: '3px',
                    color: '#aa6666', fontSize: '11px', cursor: 'pointer',
                  }}
                >
                  X
                </button>
              </div>
            ))}
          </div>
        </div>

        {/* City Dialog */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
            <label style={{ ...labelStyle, marginBottom: 0 }}>City Dialog</label>
            <button
              onClick={addScene}
              style={{
                padding: '4px 10px',
                background: '#224422',
                border: '1px solid #446644',
                borderRadius: '4px',
                color: '#88cc88',
                fontSize: '11px',
                cursor: 'pointer',
              }}
            >
              + Scene
            </button>
          </div>
          <div style={{ fontSize: '11px', color: '#666', marginBottom: '8px' }}>
            Dialog scenes that play in the city before entering the field. Played in order.
          </div>

          {cityDialog.length === 0 && (
            <div style={{
              padding: '16px',
              background: '#1a1a2e',
              border: '1px dashed #333',
              borderRadius: '6px',
              color: '#555',
              fontSize: '12px',
              textAlign: 'center',
            }}>
              No city dialog. Click "+ Scene" to add one.
            </div>
          )}

          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
            {cityDialog.map((scene, si) => (
              <div
                key={si}
                style={{
                  padding: '10px',
                  background: '#1a1a2e',
                  border: '1px solid #333',
                  borderRadius: '6px',
                }}
              >
                {/* Scene header */}
                <div style={{ display: 'flex', gap: '6px', alignItems: 'center', marginBottom: '8px' }}>
                  <span style={{ fontSize: '10px', color: '#888', minWidth: '14px' }}>#{si + 1}</span>
                  <select
                    value={scene.npc_id}
                    onChange={(e) => {
                      const npc = NPC_OPTIONS.find(n => n.id === e.target.value);
                      updateScene(si, { npc_id: e.target.value, npc_name: npc?.name || '' });
                    }}
                    style={{
                      flex: 1, padding: '4px', background: '#111',
                      border: '1px solid #444', borderRadius: '3px',
                      color: '#fff', fontSize: '12px',
                    }}
                  >
                    <option value="">-- select NPC --</option>
                    {NPC_OPTIONS.map(n => (
                      <option key={n.id} value={n.id}>{n.name}</option>
                    ))}
                  </select>
                  <button
                    onClick={() => moveScene(si, -1)}
                    disabled={si === 0}
                    style={{
                      padding: '2px 6px', background: '#2a2a4a',
                      border: '1px solid #444', borderRadius: '3px',
                      color: si === 0 ? '#444' : '#888', fontSize: '11px',
                      cursor: si === 0 ? 'default' : 'pointer',
                    }}
                  >
                    ^
                  </button>
                  <button
                    onClick={() => moveScene(si, 1)}
                    disabled={si === cityDialog.length - 1}
                    style={{
                      padding: '2px 6px', background: '#2a2a4a',
                      border: '1px solid #444', borderRadius: '3px',
                      color: si === cityDialog.length - 1 ? '#444' : '#888', fontSize: '11px',
                      cursor: si === cityDialog.length - 1 ? 'default' : 'pointer',
                    }}
                  >
                    v
                  </button>
                  <button
                    onClick={() => removeScene(si)}
                    style={{
                      padding: '2px 6px', background: '#442222',
                      border: '1px solid #664444', borderRadius: '3px',
                      color: '#aa6666', fontSize: '11px', cursor: 'pointer',
                    }}
                  >
                    X
                  </button>
                </div>

                {/* Dialog pages */}
                {(scene.dialog || []).map((page, pi) => (
                  <div
                    key={pi}
                    style={{
                      padding: '6px',
                      background: '#111',
                      border: '1px solid #2a2a2a',
                      borderRadius: '4px',
                      marginBottom: '4px',
                    }}
                  >
                    <div style={{ display: 'flex', gap: '4px', marginBottom: '4px' }}>
                      <input
                        type="text"
                        value={page.speaker}
                        onChange={(e) => updateDialogPage(si, pi, 'speaker', e.target.value)}
                        placeholder="Speaker"
                        style={{
                          width: '100px', padding: '3px 6px', background: '#1a1a2e',
                          border: '1px solid #333', borderRadius: '3px',
                          color: '#fff', fontSize: '11px',
                        }}
                      />
                      <div style={{ flex: 1 }} />
                      <button
                        onClick={() => removeDialogPage(si, pi)}
                        style={{
                          padding: '1px 5px', background: 'none',
                          border: '1px solid #444', borderRadius: '3px',
                          color: '#666', fontSize: '10px', cursor: 'pointer',
                        }}
                      >
                        X
                      </button>
                    </div>
                    <textarea
                      value={page.text}
                      onChange={(e) => updateDialogPage(si, pi, 'text', e.target.value)}
                      placeholder="Dialog text..."
                      rows={2}
                      style={{
                        width: '100%', padding: '4px 6px', background: '#1a1a2e',
                        border: '1px solid #333', borderRadius: '3px',
                        color: '#fff', fontSize: '12px', fontFamily: 'inherit',
                        resize: 'vertical', lineHeight: 1.4,
                        boxSizing: 'border-box',
                      }}
                    />
                  </div>
                ))}

                <button
                  onClick={() => addDialogPage(si)}
                  style={{
                    width: '100%', padding: '4px',
                    background: '#1a2a1a',
                    border: '1px dashed #446644',
                    borderRadius: '3px',
                    color: '#88cc88', fontSize: '11px', cursor: 'pointer',
                  }}
                >
                  + Page
                </button>
              </div>
            ))}
          </div>
        </div>

      </div>
    </div>
  );
}

const labelStyle: React.CSSProperties = {
  display: 'block',
  fontSize: '11px',
  color: '#888',
  textTransform: 'uppercase',
  letterSpacing: '0.5px',
  marginBottom: '6px',
};

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '10px 12px',
  background: '#1a1a2e',
  border: '1px solid #333',
  borderRadius: '6px',
  color: '#fff',
  fontSize: '14px',
  fontFamily: 'inherit',
  boxSizing: 'border-box',
};
