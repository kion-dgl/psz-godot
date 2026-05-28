import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, C } from '../pszui';

const QUESTS = [
  { name: 'Valley Patrol', area: 'Gurhacia Valley', diff: 'Normal', rank: 'C', reward: 500, desc: 'Patrol the valley and eliminate hostile creatures.' },
  { name: 'Swamp Sweep', area: 'Ozette Wetlands', diff: 'Normal', rank: 'C', reward: 600, desc: 'Clear out the creatures infesting the wetlands.' },
  { name: 'Forest Recon', area: 'Rioh Snowfield', diff: 'Hard', rank: 'B', reward: 1200, desc: 'Investigate unusual activity in the snowfield.' },
  { name: 'Desert Storm', area: 'Makara Desert', diff: 'Hard', rank: 'B', reward: 1500, desc: 'A sandstorm has stirred up the desert creatures.' },
  { name: 'Tower Ascent', area: 'Eternal Tower', diff: 'S. Hard', rank: 'A', reward: 5000, desc: 'Climb the tower and reach the summit.' },
];
const DIFFS = ['Normal', 'Hard', 'S. Hard'];

export default function QuestCounter() {
  const [mode, setMode] = useState(0);
  const [sel, setSel] = useState(0);
  const filtered = QUESTS.filter(q => q.diff === DIFFS[mode]);
  const q = filtered[sel];
  return (
    <ShopFrame>
      <Panel title="Quest Counter" width={420} hint="Select a quest to accept.">
        <TabBar tabs={DIFFS} active={mode} onSelect={(i) => { setMode(i); setSel(0); }} />
        {filtered.map((q, i) => (
          <PillRow key={q.name} label={q.name} rightText={`[${q.rank}]`} selected={sel === i} onClick={() => setSel(i)} />
        ))}
      </Panel>
      <Panel title="Quest Info" width={280}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 2 }}>{q?.name}</div>
          <div style={{ fontSize: 11, color: C.textLight, marginBottom: 8 }}>{q?.area}</div>
          <Divider />
          <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5, marginBottom: 8 }}>{q?.desc}</div>
          <Divider />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13 }}>
            {[['Difficulty', q?.diff], ['Rank', q?.rank], ['Reward', `${(q?.reward || 0).toLocaleString()} MST`]].map(([k, v]) => (
              <div key={k} style={{ display: 'flex', justifyContent: 'space-between' }}><span style={{ color: C.textLight }}>{k}</span><span style={{ fontWeight: 700, color: C.text }}>{v}</span></div>
            ))}
          </div>
          <div style={{ marginTop: 10, padding: 7, fontSize: 13, fontWeight: 600, background: C.selectedGradient, border: '2px solid #d08010', borderRadius: 4, color: C.text, cursor: 'pointer', textAlign: 'center' }}>Accept Quest</div>
        </div>
      </Panel>
    </ShopFrame>
  );
}
