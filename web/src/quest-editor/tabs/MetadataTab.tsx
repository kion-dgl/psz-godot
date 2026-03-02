/**
 * MetadataTab — Edit quest metadata: name, description, companions, briefing dialog
 */

import { useCallback } from 'react';
import type { QuestProject, QuestMetadata, QuestObjective, OfficeNpc, ReportDestination } from '../types';
import { AVAILABLE_COMPANIONS, OFFICE_POSITIONS } from '../types';

interface MetadataTabProps {
  project: QuestProject;
  onUpdateProject: (updater: (prev: QuestProject) => QuestProject) => void;
  isMobile?: boolean;
}

const NPC_OPTIONS = [
  { id: 'kai', name: 'Kai' },
  { id: 'sarisa', name: 'Sarisa' },
  { id: 'elio', name: 'Elio' },
  { id: 'fern', name: 'Fern' },
];

export default function MetadataTab({ project, onUpdateProject, isMobile }: MetadataTabProps) {
  const meta = project.metadata;
  const officeNpcs = meta.officeNpcs || [];
  const briefingDialog = meta.briefingDialog || [];
  const objectives = meta.objectives || [];
  const reportTo = meta.reportTo || 'guild_counter';

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

  // -- Office NPCs --
  const addOfficeNpc = useCallback(() => {
    updateMeta('officeNpcs', [...officeNpcs, { npc_id: '', npc_name: '', office_position: 'pos_2' }]);
  }, [officeNpcs, updateMeta]);

  const updateOfficeNpc = useCallback((idx: number, updates: Partial<OfficeNpc>) => {
    const next = officeNpcs.map((n, i) => i === idx ? { ...n, ...updates } : n);
    updateMeta('officeNpcs', next);
  }, [officeNpcs, updateMeta]);

  const removeOfficeNpc = useCallback((idx: number) => {
    updateMeta('officeNpcs', officeNpcs.filter((_, i) => i !== idx));
  }, [officeNpcs, updateMeta]);

  // -- Briefing Dialog --
  const addDialogPage = useCallback(() => {
    updateMeta('briefingDialog', [...briefingDialog, { speaker: '', text: '' }]);
  }, [briefingDialog, updateMeta]);

  const updateDialogPage = useCallback((idx: number, field: 'speaker' | 'text', value: string) => {
    const next = briefingDialog.map((p, i) => i === idx ? { ...p, [field]: value } : p);
    updateMeta('briefingDialog', next);
  }, [briefingDialog, updateMeta]);

  const removeDialogPage = useCallback((idx: number) => {
    updateMeta('briefingDialog', briefingDialog.filter((_, i) => i !== idx));
  }, [briefingDialog, updateMeta]);

  const moveDialogPage = useCallback((idx: number, dir: -1 | 1) => {
    const next = [...briefingDialog];
    const target = idx + dir;
    if (target < 0 || target >= next.length) return;
    [next[idx], next[target]] = [next[target], next[idx]];
    updateMeta('briefingDialog', next);
  }, [briefingDialog, updateMeta]);

  // -- Objectives --
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

  // Build speaker options: Principal (always) + office NPCs + companions
  const speakerOptions: Array<{ value: string; label: string }> = [
    { value: 'Principal', label: 'Principal' },
  ];
  for (const npc of officeNpcs) {
    if (npc.npc_name && !speakerOptions.some(s => s.value === npc.npc_name)) {
      speakerOptions.push({ value: npc.npc_name, label: npc.npc_name });
    }
  }
  for (const cid of (meta.companions || [])) {
    const comp = AVAILABLE_COMPANIONS.find(c => c.id === cid);
    if (comp && !speakerOptions.some(s => s.value === comp.name)) {
      speakerOptions.push({ value: comp.name, label: comp.name });
    }
  }

  return (
    <div style={{
      flex: 1, display: 'flex', justifyContent: 'center',
      overflow: 'auto', padding: isMobile ? '16px 12px' : '32px 24px',
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
                  flexWrap: isMobile ? 'wrap' : undefined,
                }}
              >
                <input
                  type="text"
                  value={obj.item_id}
                  onChange={(e) => updateObjective(oi, { item_id: e.target.value })}
                  placeholder="item_id"
                  style={{
                    width: isMobile ? '100%' : '120px', padding: '4px 6px', background: '#111',
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

        {/* Report Destination */}
        <div>
          <label style={labelStyle}>Report Destination</label>
          <div style={{ display: 'flex', gap: '8px' }}>
            {([['guild_counter', 'Guild Counter'], ['office', "Principal's Office"]] as const).map(([val, label]) => {
              const active = reportTo === val;
              return (
                <button
                  key={val}
                  onClick={() => updateMeta('reportTo', val as ReportDestination)}
                  style={{
                    padding: '8px 16px',
                    background: active ? '#2a3a5a' : '#1a1a2e',
                    border: `1px solid ${active ? '#6688cc' : '#333'}`,
                    borderRadius: '6px',
                    color: active ? '#88bbff' : '#888',
                    fontSize: '13px',
                    fontWeight: active ? 600 : 400,
                    cursor: 'pointer',
                  }}
                >
                  {label}
                </button>
              );
            })}
          </div>
          <div style={{ fontSize: '11px', color: '#666', marginTop: '4px' }}>
            Where the player reports after completing the quest.
          </div>
        </div>

        {/* Office NPCs */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
            <label style={{ ...labelStyle, marginBottom: 0 }}>Office NPCs</label>
            <button
              onClick={addOfficeNpc}
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
              + NPC
            </button>
          </div>
          <div style={{ fontSize: '11px', color: '#666', marginBottom: '8px' }}>
            NPCs placed in the office during the quest briefing. Principal is always present.
          </div>

          {officeNpcs.length === 0 && (
            <div style={{
              padding: '16px',
              background: '#1a1a2e',
              border: '1px dashed #333',
              borderRadius: '6px',
              color: '#555',
              fontSize: '12px',
              textAlign: 'center',
            }}>
              No extra NPCs. Click "+ NPC" to add one.
            </div>
          )}

          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            {officeNpcs.map((npc, ni) => (
              <div
                key={ni}
                style={{
                  display: 'flex', gap: '6px', alignItems: 'center',
                  padding: '8px',
                  background: '#1a1a2e',
                  border: '1px solid #333',
                  borderRadius: '6px',
                  flexWrap: isMobile ? 'wrap' : undefined,
                }}
              >
                <select
                  value={npc.npc_id}
                  onChange={(e) => {
                    const opt = NPC_OPTIONS.find(n => n.id === e.target.value);
                    updateOfficeNpc(ni, { npc_id: e.target.value, npc_name: opt?.name || '' });
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
                <select
                  value={npc.office_position}
                  onChange={(e) => updateOfficeNpc(ni, { office_position: e.target.value })}
                  style={{
                    width: '110px', padding: '4px', background: '#111',
                    border: '1px solid #444', borderRadius: '3px',
                    color: '#fff', fontSize: '11px',
                  }}
                >
                  {OFFICE_POSITIONS.map(p => (
                    <option key={p.id} value={p.id}>{p.label}</option>
                  ))}
                </select>
                <button
                  onClick={() => removeOfficeNpc(ni)}
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

        {/* Briefing Dialog */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
            <label style={{ ...labelStyle, marginBottom: 0 }}>Briefing Dialog</label>
            <button
              onClick={addDialogPage}
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
              + Page
            </button>
          </div>
          <div style={{ fontSize: '11px', color: '#666', marginBottom: '8px' }}>
            Dialog played in the principal's office after quest acceptance.
          </div>

          {briefingDialog.length === 0 && (
            <div style={{
              padding: '16px',
              background: '#1a1a2e',
              border: '1px dashed #333',
              borderRadius: '6px',
              color: '#555',
              fontSize: '12px',
              textAlign: 'center',
            }}>
              No briefing dialog. Click "+ Page" to add one.
            </div>
          )}

          <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
            {briefingDialog.map((page, pi) => (
              <div
                key={pi}
                style={{
                  padding: '6px',
                  background: '#1a1a2e',
                  border: '1px solid #333',
                  borderRadius: '4px',
                }}
              >
                <div style={{ display: 'flex', gap: '4px', marginBottom: '4px' }}>
                  <select
                    value={page.speaker}
                    onChange={(e) => updateDialogPage(pi, 'speaker', e.target.value)}
                    style={{
                      width: '120px', padding: '3px 6px', background: '#111',
                      border: '1px solid #444', borderRadius: '3px',
                      color: '#fff', fontSize: '11px',
                    }}
                  >
                    <option value="">-- speaker --</option>
                    {speakerOptions.map(s => (
                      <option key={s.value} value={s.value}>{s.label}</option>
                    ))}
                  </select>
                  <div style={{ flex: 1 }} />
                  <button
                    onClick={() => moveDialogPage(pi, -1)}
                    disabled={pi === 0}
                    style={{
                      padding: '1px 5px', background: 'none',
                      border: '1px solid #444', borderRadius: '3px',
                      color: pi === 0 ? '#333' : '#666', fontSize: '10px',
                      cursor: pi === 0 ? 'default' : 'pointer',
                    }}
                  >
                    ^
                  </button>
                  <button
                    onClick={() => moveDialogPage(pi, 1)}
                    disabled={pi === briefingDialog.length - 1}
                    style={{
                      padding: '1px 5px', background: 'none',
                      border: '1px solid #444', borderRadius: '3px',
                      color: pi === briefingDialog.length - 1 ? '#333' : '#666', fontSize: '10px',
                      cursor: pi === briefingDialog.length - 1 ? 'default' : 'pointer',
                    }}
                  >
                    v
                  </button>
                  <button
                    onClick={() => removeDialogPage(pi)}
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
                  onChange={(e) => updateDialogPage(pi, 'text', e.target.value)}
                  placeholder="Dialog text..."
                  rows={2}
                  style={{
                    width: '100%', padding: '4px 6px', background: '#111',
                    border: '1px solid #2a2a2a', borderRadius: '3px',
                    color: '#fff', fontSize: '12px', fontFamily: 'inherit',
                    resize: 'vertical', lineHeight: 1.4,
                    boxSizing: 'border-box',
                  }}
                />
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
