/**
 * SfxLabeler — Browse and label PSOBB sound effects.
 *
 * Loads WAV files from web/public/assets/psobb_sfx/{category}/*.wav
 * (served via /assets/psobb_sfx/... through assetUrl() → CDN in prod),
 * lets you play them, assign labels (e.g. "saber_swing_1", "menu_cursor"),
 * and export the mapping as JSON.
 */

import { useState, useEffect, useCallback, useRef, memo } from 'react';
import { assetUrl } from '../utils/assets';

const PAGE_SIZE = 30;

const CATEGORIES = [
  'common', 'forest', 'cave', 'machine', 'ruin', 'ancient',
  'city', 'boss01', 'boss02', 'boss03', 'boss04', 'boss05',
  'boss06', 'boss07', 'boss08', 'boss09', 'tower', 'jungle', 'water',
  'beach', 'ship', 'duel01', 'duel02', 'ephinea',
  'crater', 'desert', 'wilds',
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
  const [lastPlayed, setLastPlayed] = useState<string | null>(null);
  const [filter, setFilter] = useState<'all' | 'unlabeled' | 'starred' | 'labeled'>('all');
  const [search, setSearch] = useState('');
  const [autoAdvance, setAutoAdvance] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const autoAdvanceRef = useRef(autoAdvance);
  autoAdvanceRef.current = autoAdvance;

  // Load file list from manifest
  const [manifest, setManifest] = useState<Record<string, string[]>>({});
  useEffect(() => {
    fetch(assetUrl('assets/psobb_sfx/manifest.json'))
      .then(r => r.json())
      .then(data => setManifest(data))
      .catch(() => {});
  }, []);

  useEffect(() => {
    setFiles(manifest[category] || []);
  }, [category, manifest]);

  // Save labels on change
  useEffect(() => {
    saveLabels(labels);
  }, [labels]);

  const filteredFilesRef = useRef<string[]>([]);

  const playSound = useCallback((file: string) => {
    if (audioRef.current) {
      audioRef.current.pause();
    }
    const url = assetUrl(`assets/psobb_sfx/${category}/${file}`);
    const audio = new Audio(url);
    audioRef.current = audio;
    setPlaying(file);
    setLastPlayed(file);
    // Jump to the page containing this file
    const ff = filteredFilesRef.current;
    const fileIdx = ff.indexOf(file);
    if (fileIdx >= 0) {
      const targetPage = Math.floor(fileIdx / PAGE_SIZE);
      setPage(targetPage);
    }
    audio.play();
    audio.onended = () => {
      if (autoAdvanceRef.current) {
        const ff = filteredFilesRef.current;
        const idx = ff.indexOf(file);
        if (idx >= 0 && idx < ff.length - 1) {
          // Small delay so the UI updates
          setTimeout(() => playSound(ff[idx + 1]), 150);
          return;
        }
      }
      setPlaying(null);
    };
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
  filteredFilesRef.current = filteredFiles;

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

  const [page, setPage] = useState(0);

  // Reset page when category or filter changes
  useEffect(() => { setPage(0); }, [category, filter, search]);

  const totalPages = Math.ceil(filteredFiles.length / PAGE_SIZE);
  const pagedFiles = filteredFiles.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);

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
          {CATEGORIES.filter(cat => (manifest[cat]?.length || 0) > 0).map(cat => {
            const catTotal = manifest[cat]?.length || 0;
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
                {cat} <span style={{ color: '#555', fontSize: '11px' }}>({catTotal})</span>
                {catLabeled > 0 && <span style={{ color: '#66aa66', fontSize: '11px' }}> {catLabeled}</span>}
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
        {/* Playback bar */}
        <div style={{
          padding: '8px 16px', borderBottom: '1px solid #222',
          display: 'flex', gap: '8px', alignItems: 'center',
          background: '#0d0d1e',
        }}>
          <button onClick={() => {
            const idx = filteredFiles.indexOf(playing || '');
            const prev = idx > 0 ? idx - 1 : filteredFiles.length - 1;
            if (filteredFiles[prev]) playSound(filteredFiles[prev]);
          }} style={transportBtnStyle} title="Previous (Shift+Left)">
            {'\u23EE'}
          </button>
          <button onClick={() => {
            if (playing && audioRef.current) { audioRef.current.pause(); setPlaying(null); }
            else if (filteredFiles.length > 0) playSound(filteredFiles[0]);
          }} style={{ ...transportBtnStyle, width: '40px', fontSize: '18px', background: playing ? '#4a9eff' : '#333' }}>
            {playing ? '\u23F9' : '\u25B6'}
          </button>
          <button onClick={() => {
            const idx = filteredFiles.indexOf(playing || '');
            const next = idx >= 0 && idx < filteredFiles.length - 1 ? idx + 1 : 0;
            playSound(filteredFiles[next]);
          }} style={transportBtnStyle} title="Next (Shift+Right)">
            {'\u23ED'}
          </button>
          <button onClick={() => setAutoAdvance(a => !a)} style={{
            ...transportBtnStyle,
            background: autoAdvance ? '#2a4a2a' : '#333',
            color: autoAdvance ? '#88ff88' : '#888',
            fontSize: '11px', width: 'auto', padding: '4px 10px',
          }} title="Auto-advance to next sound when current finishes">
            Auto
          </button>
          <span style={{
            flex: 1, fontSize: '12px', fontFamily: 'monospace',
            color: playing ? '#4a9eff' : '#555',
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>
            {playing || 'No sound playing'}
          </span>
          {playing && getEntry(playing)?.label && (
            <span style={{ fontSize: '11px', color: '#88ff88' }}>{getEntry(playing)?.label}</span>
          )}
        </div>

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

        {/* Pagination */}
        {totalPages > 1 && (
          <div style={{
            padding: '6px 16px', borderBottom: '1px solid #333',
            display: 'flex', gap: '4px', alignItems: 'center',
          }}>
            <button
              onClick={() => setPage(p => Math.max(0, p - 1))}
              disabled={page === 0}
              style={{ ...pageBtnStyle, opacity: page === 0 ? 0.3 : 1 }}
            >
              Prev
            </button>
            <span style={{ fontSize: '12px', color: '#888', minWidth: '80px', textAlign: 'center' }}>
              {page + 1} / {totalPages}
            </span>
            <button
              onClick={() => setPage(p => Math.min(totalPages - 1, p + 1))}
              disabled={page >= totalPages - 1}
              style={{ ...pageBtnStyle, opacity: page >= totalPages - 1 ? 0.3 : 1 }}
            >
              Next
            </button>
            <span style={{ fontSize: '11px', color: '#555', marginLeft: '8px' }}>
              {filteredFiles.length} sounds
            </span>
          </div>
        )}

        {/* Sound list */}
        <div style={{ flex: 1, overflow: 'auto', padding: '8px', paddingBottom: '48px' }}>
          {pagedFiles.map(file => (
            <SfxRow
              key={file}
              file={file}
              entry={getEntry(file)}
              isPlaying={playing === file}
              isLastPlayed={lastPlayed === file}
              onPlay={playSound}
              onUpdate={updateEntry}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

const transportBtnStyle: React.CSSProperties = {
  width: '32px', height: '32px', borderRadius: '4px',
  background: '#333', border: 'none', color: '#ccc',
  cursor: 'pointer', fontSize: '14px',
};

const pageBtnStyle: React.CSSProperties = {
  padding: '4px 12px', fontSize: '11px', background: '#333',
  border: '1px solid #555', borderRadius: '4px', color: '#aaa', cursor: 'pointer',
};

const SfxRow = memo(function SfxRow({ file, entry, isPlaying, isLastPlayed, onPlay, onUpdate }: {
  file: string;
  entry: SfxEntry | undefined;
  isPlaying: boolean;
  isLastPlayed: boolean;
  onPlay: (file: string) => void;
  onUpdate: (file: string, updates: Partial<SfxEntry>) => void;
}) {
  const rowRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (isLastPlayed && rowRef.current) {
      rowRef.current.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }, [isLastPlayed]);

  return (
    <div
      ref={rowRef}
      style={{
        display: 'flex', alignItems: 'center', gap: '8px',
        padding: '6px 8px', marginBottom: '2px',
        background: isPlaying ? '#1a2a3a' : isLastPlayed ? '#1a1a2a' : entry?.label ? '#0a1a0a' : '#0a0a14',
        borderRadius: '4px', border: `1px solid ${isPlaying ? '#4a9eff' : isLastPlayed ? '#335' : entry?.starred ? '#aa8844' : '#1a1a2e'}`,
      }}
    >
      <button
        onClick={() => onPlay(file)}
        style={{
          width: '32px', height: '32px', borderRadius: '50%',
          background: isPlaying ? '#4a9eff' : '#333',
          border: 'none', color: '#fff', cursor: 'pointer',
          fontSize: '14px', flexShrink: 0,
        }}
      >
        {isPlaying ? '||' : '\u25B6'}
      </button>
      <span style={{ fontSize: '11px', color: '#666', width: '140px', flexShrink: 0, fontFamily: 'monospace' }}>
        {file}
      </span>
      <button
        onClick={() => onUpdate(file, { starred: !entry?.starred })}
        style={{
          background: 'none', border: 'none', cursor: 'pointer',
          color: entry?.starred ? '#ffaa44' : '#333', fontSize: '16px', flexShrink: 0,
        }}
      >
        {entry?.starred ? '\u2605' : '\u2606'}
      </button>
      <select
        value={entry?.label || ''}
        onChange={e => onUpdate(file, { label: e.target.value })}
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
      <input
        type="text"
        value={entry?.label || ''}
        onChange={e => onUpdate(file, { label: e.target.value })}
        placeholder="custom label"
        style={{
          width: '150px', padding: '4px 6px', background: '#111',
          border: '1px solid #333', borderRadius: '3px',
          color: '#fff', fontSize: '11px', fontFamily: 'monospace',
        }}
      />
      <input
        type="text"
        value={entry?.notes || ''}
        onChange={e => onUpdate(file, { notes: e.target.value })}
        placeholder="notes"
        style={{
          width: '120px', padding: '4px 6px', background: '#111',
          border: '1px solid #222', borderRadius: '3px',
          color: '#888', fontSize: '11px',
        }}
      />
    </div>
  );
});
