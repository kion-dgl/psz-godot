/**
 * MetadataTab — Edit quest metadata: name, description, type, difficulty, level
 */

import { useCallback } from 'react';
import type { QuestProject, QuestMetadata } from '../types';

interface MetadataTabProps {
  project: QuestProject;
  onUpdateProject: (updater: (prev: QuestProject) => QuestProject) => void;
}

const QUEST_TYPES: { value: QuestMetadata['questType']; label: string; desc: string }[] = [
  { value: 'exploration', label: 'Exploration', desc: 'Reach the end of the field' },
  { value: 'hunt', label: 'Hunt', desc: 'Defeat a target enemy or boss' },
  { value: 'collection', label: 'Collection', desc: 'Gather items from the field' },
  { value: 'escort', label: 'Escort', desc: 'Protect an NPC through the field' },
  { value: 'story', label: 'Story', desc: 'Narrative-driven with cutscenes' },
];

const DIFFICULTIES: { value: string; label: string; color: string }[] = [
  { value: 'normal', label: 'Normal', color: '#88ff88' },
  { value: 'hard', label: 'Hard', color: '#ffcc44' },
  { value: 'super', label: 'Super Hard', color: '#ff6666' },
];

export default function MetadataTab({ project, onUpdateProject }: MetadataTabProps) {
  const meta = project.metadata;

  const updateMeta = useCallback(<K extends keyof QuestMetadata>(key: K, value: QuestMetadata[K]) => {
    onUpdateProject(prev => ({
      ...prev,
      metadata: { ...prev.metadata, [key]: value },
    }));
  }, [onUpdateProject]);

  const updateName = useCallback((name: string) => {
    onUpdateProject(prev => ({ ...prev, name }));
  }, [onUpdateProject]);

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

        {/* Quest Type */}
        <div>
          <label style={labelStyle}>Quest Type</label>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            {QUEST_TYPES.map(qt => {
              const selected = meta.questType === qt.value;
              return (
                <div
                  key={qt.value}
                  onClick={() => updateMeta('questType', qt.value)}
                  style={{
                    padding: '10px 14px',
                    background: selected ? '#3a3a6a' : '#1a1a2e',
                    border: `1px solid ${selected ? '#88aaff' : '#333'}`,
                    borderRadius: '6px',
                    cursor: 'pointer',
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                  }}
                >
                  <div>
                    <span style={{ fontSize: '13px', fontWeight: 600, color: selected ? '#88aaff' : '#ccc' }}>
                      {qt.label}
                    </span>
                    <span style={{ fontSize: '11px', color: '#888', marginLeft: '8px' }}>
                      {qt.desc}
                    </span>
                  </div>
                  {selected && (
                    <div style={{ width: 8, height: 8, borderRadius: '50%', background: '#88aaff' }} />
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Difficulty */}
        <div>
          <label style={labelStyle}>Difficulty</label>
          <div style={{ display: 'flex', gap: '8px' }}>
            {DIFFICULTIES.map(d => {
              const selected = meta.difficulty === d.value;
              return (
                <button
                  key={d.value}
                  onClick={() => updateMeta('difficulty', d.value as QuestMetadata['difficulty'])}
                  style={{
                    flex: 1,
                    padding: '10px',
                    background: selected ? d.color + '22' : '#1a1a2e',
                    border: `1px solid ${selected ? d.color : '#333'}`,
                    borderRadius: '6px',
                    color: selected ? d.color : '#888',
                    fontSize: '13px',
                    fontWeight: selected ? 700 : 400,
                    cursor: 'pointer',
                  }}
                >
                  {d.label}
                </button>
              );
            })}
          </div>
        </div>

        {/* Recommended Level */}
        <div>
          <label style={labelStyle}>Recommended Level</label>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <input
              type="range"
              min={1}
              max={200}
              value={meta.recommendedLevel}
              onChange={(e) => updateMeta('recommendedLevel', parseInt(e.target.value))}
              style={{ flex: 1 }}
            />
            <input
              type="number"
              min={1}
              max={200}
              value={meta.recommendedLevel}
              onChange={(e) => updateMeta('recommendedLevel', Math.max(1, Math.min(200, parseInt(e.target.value) || 1)))}
              style={{
                ...inputStyle,
                width: '70px',
                textAlign: 'center',
              }}
            />
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
