import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { loadBossConfig, loadRoster, type BossArenaConfig, type RosterEntry } from './types';

/**
 * Boss rooms index (#493) — one room per boss, loaded inside its own arena.
 * Behavior notes are pending; the rooms are the observation instrument.
 */
export default function BossRoomIndex() {
  const [config, setConfig] = useState<BossArenaConfig | null>(null);
  const [roster, setRoster] = useState<Map<string, RosterEntry>>(new Map());
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadBossConfig().then(setConfig, (e) => setError(String(e)));
    loadRoster().then(setRoster, (e) => setError(String(e)));
  }, []);

  return (
    // The app shell clips routes with overflow:hidden (canvas tools fill the
    // viewport), so a document-style page must scroll itself.
    <div style={{ height: '100%', overflowY: 'auto', background: '#0a0a1a', color: '#fff', padding: 20 }}>
      <h2 style={{ margin: '0 0 4px' }}>Boss Rooms</h2>
      <p style={{ color: '#9ab', fontSize: 13, maxWidth: 720 }}>
        One room per boss, loaded <em>inside its own arena</em> — boss behavior is arena-bound (fly passes,
        surfacing spots, fixed emplacements), so unlike the flat <Link to="/enemy-room" style={{ color: '#88aaff' }}>enemy rooms</Link> these
        map behavior against the real stage geometry. Mapping from <code>data/boss_arenas.json</code>.
      </p>
      {error && <div style={{ color: '#f66' }}>{error}</div>}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 12, marginTop: 12 }}>
        {config &&
          Object.entries(config.bosses).map(([id, b]) => {
            const arena = config.arenas[b.arena];
            return (
              <Link key={id} to={`/boss-room/${id}`} style={{ textDecoration: 'none', color: 'inherit' }}>
                <div style={{ border: '1px solid #334', borderRadius: 8, padding: 12, background: '#12122a', height: '100%' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                    <strong>{roster.get(id)?.name ?? id}</strong>
                    <span style={{ color: '#889', fontSize: 11 }}>{b.model_id}</span>
                  </div>
                  <div style={{ color: '#9ab', fontSize: 11, margin: '6px 0' }}>
                    {arena?.label ?? b.arena} ({b.arena}) · from {b.quest_source}
                  </div>
                  {b.note && <div style={{ color: '#a86', fontSize: 10, fontStyle: 'italic' }}>{b.note}</div>}
                </div>
              </Link>
            );
          })}
      </div>
      {config && (
        <p style={{ color: '#667', fontSize: 11, marginTop: 16 }}>
          Unassigned arenas (no boss spawns there in current quest data):{' '}
          {Object.entries(config.arenas)
            .filter(([, a]) => a.unassigned)
            .map(([id, a]) => `${id} (${a.label})`)
            .join(' · ')}
          . Load them from any room's arena picker.
        </p>
      )}
    </div>
  );
}
