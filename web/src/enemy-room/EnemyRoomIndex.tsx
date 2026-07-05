import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { loadConfig, loadRoster, type EnemyAttackConfig, type RosterEntry } from './types';
import { ARCHETYPES } from './archetypes';

/**
 * Enemy rooms index — one room per behavior archetype (spec
 * /mechanics/enemy-attacks "Rig groups & behavior archetypes"). Each room
 * previews and captures that archetype's behavior for its enemies.
 */
export default function EnemyRoomIndex() {
  const [config, setConfig] = useState<EnemyAttackConfig | null>(null);
  const [roster, setRoster] = useState<Map<string, RosterEntry>>(new Map());
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadConfig().then(setConfig, (e) => setError(String(e)));
    loadRoster().then(setRoster, (e) => setError(String(e)));
  }, []);

  const membersOf = (archetypeId: string): string[] =>
    config
      ? Object.keys(config.enemies)
          .filter((id) => (config.enemies[id].archetype ?? 'unclassified') === archetypeId)
          .sort()
      : [];

  return (
    <div style={{ minHeight: 'calc(100vh - 60px)', background: '#0a0a1a', color: '#fff', padding: 20 }}>
      <h2 style={{ margin: '0 0 4px' }}>Enemy Rooms</h2>
      <p style={{ color: '#9ab', fontSize: 13, maxWidth: 720 }}>
        One room per behavior archetype — the taxonomy from spec <code>/mechanics/enemy-attacks</code>, stamped
        onto every enemy in <code>data/enemy_attacks.json</code>. Pick a room to preview and tune that
        archetype's enemies against the sim.
      </p>
      {error && <div style={{ color: '#f66' }}>{error}</div>}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: 12, marginTop: 12 }}>
        {ARCHETYPES.map((a) => {
          const members = membersOf(a.id);
          const names = members.map((id) => roster.get(id)?.name || id);
          const card = (
            <div
              key={a.id}
              style={{
                border: '1px solid #334',
                borderRadius: 8,
                padding: 12,
                background: a.outOfScope ? '#101020' : '#12122a',
                opacity: a.outOfScope ? 0.55 : 1,
                height: '100%',
              }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <strong>{a.label}</strong>
                <span style={{ color: '#889', fontSize: 11 }}>{members.length} enem{members.length === 1 ? 'y' : 'ies'}</span>
              </div>
              <div style={{ color: '#9ab', fontSize: 11, margin: '6px 0' }}>{a.blurb}</div>
              <div style={{ color: '#786', fontSize: 10, fontStyle: 'italic', marginBottom: 6 }}>{a.simNote}</div>
              <div style={{ color: '#667', fontSize: 10 }}>{names.join(' · ') || '—'}</div>
            </div>
          );
          return a.outOfScope ? (
            card
          ) : (
            <Link key={a.id} to={`/enemy-room/${a.id}`} style={{ textDecoration: 'none', color: 'inherit' }}>
              {card}
            </Link>
          );
        })}
      </div>
    </div>
  );
}
