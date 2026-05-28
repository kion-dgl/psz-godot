import { useState } from 'react';
import { ShopFrame, Panel, PillRow, Divider, StatRow, ActionButton, C } from '../pszui';

type Quest = {
  name: string; area: string; reward: string; desc: string;
  tag?: { text: string; color: string }; muted?: boolean; lockedNote?: string;
};
const QUESTS: Quest[] = [
  { name: 'Search and Rescue', area: 'Paru Village', reward: '500 M', desc: 'Locate the missing scouts in the outskirts and bring them home safely.' },
  { name: 'Defend the Colony', area: 'Colony Gate', reward: '800 M', tag: { text: 'REPORT', color: '#e0a020' }, desc: 'You held the line — report back to the Guild Counter to claim your reward.' },
  { name: 'Static in the Snow', area: 'Rioh Snowfield', reward: '1,200 M', desc: 'Investigate the source of the electromagnetic interference in the snowfield.' },
  { name: 'Defeat the Scorpion King', area: 'Makara Desert', reward: '5,000 M', tag: { text: 'LOCKED', color: '#888' }, muted: true, desc: 'A massive creature has nested deep in the desert ruins.', lockedNote: '[LOCKED] Complete "The Paru Pact" to unlock.' },
  { name: 'Valley Patrol', area: 'Gurhacia Valley', reward: '500 M', tag: { text: 'CLEAR', color: '#338844' }, desc: 'Patrol the valley and eliminate hostile creatures. Already cleared.' },
];

export default function QuestCounter() {
  const [sel, setSel] = useState(0);
  const q = QUESTS[sel];

  return (
    <ShopFrame>
      <Panel title="Guild Counter" width={420} hint="Up/Down: Select   Enter: Accept   Esc: Leave">
        {QUESTS.map((quest, i) => (
          <PillRow
            key={quest.name}
            label={quest.name}
            tag={quest.tag}
            muted={quest.muted}
            selected={sel === i}
            onClick={() => setSel(i)}
          />
        ))}
        <Divider />
        <div style={{ fontSize: 11, color: C.textLight, padding: '2px 4px', lineHeight: 1.5 }}>
          Difficulty (Normal / Hard / Super-Hard) is chosen in a sub-menu after selecting a quest.
        </div>
      </Panel>
      <Panel title="Quest Info" width={280}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 8 }}>{q.name}</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <StatRow label="Area" value={q.area} />
            <StatRow label="Type" value="Quest" />
            <StatRow label="Reward" value={q.reward} />
          </div>
          <Divider />
          <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>{q.desc}</div>
          {q.lockedNote && (
            <div style={{ fontSize: 12, color: '#888', lineHeight: 1.5, marginTop: 8, fontWeight: 600 }}>{q.lockedNote}</div>
          )}
          <ActionButton label="Accept Quest" />
        </div>
      </Panel>
    </ShopFrame>
  );
}
