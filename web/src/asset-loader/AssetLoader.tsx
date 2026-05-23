import { useEffect, useMemo, useRef, useState } from 'react';

type Phase = 'connecting' | 'loading' | 'done';
type Speed = 'slow' | 'normal' | 'fast';

const CANVAS_W = 1280;
const CANVAS_H = 720;
const LOADER_W = 640;

const FILE_MANIFEST = [
  'fetching: /assets/sound/music/p0_title.ogg…',
  'fetching: /assets/models/players/humar.pck…',
  'fetching: /assets/models/players/racast.pck…',
  'fetching: /assets/models/players/fonewearl.pck…',
  'fetching: /assets/stages/darbelie_orbit.pck…',
  'fetching: /assets/stages/dark_castle.pck…',
  'fetching: /assets/sfx/psobb_pack.zip…',
  'fetching: /assets/shaders/photon_blast.shader…',
  'fetching: /assets/textures/ui_atlas_hd.png…',
  'mounting assets into virtual directory…',
];

const TOTAL_MB = 264;

// Opacity-only keyframe so it can't override inline transforms (translateX(-50%))
// after the animation's `both` fill mode latches the final state.
const STYLES = `
  @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&family=Share+Tech+Mono&family=Outfit:wght@300;400;600&family=Noto+Sans+JP:wght@400;500;700&display=swap');

  @keyframes psz-twinkle {
    0%, 100% { opacity: 0.2; transform: scale(0.7); }
    50%      { opacity: 1; transform: scale(1.4); }
  }
  @keyframes psz-spin {
    from { transform: rotate(0deg); }
    to   { transform: rotate(360deg); }
  }
  @keyframes psz-cloud-pulse {
    0%, 100% { opacity: 1; }
    50%      { opacity: 0.55; }
  }
  @keyframes psz-fade-in {
    from { opacity: 0; }
    to   { opacity: 1; }
  }
  @keyframes psz-dot-pulse {
    0%, 100% { opacity: 0.4; }
    50%      { opacity: 1; }
  }
  .psz-sparkle {
    position: absolute;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255,255,255,1) 0%, rgba(255,250,200,0.7) 40%, rgba(255,255,255,0) 75%);
    pointer-events: none;
    animation-name: psz-twinkle;
    animation-iteration-count: infinite;
    animation-timing-function: ease-in-out;
  }
  .psz-fade-in { animation: psz-fade-in 0.6s ease-out both; }
`;

type Sparkle = { top: string; left: string; size: number; delay: number; dur: number };

function makeSparkles(count: number): Sparkle[] {
  const out: Sparkle[] = [];
  for (let i = 0; i < count; i++) {
    out.push({
      top: `${Math.random() * 100}%`,
      left: `${Math.random() * 100}%`,
      size: 3 + Math.random() * 6,
      delay: Math.random() * 3,
      dur: 2.2 + Math.random() * 1.8,
    });
  }
  return out;
}

function CloudDownIcon({ size = 32 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="currentColor" aria-hidden>
      <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z" />
    </svg>
  );
}

function SpinnerWidget({ showIcon }: { showIcon: boolean }) {
  return (
    <div style={{ position: 'relative', width: 160, height: 160 }}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          border: '3px solid rgba(255, 255, 255, 0.4)',
          borderRadius: '50%',
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 0,
          border: '3px solid transparent',
          borderTopColor: 'rgba(253, 224, 71, 0.95)',
          borderBottomColor: 'rgba(253, 224, 71, 0.95)',
          borderRadius: '50%',
          boxShadow: '0 0 26px rgba(253, 224, 71, 0.7)',
          animation: 'psz-spin 1.2s linear infinite',
        }}
      />
      {showIcon && (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: '#fef08a',
            filter: 'drop-shadow(0 0 8px rgba(253, 224, 71, 0.85))',
            animation: 'psz-cloud-pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
          }}
        >
          <CloudDownIcon size={56} />
        </div>
      )}
    </div>
  );
}

export default function AssetLoader() {
  const [phase, setPhase] = useState<Phase>('connecting');
  const [progress, setProgress] = useState(0);
  const [speed, setSpeed] = useState<Speed>('normal');
  const [sparkleSeed, setSparkleSeed] = useState(0);

  const speedRef = useRef(speed);
  speedRef.current = speed;

  const sparkles = useMemo(() => makeSparkles(32), [sparkleSeed]);

  // Brief handshake beat before the download actually starts. Sells the
  // "connecting → connected" state change that justifies the cloud icon
  // appearing.
  useEffect(() => {
    if (phase !== 'connecting') return;
    const t = window.setTimeout(() => setPhase('loading'), 1200);
    return () => window.clearTimeout(t);
  }, [phase]);

  useEffect(() => {
    if (phase !== 'loading') return;
    let cancelled = false;
    let tickTimer = 0;
    let doneTimer = 0;
    // Guard prevents React's batched updater (and strict-mode double-invoke)
    // from scheduling the "done" transition more than once per loading run.
    let doneScheduled = false;
    const tick = () => {
      if (cancelled) return;
      const s = speedRef.current;
      const inc = s === 'slow' ? 0.5 : s === 'fast' ? 3.5 : 1.4;
      const delay = s === 'slow' ? 80 : s === 'fast' ? 25 : 50;
      setProgress((p) => {
        const next = Math.min(100, p + inc * (Math.random() * 1.5 + 0.5));
        if (next >= 100 && !doneScheduled) {
          doneScheduled = true;
          doneTimer = window.setTimeout(() => setPhase('done'), 700);
        }
        return next;
      });
      tickTimer = window.setTimeout(tick, delay);
    };
    tick();
    return () => {
      cancelled = true;
      window.clearTimeout(tickTimer);
      window.clearTimeout(doneTimer);
    };
  }, [phase]);

  const restart = () => {
    setProgress(0);
    setSparkleSeed((s) => s + 1);
    setPhase('connecting');
  };

  const downloadedMb = ((progress / 100) * TOTAL_MB).toFixed(1);
  const speedMbs = speed === 'slow' ? 1.2 : speed === 'fast' ? 24.0 : 6.8;
  const fileIdx = Math.min(
    Math.floor((progress / 100) * FILE_MANIFEST.length),
    FILE_MANIFEST.length - 1,
  );

  return (
    <>
      <style>{STYLES}</style>
      <div
        style={{
          width: '100%',
          height: '100%',
          background: '#0a0a1a',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'flex-start',
          padding: 16,
          gap: 12,
          overflow: 'auto',
          boxSizing: 'border-box',
        }}
      >
        {/* Fixed 1280×720 preview frame */}
        <div
          style={{
            width: CANVAS_W,
            height: CANVAS_H,
            flexShrink: 0,
            position: 'relative',
            overflow: 'hidden',
            background: 'linear-gradient(to bottom, #7dd3fc 0%, #38bdf8 45%, #2563eb 100%)',
            fontFamily: '"Outfit", system-ui, sans-serif',
            color: '#0c1e3d',
            boxShadow: '0 0 0 1px #2a2a4a, 0 8px 32px rgba(0,0,0,0.5)',
          }}
        >
          {/* Sparkle particles */}
          <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', zIndex: 1 }}>
            {sparkles.map((s, i) => (
              <span
                key={i}
                className="psz-sparkle"
                style={{
                  top: s.top,
                  left: s.left,
                  width: s.size,
                  height: s.size,
                  animationDelay: `${s.delay}s`,
                  animationDuration: `${s.dur}s`,
                }}
              />
            ))}
          </div>

          {/* Banner — cream→sky vertical gradient body + gold gradient accent stripe */}
          <div
            className="psz-fade-in"
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              right: 0,
              zIndex: 6,
              padding: '24px 32px 18px',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'flex-start',
              background:
                'linear-gradient(to bottom, rgba(254, 249, 195, 0.55) 0%, rgba(186, 230, 253, 0.30) 70%, rgba(186, 230, 253, 0) 100%)',
              boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.45)',
            }}
          >
            <div>
              <div
                style={{
                  fontFamily: '"Orbitron", "Outfit", sans-serif',
                  fontSize: 10,
                  letterSpacing: '0.3em',
                  color: '#1e3a8a',
                  textTransform: 'uppercase',
                  marginBottom: 4,
                }}
              >
                PATCH SERVER LINK
              </div>
              <div
                style={{
                  fontFamily: '"Orbitron", "Outfit", sans-serif',
                  fontSize: 16,
                  letterSpacing: '0.18em',
                  color: '#172554',
                  textTransform: 'uppercase',
                  textShadow: '0 1px 2px rgba(255,255,255,0.5)',
                }}
              >
                Live Patch Update
              </div>
              <div
                style={{
                  fontFamily: '"Noto Sans JP", "Outfit", sans-serif',
                  fontSize: 11,
                  letterSpacing: '0.08em',
                  color: 'rgba(30, 58, 138, 0.7)',
                  marginTop: 3,
                }}
              >
                ライブ・パッチ・アップデート
              </div>
            </div>
            <div
              style={{
                textAlign: 'right',
                fontFamily: '"Share Tech Mono", monospace',
                fontSize: 12,
                color: 'rgba(30, 58, 138, 0.75)',
              }}
            >
              <div>
                CLIENT:{' '}
                <span style={{ color: '#a16207', fontWeight: 700 }}>v1.12.0_patch</span>
              </div>
              <div
                style={{
                  fontFamily: '"Noto Sans JP", "Outfit", sans-serif',
                  fontSize: 10,
                  letterSpacing: '0.08em',
                  color: 'rgba(30, 58, 138, 0.6)',
                  marginTop: 3,
                }}
              >
                クライアント
              </div>
            </div>

            {/* Gold gradient accent stripe (replaces the flat border-bottom) */}
            <div
              style={{
                position: 'absolute',
                left: 0,
                right: 0,
                bottom: 0,
                height: 2,
                background:
                  'linear-gradient(to right, rgba(253, 224, 71, 0) 0%, rgba(253, 224, 71, 0.5) 12%, #facc15 40%, #fde047 50%, #facc15 60%, rgba(253, 224, 71, 0.5) 88%, rgba(253, 224, 71, 0) 100%)',
                boxShadow: '0 0 12px rgba(253, 224, 71, 0.45)',
              }}
            />
          </div>

          {/* Spinner — dead center of the 1280×720 frame */}
          <div
            style={{
              position: 'absolute',
              top: '50%',
              left: '50%',
              transform: 'translate(-50%, -50%)',
              zIndex: 7,
            }}
          >
            <SpinnerWidget showIcon={phase !== 'connecting'} />
          </div>

          {/* Loader content — status text, progress bar, telemetry. Fixed width
              to dodge any percent-based overflow. */}
          <div
            className="psz-fade-in"
            style={{
              position: 'absolute',
              left: '50%',
              bottom: 64,
              marginLeft: -LOADER_W / 2,
              width: LOADER_W,
              zIndex: 7,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 16,
            }}
          >
            <div style={{ textAlign: 'center', width: '100%' }}>
              <div
                style={{
                  fontFamily: '"Orbitron", "Outfit", sans-serif',
                  fontSize: 13,
                  letterSpacing: '0.18em',
                  color: '#ffffff',
                  textShadow: '0 1px 3px rgba(30, 58, 138, 0.6)',
                  textTransform: 'uppercase',
                }}
              >
                {phase === 'connecting'
                  ? 'Establishing Connection'
                  : phase === 'done'
                    ? 'Ready'
                    : 'Downloading Remote Assets'}
              </div>
              <div
                style={{
                  fontFamily: '"Noto Sans JP", "Outfit", sans-serif',
                  fontSize: 10,
                  color: 'rgba(12, 30, 61, 0.65)',
                  marginTop: 2,
                  letterSpacing: '0.05em',
                }}
              >
                {phase === 'connecting'
                  ? '接続を確立中'
                  : phase === 'done'
                    ? '準備完了'
                    : 'アセットをダウンロード中'}
              </div>
              <div
                style={{
                  fontFamily: '"Share Tech Mono", monospace',
                  fontSize: 11,
                  color: 'rgba(12, 30, 61, 0.7)',
                  marginTop: 6,
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                  maxWidth: '100%',
                }}
              >
                {phase === 'connecting'
                  ? 'negotiating with gateway…'
                  : phase === 'done'
                    ? '— assets mounted —'
                    : FILE_MANIFEST[fileIdx]}
              </div>
            </div>

            <div
              style={{
                width: '100%',
                height: 18,
                background: 'rgba(12, 30, 61, 0.35)',
                borderRadius: 9,
                border: '1px solid rgba(253, 224, 71, 0.6)',
                padding: 2,
                overflow: 'hidden',
                position: 'relative',
              }}
            >
              <div
                style={{
                  width: `${progress}%`,
                  height: '100%',
                  background: 'linear-gradient(to right, #fde047, #facc15, #f59e0b)',
                  borderRadius: 7,
                  boxShadow: '0 0 18px rgba(253, 224, 71, 0.7)',
                  transition: 'width 80ms linear',
                }}
              />
            </div>

            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(3, 1fr)',
                gap: 12,
                width: '100%',
                fontFamily: '"Share Tech Mono", monospace',
                fontSize: 11,
                textAlign: 'center',
                color: 'rgba(12, 30, 61, 0.8)',
                paddingTop: 8,
                borderTop: '1px solid rgba(12, 30, 61, 0.2)',
              }}
            >
              <Telemetry label="Data" value={`${downloadedMb} / ${TOTAL_MB} MB`} />
              <Telemetry label="Speed" value={`${speedMbs.toFixed(1)} MB/s`} accent />
              <Telemetry label="Progress" value={`${Math.floor(progress)}%`} accent />
            </div>
          </div>

          {/* Footer — gateway / connection status */}
          <div
            className="psz-fade-in"
            style={{
              position: 'absolute',
              bottom: 0,
              left: 0,
              right: 0,
              zIndex: 6,
              padding: '8px 32px',
              borderTop: '1px solid rgba(30, 58, 138, 0.2)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              fontFamily: '"Share Tech Mono", monospace',
              fontSize: 10,
              color: 'rgba(30, 58, 138, 0.6)',
            }}
          >
            <span>GATEWAY: [arweave / r2 mirror]</span>
            <span
              style={{
                color: '#a16207',
                fontWeight: 700,
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                animation: 'psz-dot-pulse 1.8s infinite ease-in-out',
              }}
            >
              <span
                style={{
                  width: 6,
                  height: 6,
                  borderRadius: '50%',
                  background: '#a16207',
                  boxShadow: '0 0 6px rgba(161, 98, 7, 0.8)',
                }}
              />
              {phase === 'connecting'
                ? 'CONNECTING…'
                : phase === 'done'
                  ? 'READY'
                  : 'CONNECTED'}
            </span>
          </div>
        </div>

        {/* Dev controls strip */}
        <div
          style={{
            width: CANVAS_W,
            display: 'flex',
            alignItems: 'center',
            gap: 16,
            flexWrap: 'wrap',
            padding: '8px 14px',
            background: '#12122a',
            border: '1px solid #2a2a4a',
            borderRadius: 4,
            flexShrink: 0,
            fontSize: 11,
            color: '#e0e0e0',
            fontFamily: '"Outfit", system-ui, sans-serif',
          }}
        >
          <span style={{ color: '#666' }}>
            {CANVAS_W} × {CANVAS_H}
          </span>
          <span>
            Phase: <code style={{ color: '#fde047' }}>{phase}</code>
          </span>
          <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ color: '#9ca3af' }}>Net</span>
            <select
              value={speed}
              onChange={(e) => setSpeed(e.target.value as Speed)}
              style={{
                background: '#0c1e3d',
                color: '#fde047',
                border: '1px solid #1e3a8a',
                borderRadius: 4,
                padding: '2px 4px',
                fontSize: 11,
              }}
            >
              <option value="slow">3G (1.2 MB/s)</option>
              <option value="normal">Wi-Fi (6.8 MB/s)</option>
              <option value="fast">Fiber (24 MB/s)</option>
            </select>
          </label>
          <button
            onClick={restart}
            style={{
              background: '#1e3a8a',
              color: '#fde047',
              border: '1px solid #fde047',
              borderRadius: 4,
              padding: '4px 10px',
              fontSize: 11,
              cursor: 'pointer',
            }}
          >
            Restart loop
          </button>
          <span style={{ color: '#666', marginLeft: 'auto' }}>
            BGM placeholder — Phantasy Star reference track TBD
          </span>
        </div>
      </div>
    </>
  );
}

function Telemetry({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent?: boolean;
}) {
  return (
    <div>
      <div
        style={{
          fontSize: 9,
          textTransform: 'uppercase',
          letterSpacing: '0.15em',
          opacity: 0.65,
          marginBottom: 2,
        }}
      >
        {label}
      </div>
      <div style={{ color: accent ? '#a16207' : '#0c1e3d', fontWeight: accent ? 600 : 400 }}>
        {value}
      </div>
    </div>
  );
}
