import { useState } from 'react';

const W = 960, H = 540;

const C = {
  bg: '#a8cce8',
  titleTop: '#2a3448',
  titleBot: '#1e2838',
  cream: '#e0e4ef',
  orange: '#f0a020',
  goldTitle: '#f8c840',
  dark: '#1a1a2a',
  darkMuted: '#3a4a5a',
  white: '#ffffff',
  greenArrow: '#338844',
  panelBorder: 'rgba(122,160,192,0.5)',
};

const SCANLINES = `repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(120,160,200,0.08) 2px,rgba(120,160,200,0.08) 4px)`;

type Step = 'appearance' | 'name' | 'confirm';

const ROWS_HUMAN = ['Head Type', 'Hair Color', 'Costume Color', 'Skin Tone'];
const ROWS_CAST = ['Head Parts', 'Body Color A', 'Body Color B', 'Body Color C'];
const MAXES = [8, 12, 12, 6];

const HAIR_COLORS = ['Brown', 'Black', 'Blonde', 'Red', 'Blue', 'Green', 'Silver', 'Purple', 'Pink', 'Teal', 'Orange', 'White'];
const BODY_COLORS = ['Red', 'Blue', 'Green', 'Yellow', 'Purple', 'White', 'Black', 'Pink', 'Teal', 'Orange', 'Silver', 'Gold'];
const SKIN_TONES = ['Light', 'Fair', 'Medium', 'Tan', 'Brown', 'Dark'];

export default function CharacterCustomize() {
  const [step, setStep] = useState<Step>('appearance');
  const [row, setRow] = useState(0);
  const [vals, setVals] = useState([0, 0, 0, 0]);
  const [name, setName] = useState('');
  const isCast = false;
  const rows = isCast ? ROWS_CAST : ROWS_HUMAN;
  const className = 'HUmar';
  const classInfo = 'Human · Male · Hunter';

  const cycle = (r: number, dir: number) => {
    setVals(prev => {
      const next = [...prev];
      next[r] = ((next[r] + dir) % MAXES[r] + MAXES[r]) % MAXES[r];
      return next;
    });
  };

  return (
    <div style={{
      width: W, height: H, position: 'relative', overflow: 'hidden',
      background: C.bg, backgroundImage: SCANLINES,
      fontFamily: "'Segoe UI', 'Helvetica Neue', Arial, sans-serif",
    }}>
      {/* Accent bar */}
      <div style={{ height: 12, background: `linear-gradient(180deg, ${C.goldTitle} 0%, ${C.orange} 55%, #c88010 100%)` }} />

      {/* Title bar */}
      <div style={{
        height: 48, background: C.titleTop, display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', padding: '0 20px',
        borderBottom: '1px solid rgba(200,160,40,0.55)',
      }}>
        <span style={{ fontSize: 20, fontWeight: 800, fontStyle: 'italic', color: C.goldTitle, letterSpacing: 1, textShadow: '1px 1px 0 rgba(0,0,0,0.55)' }}>
          {step === 'appearance' ? 'CUSTOMIZE APPEARANCE' : step === 'name' ? 'ENTER NAME' : 'CONFIRM CHARACTER'}
        </span>
        {/* Step tabs for spec navigation */}
        <div style={{ display: 'flex', gap: 4 }}>
          {(['appearance', 'name', 'confirm'] as Step[]).map(s => (
            <button key={s} onClick={() => setStep(s)} style={{
              background: step === s ? C.orange : 'rgba(255,255,255,0.1)',
              color: step === s ? C.dark : 'rgba(255,255,255,0.6)',
              border: 'none', borderRadius: 3, padding: '3px 10px',
              fontSize: 11, fontWeight: 600, cursor: 'pointer', textTransform: 'capitalize',
            }}>{s}</button>
          ))}
        </div>
      </div>

      {/* Content */}
      <div style={{ position: 'absolute', top: 60, left: 0, right: 0, bottom: 32 }}>
        {step === 'appearance' && (
          <div style={{ display: 'flex', height: '100%' }}>
            {/* Left panel */}
            <div style={{ width: 300, margin: 16, background: 'rgba(210,220,235,0.92)', border: `1px solid ${C.panelBorder}`, borderRadius: 8, overflow: 'hidden' }}>
              <div style={{ height: 36, background: C.titleBot, display: 'flex', alignItems: 'center', padding: '0 14px' }}>
                <span style={{ fontSize: 14, fontWeight: 700, color: C.white }}>APPEARANCE</span>
              </div>
              {rows.map((label, i) => {
                const sel = i === row;
                return (
                  <div key={i} onClick={() => setRow(i)} style={{
                    margin: '4px 4px 0', padding: '6px 14px', borderRadius: 4, cursor: 'pointer',
                    background: sel ? C.orange : C.cream,
                  }}>
                    <div style={{ fontSize: 14, fontWeight: 600, color: sel ? C.white : C.dark }}>{label}</div>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 8, marginTop: 2 }}>
                      <span onClick={(e) => { e.stopPropagation(); cycle(i, -1); }} style={{ fontSize: 16, color: sel ? C.white : C.greenArrow, cursor: 'pointer', fontWeight: 700 }}>◀</span>
                      <span style={{ fontSize: 14, fontWeight: 600, color: sel ? C.white : C.dark, minWidth: 40, textAlign: 'center' }}>{vals[i] + 1}/{MAXES[i]}</span>
                      <span onClick={(e) => { e.stopPropagation(); cycle(i, 1); }} style={{ fontSize: 16, color: sel ? C.white : C.greenArrow, cursor: 'pointer', fontWeight: 700 }}>▶</span>
                    </div>
                  </div>
                );
              })}
              <div style={{ padding: '12px 14px', textAlign: 'center', fontSize: 16, fontWeight: 700, color: '#ff0030' }}>{className}</div>
            </div>

            {/* 3D preview placeholder */}
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', margin: 16 }}>
              <div style={{
                width: '100%', height: '100%', borderRadius: 8,
                background: 'linear-gradient(180deg, #b8d8f0 0%, #90b8d8 100%)',
                border: `1px solid ${C.panelBorder}`,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                flexDirection: 'column', gap: 8,
              }}>
                <div style={{ fontSize: 48, opacity: 0.3 }}>🧑</div>
                <div style={{ fontSize: 13, color: C.darkMuted, fontStyle: 'italic' }}>3D model preview</div>
                <div style={{ fontSize: 11, color: C.darkMuted }}>Right stick rotates · Uses SubViewport in Godot</div>
              </div>
            </div>
          </div>
        )}

        {step === 'name' && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}>
            <div style={{
              width: 420, background: 'rgba(210,220,235,0.95)', border: `1px solid ${C.panelBorder}`,
              borderRadius: 8, overflow: 'hidden',
            }}>
              <div style={{ height: 40, background: C.titleBot, display: 'flex', alignItems: 'center', padding: '0 16px' }}>
                <span style={{ fontSize: 16, fontWeight: 700, color: C.white }}>CHARACTER NAME</span>
              </div>
              <div style={{ padding: 20, textAlign: 'center' }}>
                <div style={{ fontSize: 14, color: C.darkMuted, marginBottom: 16 }}>{className}  ({classInfo})</div>
                <input
                  type="text"
                  maxLength={16}
                  value={name}
                  onChange={e => setName(e.target.value)}
                  placeholder="Enter name..."
                  style={{
                    width: '80%', padding: '10px 16px', fontSize: 18, textAlign: 'center',
                    border: `1px solid ${C.panelBorder}`, borderRadius: 4,
                    outline: 'none', fontFamily: 'inherit',
                  }}
                />
                <div style={{ fontSize: 12, color: C.darkMuted, marginTop: 8 }}>Max 16 characters</div>
              </div>
            </div>
          </div>
        )}

        {step === 'confirm' && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}>
            <div style={{
              width: 500, background: 'rgba(210,220,235,0.95)', border: `1px solid ${C.panelBorder}`,
              borderRadius: 8, overflow: 'hidden',
            }}>
              <div style={{ height: 40, background: C.titleBot, display: 'flex', alignItems: 'center', padding: '0 16px' }}>
                <span style={{ fontSize: 16, fontWeight: 700, color: C.white }}>CREATE THIS CHARACTER?</span>
              </div>
              <div style={{ display: 'flex', padding: 20, gap: 24 }}>
                {/* Art placeholder */}
                <div style={{ width: 160, height: 160, background: 'rgba(180,200,220,0.5)', borderRadius: 6, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <span style={{ fontSize: 64, opacity: 0.3 }}>🧑</span>
                </div>
                <div style={{ flex: 1, fontSize: 14 }}>
                  <div style={{ fontSize: 24, fontWeight: 700, color: C.dark, marginBottom: 8 }}>{name || 'Sara'}</div>
                  <div style={{ height: 1, background: C.panelBorder, marginBottom: 8 }} />
                  <Row label="Class:" value={className} color="#ff0030" />
                  <Row label="Type:" value="Hunter" />
                  <Row label="Race:" value="Human" />
                  <Row label="Gender:" value="Male" />
                  <div style={{ height: 8 }} />
                  <div style={{ fontSize: 13, color: C.darkMuted, marginBottom: 4 }}>Appearance</div>
                  <Row label="Head:" value={String(vals[0] + 1)} />
                  <Row label="Hair:" value={HAIR_COLORS[vals[1]]} />
                  <Row label="Costume:" value={BODY_COLORS[vals[2]]} />
                  <Row label="Skin:" value={SKIN_TONES[vals[3]]} />
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Hint bar */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, height: 32,
        background: 'rgba(255,255,255,0.65)', borderTop: `2px solid ${C.orange}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 13, color: C.darkMuted,
      }}>
        {step === 'appearance' && '↑↓ Row    ←→ Change    R-Stick Rotate    A · Confirm    B · Back'}
        {step === 'name' && 'Type a name, then press Enter    B · Back'}
        {step === 'confirm' && 'A · Create Character    B · Back to Name'}
      </div>
    </div>
  );
}

function Row({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div style={{ display: 'flex', gap: 8, marginBottom: 2 }}>
      <span style={{ fontSize: 14, color: '#3a4a5a', width: 80 }}>{label}</span>
      <span style={{ fontSize: 14, color: color || '#1a1a2a' }}>{value}</span>
    </div>
  );
}
