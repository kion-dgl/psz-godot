/**
 * SfxLabeler — Browse and label PSOBB sound effects.
 *
 * Loads WAV files from web/public/psobb_sfx/{category}/*.wav,
 * lets you play them, assign labels (e.g. "saber_swing_1", "menu_cursor"),
 * and export the mapping as JSON.
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { assetUrl } from '../utils/assets';

const CATEGORIES = [
  'common', 'forest', 'cave', 'machine', 'ruin', 'ancient',
  'city', 'boss01', 'boss02', 'boss03', 'boss04', 'boss05',
  'boss06', 'boss07', 'boss08', 'tower', 'jungle', 'water',
  'beach', 'ship', 'duel01', 'duel02', 'ephinea',
];

// Label presets for quick tagging
const LABEL_PRESETS = [
  // UI
  'menu_cursor', 'menu_confirm', 'menu_cancel', 'menu_open', 'menu_error',
  'level_up', 'item_pickup', 'quest_complete', 'gate_open', 'treasure',
  // Weapons
  'saber_swing', 'sword_swing', 'dagger_swing', 'spear_swing', 'claw_swing',
  'double_saber_swing', 'handgun_fire', 'rifle_fire', 'gunblade_swing',
  'machinegun_fire', 'slicer_throw', 'rod_swing', 'wand_swing', 'shield_bash',
  // Combat
  'hit_melee', 'hit_ranged', 'hit_critical', 'player_damage', 'player_death',
  'enemy_damage', 'enemy_death', 'dodge',
  // Techniques
  'tech_foie', 'tech_barta', 'tech_zonde', 'tech_resta', 'tech_grants',
  'tech_megid', 'tech_shifta', 'tech_deband',
  // Enemies
  'enemy_appear', 'enemy_attack', 'enemy_walk', 'enemy_idle',
  'boss_roar', 'boss_attack', 'boss_phase',
  // Environment
  'ambient', 'door', 'switch', 'teleporter', 'box_break', 'trap',
  // Other
  'footstep', 'charge', 'special', 'voice', 'unknown',
];

interface SfxEntry {
  file: string;
  label: string;
  category: string;
  notes: string;
  starred: boolean;
}

// Persistence key
const STORAGE_KEY = 'psz_sfx_labels';

function loadLabels(): Record<string, SfxEntry> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function saveLabels(labels: Record<string, SfxEntry>) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(labels));
}

export default function SfxLabeler() {
  const [category, setCategory] = useState('common');
  const [files, setFiles] = useState<string[]>([]);
  const [labels, setLabels] = useState<Record<string, SfxEntry>>(loadLabels);
  const [loaded, setLoaded] = useState(false);

  // Load saved labels from data/sfx_labels.json on first mount
  useEffect(() => {
    if (loaded) return;
    fetch(assetUrl('data/sfx_labels.json'))
      .then(r => r.ok ? r.json() : null)
      .then(data => {
        if (data) {
          setLabels(prev => {
            // File labels are base, localStorage overrides
            const merged = { ...data, ...prev };
            return merged;
          });
        }
      })
      .catch(() => {})
      .finally(() => setLoaded(true));
  }, [loaded]);
  const [playing, setPlaying] = useState<string | null>(null);
  const [filter, setFilter] = useState<'all' | 'unlabeled' | 'starred' | 'labeled'>('all');
  const [search, setSearch] = useState('');
  const audioRef = useRef<HTMLAudioElement | null>(null);

  // Load file list for category
  useEffect(() => {
    // Generate file list (we know the pattern: {category}_{000-999}.wav)
    // We'll try loading sequentially until we get a 404
    const loadFiles = async () => {
      const found: string[] = [];
      for (let i = 0; i < 300; i++) {
        const name = `${category}_${i.toString().padStart(3, '0')}.wav`;
        const url = assetUrl(`psobb_sfx/${category}/${name}`);
        try {
          const res = await fetch(url, { method: 'HEAD' });
          if (res.ok) {
            found.push(name);
          } else {
            // Allow gaps up to 5
            if (found.length > 0 && i - found.length > 5) break;
          }
        } catch {
          break;
        }
      }
      setFiles(found);
    };
    loadFiles();
  }, [category]);

  // Save labels on change
  useEffect(() => {
    saveLabels(labels);
  }, [labels]);

  const playSound = useCallback((file: string) => {
    if (audioRef.current) {
      audioRef.current.pause();
    }
    const url = assetUrl(`psobb_sfx/${category}/${file}`);
    const audio = new Audio(url);
    audioRef.current = audio;
    setPlaying(file);
    audio.play();
    audio.onended = () => setPlaying(null);
  }, [category]);

  const updateEntry = useCallback((file: string, updates: Partial<SfxEntry>) => {
    const key = `${category}/${file}`;
    setLabels(prev => {
      const existing = prev[key] || { file, category, label: '', notes: '', starred: false };
      return { ...prev, [key]: { ...existing, ...updates } };
    });
  }, [category]);

  const getEntry = (file: string): SfxEntry | undefined => {
    return labels[`${category}/${file}`];
  };

  const filteredFiles = files.filter(file => {
    const entry = getEntry(file);
    if (filter === 'unlabeled' && entry?.label) return false;
    if (filter === 'starred' && !entry?.starred) return false;
    if (filter === 'labeled' && !entry?.label) return false;
    if (search && entry?.label && !entry.label.includes(search) && !file.includes(search)) return false;
    if (search && !entry?.label && !file.includes(search)) return false;
    return true;
  });

  const [copied, setCopied] = useState(false);

  const exportJSON = () => {
    // Export full labels map — only entries that have a label, star, or notes
    const filtered: Record<string, SfxEntry> = {};
    for (const [key, entry] of Object.entries(labels)) {
      if (entry.label || entry.starred || entry.notes) {
        filtered[key] = entry;
      }
    }
    const json = JSON.stringify(filtered, null, 2);
    navigator.clipboard.writeText(json);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const importJSON = () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json';
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) return;
      const text = await file.text();
      try {
        const imported = JSON.parse(text) as Record<string, SfxEntry>;
        setLabels(prev => ({ ...prev, ...imported }));
      } catch {
        alert('Invalid JSON file');
      }
    };
    input.click();
  };

  const stats = {
    total: files.length,
    labeled: files.filter(f => getEntry(f)?.label).length,
    starred: files.filter(f => getEntry(f)?.starred).length,
  };

  return (
    <div style={{ display: 'flex', height: '100vh', background: '#0a0a1a', color: '#ccc', fontFamily: 'sans-serif' }}>
      {/* Sidebar */}
      <div style={{
        width: '220px', borderRight: '1px solid #333', overflow: 'auto',
        display: 'flex', flexDirection: 'column',
      }}>
        <div style={{ padding: '12px', borderBottom: '1px solid #333' }}>
          <div style={{ fontSize: '14px', fontWeight: 'bold', color: '#fff', marginBottom: '8px' }}>
            SFX Labeler
          </div>
          <div style={{ fontSize: '11px', color: '#666' }}>
            {Object.values(labels).filter(e => e.label).length} labeled total
          </div>
        </div>
        <div style={{ flex: 1, overflow: 'auto' }}>
          {CATEGORIES.map(cat => {
            const catLabeled = Object.entries(labels).filter(([k, v]) => k.startsWith(cat + '/') && v.label).length;
            return (
              <button
                key={cat}
                onClick={() => setCategory(cat)}
                style={{
                  display: 'block', width: '100%', padding: '8px 12px',
                  background: category === cat ? '#1a2a4a' : 'transparent',
                  border: 'none', borderBottom: '1px solid #1a1a2e',
                  color: category === cat ? '#88bbff' : '#888',
                  textAlign: 'left', cursor: 'pointer', fontSize: '13px',
                }}
              >
                {cat} {catLabeled > 0 && <span style={{ color: '#66aa66', fontSize: '11px' }}>({catLabeled})</span>}
              </button>
            );
          })}
        </div>
        <div style={{ padding: '8px', borderTop: '1px solid #333', display: 'flex', flexDirection: 'column', gap: '4px' }}>
          <button onClick={exportJSON} style={{
            width: '100%', padding: '8px',
            background: copied ? '#2a4a2a' : '#224422',
            border: `1px solid ${copied ? '#66aa66' : '#446644'}`, borderRadius: '4px',
            color: copied ? '#88ff88' : '#88cc88', fontSize: '12px', cursor: 'pointer',
          }}>
            {copied ? 'Copied!' : 'Copy Labels JSON'}
          </button>
          <button onClick={importJSON} style={{
            width: '100%', padding: '8px', background: '#222244',
            border: '1px solid #444466', borderRadius: '4px',
            color: '#8888cc', fontSize: '12px', cursor: 'pointer',
          }}>
            Import Labels JSON
          </button>
        </div>
      </div>

      {/* Main content */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* Toolbar */}
        <div style={{
          padding: '8px 16px', borderBottom: '1px solid #333',
          display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap',
        }}>
          <span style={{ fontSize: '14px', fontWeight: 'bold', color: '#fff' }}>{category}</span>
          <span style={{ fontSize: '11px', color: '#666' }}>
            {stats.labeled}/{stats.total} labeled, {stats.starred} starred
          </span>
          <div style={{ flex: 1 }} />
          {(['all', 'unlabeled', 'labeled', 'starred'] as const).map(f => (
            <button key={f} onClick={() => setFilter(f)} style={{
              padding: '4px 10px', fontSize: '11px', borderRadius: '4px', cursor: 'pointer',
              background: filter === f ? '#4a9eff' : '#333',
              color: filter === f ? '#fff' : '#888',
              border: 'none',
            }}>
              {f}
            </button>
          ))}
          <input
            type="text" placeholder="Search..."
            value={search} onChange={e => setSearch(e.target.value)}
            style={{
              padding: '4px 8px', background: '#111', border: '1px solid #444',
              borderRadius: '4px', color: '#fff', fontSize: '12px', width: '120px',
            }}
          />
        </div>

        {/* Sound list */}
        <div style={{ flex: 1, overflow: 'auto', padding: '8px' }}>
          {filteredFiles.map(file => {
            const entry = getEntry(file);
            const isPlaying = playing === file;
            return (
              <div
                key={file}
                style={{
                  display: 'flex', alignItems: 'center', gap: '8px',
                  padding: '6px 8px', marginBottom: '2px',
                  background: isPlaying ? '#1a2a3a' : entry?.label ? '#0a1a0a' : '#0a0a14',
                  borderRadius: '4px', border: `1px solid ${isPlaying ? '#4a9eff' : entry?.starred ? '#aa8844' : '#1a1a2e'}`,
                }}
              >
                {/* Play button */}
                <button
                  onClick={() => playSound(file)}
                  style={{
                    width: '32px', height: '32px', borderRadius: '50%',
                    background: isPlaying ? '#4a9eff' : '#333',
                    border: 'none', color: '#fff', cursor: 'pointer',
                    fontSize: '14px', flexShrink: 0,
                  }}
                >
                  {isPlaying ? '||' : '\u25B6'}
                </button>

                {/* File name */}
                <span style={{ fontSize: '11px', color: '#666', width: '140px', flexShrink: 0, fontFamily: 'monospace' }}>
                  {file}
                </span>

                {/* Star */}
                <button
                  onClick={() => updateEntry(file, { starred: !entry?.starred })}
                  style={{
                    background: 'none', border: 'none', cursor: 'pointer',
                    color: entry?.starred ? '#ffaa44' : '#333', fontSize: '16px', flexShrink: 0,
                  }}
                >
                  {entry?.starred ? '\u2605' : '\u2606'}
                </button>

                {/* Label select */}
                <select
                  value={entry?.label || ''}
                  onChange={e => updateEntry(file, { label: e.target.value })}
                  style={{
                    flex: 1, padding: '4px', background: '#111', border: '1px solid #333',
                    borderRadius: '3px', color: entry?.label ? '#88ff88' : '#666',
                    fontSize: '12px', maxWidth: '200px',
                  }}
                >
                  <option value="">-- label --</option>
                  {LABEL_PRESETS.map(l => (
                    <option key={l} value={l}>{l}</option>
                  ))}
                </select>

                {/* Custom label input */}
                <input
                  type="text"
                  value={entry?.label || ''}
                  onChange={e => updateEntry(file, { label: e.target.value })}
                  placeholder="custom label"
                  style={{
                    width: '150px', padding: '4px 6px', background: '#111',
                    border: '1px solid #333', borderRadius: '3px',
                    color: '#fff', fontSize: '11px', fontFamily: 'monospace',
                  }}
                />

                {/* Notes */}
                <input
                  type="text"
                  value={entry?.notes || ''}
                  onChange={e => updateEntry(file, { notes: e.target.value })}
                  placeholder="notes"
                  style={{
                    width: '120px', padding: '4px 6px', background: '#111',
                    border: '1px solid #222', borderRadius: '3px',
                    color: '#888', fontSize: '11px',
                  }}
                />
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
