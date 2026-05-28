import { useState, useEffect, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { assetUrl } from '../../utils/assets';

const W = 960, H = 540;

const C = {
  bgLight: '#a8cce8',
  bgDark: '#2a3448',
  bgDarker: '#1e2838',
  itemBg: 'rgba(255,255,255,0.85)',
  selectedGradient: 'linear-gradient(90deg, #f0a020 0%, #f8c840 100%)',
  text: '#1a1a2a',
  textLight: '#3a4a5a',
  textWhite: '#ffffff',
  textOnSelected: '#1a1a2a',
  hintBg: 'rgba(255,255,255,0.7)',
  hintBorder: '#8aa8c8',
  separator: '#7aa0c0',
};

const SCANLINES = `repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(120,160,200,0.08) 2px,rgba(120,160,200,0.08) 4px)`;

const CLASS_TO_PREFIX: Record<string, string> = {
  humar: 'pc_00', humarl: 'pc_01', ramar: 'pc_02', ramarl: 'pc_03',
  fomar: 'pc_04', fomarl: 'pc_05', hunewm: 'pc_06', hunewearl: 'pc_07',
  hucast: 'pc_08', hucaseal: 'pc_09', racast: 'pc_10', racaseal: 'pc_11',
  fonewm: 'pc_12', fonewearl: 'pc_13',
};

type Slot =
  | { kind: 'filled'; name: string; klass: string; level: number; playtimeMin: number }
  | { kind: 'empty' };

const SLOTS: Slot[] = [
  { kind: 'filled', name: 'Sara',    klass: 'HUmar',     level: 42, playtimeMin: 38 * 60 + 12 },
  { kind: 'filled', name: 'Reika',   klass: 'FOnewearl', level: 28, playtimeMin: 12 * 60 + 47 },
  { kind: 'filled', name: 'Kiln',    klass: 'RAcast',    level: 17, playtimeMin: 4 * 60 + 5 },
  { kind: 'filled', name: 'Mira',    klass: 'HUnewearl', level: 31, playtimeMin: 18 * 60 + 30 },
  { kind: 'filled', name: 'Vanta',   klass: 'HUcast',    level: 22, playtimeMin: 7 * 60 + 14 },
  { kind: 'filled', name: 'Iola',    klass: 'HUcaseal',  level: 9,  playtimeMin: 1 * 60 + 22 },
  { kind: 'filled', name: 'Kale',    klass: 'RAmar',     level: 50, playtimeMin: 60 * 60 + 0 },
  { kind: 'filled', name: 'Reine',   klass: 'RAmarl',    level: 14, playtimeMin: 3 * 60 + 8 },
  { kind: 'filled', name: 'Echo',    klass: 'RAcaseal',  level: 38, playtimeMin: 25 * 60 + 41 },
  { kind: 'filled', name: 'Pell',    klass: 'FOmar',     level: 20, playtimeMin: 6 * 60 + 55 },
  { kind: 'filled', name: 'Fenn',    klass: 'FOmarl',    level: 16, playtimeMin: 4 * 60 + 17 },
  { kind: 'filled', name: 'Vexi',    klass: 'FOnewm',    level: 11, playtimeMin: 2 * 60 + 33 },
  { kind: 'filled', name: 'Quill',   klass: 'HUmar',     level: 7,  playtimeMin: 48 },
  { kind: 'filled', name: 'Pyx',     klass: 'FOnewearl', level: 3,  playtimeMin: 19 },
  { kind: 'empty' }, { kind: 'empty' }, { kind: 'empty' },
  { kind: 'empty' }, { kind: 'empty' }, { kind: 'empty' },
];

const CLASS_FLAVOR: Record<string, string> = {
  HUmar:     'Balanced human Hunter. Strong ATP, decent EVP, no techs.',
  HUnewearl: 'Newman Hunter. Trades raw ATP for higher EVP and basic techs.',
  HUcast:    'Cast Hunter. Highest HP and ATP, immune to status, no techs.',
  HUcaseal:  'Female Cast Hunter. ATA-leaning Cast variant, no techs.',
  RAmar:     'Human Ranger. Solid all-rounder with mid-tier techs.',
  RAmarl:    'Female human Ranger. Higher MST than RAmar, basic support techs.',
  RAcast:    'Cast Ranger. Trap specialist, immune to status, no techs.',
  RAcaseal:  'Female Cast Ranger. ATA-leaning, traps, no techs.',
  FOmar:     'Male Force. Balanced caster, ATP+ over FOnewearl.',
  FOmarl:    'Female human Force. Highest ATA caster.',
  FOnewm:    'Male Newman Force. Stronger tech multipliers than human Forces.',
  FOnewearl: 'Newman Force. Highest tech multiplier in the game; fragile.',
};

function fmtPlaytime(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h > 0 ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}m`;
}

function Panel({ title, children, hint }: { title?: string; children: React.ReactNode; hint?: string }) {
  return (
    <div style={{ width: '100%', display: 'flex', flexDirection: 'column', filter: 'drop-shadow(0 2px 8px rgba(0,0,0,0.25))' }}>
      {title && (
        <div style={{ position: 'relative', height: 36, marginBottom: -1 }}>
          <div style={{ position: 'absolute', inset: 0, background: C.bgDark, clipPath: 'polygon(0 0, 85% 0, 80% 100%, 0 100%)' }} />
          <div style={{ position: 'absolute', top: 0, right: 0, bottom: 0, width: '30%', background: `linear-gradient(135deg, transparent 30%, ${C.bgDarker} 30%, ${C.bgDarker} 35%, ${C.bgDark} 35%)` }} />
          <div style={{ position: 'relative', padding: '6px 16px', fontSize: 16, fontWeight: 800, color: C.textWhite, fontStyle: 'italic', letterSpacing: 0.5, textShadow: '1px 1px 0 rgba(0,0,0,0.5)', zIndex: 1 }}>{title}</div>
        </div>
      )}
      <div style={{ flex: 1, background: C.bgLight, backgroundImage: SCANLINES, borderTop: `2px solid ${C.bgDark}`, borderBottom: hint ? 'none' : `2px solid ${C.separator}`, padding: 8 }}>{children}</div>
      {hint && (
        <div style={{ background: C.hintBg, backgroundImage: SCANLINES, border: `1px solid ${C.hintBorder}`, borderRadius: '0 0 20px 20px', padding: '8px 20px', fontSize: 14, color: C.text, marginTop: 8, textAlign: 'center' }}>{hint}</div>
      )}
    </div>
  );
}

function PillRow({ label, selected, rightText, onClick }: { label: string; selected?: boolean; rightText?: string; onClick?: () => void }) {
  return (
    <div onClick={onClick} style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '7px 14px', marginBottom: 3,
      background: selected ? C.selectedGradient : C.itemBg,
      borderRadius: 3, border: selected ? '2px solid #d08010' : '1px solid rgba(150,180,210,0.4)',
      cursor: 'pointer', fontSize: 14, fontWeight: 600, color: C.text,
    }}>
      <span>{label}</span>
      {rightText && <span style={{ fontSize: 12, color: C.textLight }}>{rightText}</span>}
    </div>
  );
}

function ModelPreview({ classId }: { classId: string | null }) {
  const ref = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<{ scene: THREE.Scene; camera: THREE.PerspectiveCamera; renderer: THREE.WebGLRenderer; group: THREE.Group; raf: number } | null>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const w = el.clientWidth, h = el.clientHeight;
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(35, w / h, 0.1, 100);
    camera.position.set(0, 1.1, 3.4);
    camera.lookAt(0, 1.0, 0);
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(w, h);
    renderer.setClearColor(0x000000, 0);
    el.appendChild(renderer.domElement);
    scene.add(new THREE.AmbientLight(0xffffff, 0.85));
    const dir = new THREE.DirectionalLight(0xffffff, 0.7);
    dir.position.set(3, 5, 4);
    scene.add(dir);
    const group = new THREE.Group();
    scene.add(group);
    let raf = 0;
    const animate = () => { renderer.render(scene, camera); raf = requestAnimationFrame(animate); };
    raf = requestAnimationFrame(animate);
    sceneRef.current = { scene, camera, renderer, group, raf };
    return () => { cancelAnimationFrame(raf); renderer.dispose(); if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement); };
  }, []);

  useEffect(() => {
    const sd = sceneRef.current;
    if (!sd) return;
    while (sd.group.children.length) {
      const c = sd.group.children[0];
      sd.group.remove(c);
      c.traverse((o) => { const m = o as THREE.Mesh; if (m.geometry) m.geometry.dispose(); });
    }
    if (!classId) return;
    const prefix = CLASS_TO_PREFIX[classId];
    if (!prefix) return;
    const v = `${prefix}0`;
    const url = assetUrl(`assets/player/${v}/${v}_000.glb`);
    const texUrl = assetUrl(`assets/player/${v}/textures/${v}_000.png`);
    new GLTFLoader().load(url, (gltf) => {
      new THREE.TextureLoader().load(texUrl, (tex) => {
        tex.magFilter = THREE.NearestFilter;
        tex.minFilter = THREE.NearestFilter;
        tex.flipY = false;
        tex.colorSpace = THREE.SRGBColorSpace;
        gltf.scene.traverse((o) => { const m = o as THREE.Mesh; if (m.isMesh && m.material) { (m.material as THREE.MeshBasicMaterial).map = tex; (m.material as THREE.MeshBasicMaterial).needsUpdate = true; } });
      });
      sd.group.add(gltf.scene);
    });
  }, [classId]);

  return <div ref={ref} style={{ width: '100%', height: '100%' }} />;
}

export default function CharSelectScreen() {
  const [sel, setSel] = useState(0);
  const slot = SLOTS[sel];
  const nextLabel = slot.kind === 'filled' ? 'Start' : 'Create';
  const BG_URL = '/character_select_bg.png';

  return (
    <div style={{
      width: W, height: H, position: 'relative', overflow: 'hidden',
      backgroundImage: `url('${BG_URL}')`, backgroundSize: 'cover', backgroundPosition: 'center',
      fontFamily: "'Segoe UI', 'Helvetica Neue', Arial, sans-serif",
    }}>
      {/* Banner */}
      <div style={{
        position: 'absolute', top: 16, left: 0, width: '100%', height: 63,
        background: '#FBBA18',
        clipPath: 'polygon(0 0, 100% 0, 100% 58%, 49% 58%, 44% 100%, 0 100%)',
        filter: 'drop-shadow(2px 0 0 #1a1a2a) drop-shadow(-2px 0 0 #1a1a2a) drop-shadow(0 2px 0 #1a1a2a) drop-shadow(0 -2px 0 #1a1a2a) drop-shadow(0 4px 6px rgba(0,0,0,0.4))',
        display: 'flex', alignItems: 'flex-start',
      }}>
        <div style={{ padding: '9px 27px', fontSize: 21, fontWeight: 800, fontStyle: 'italic', color: '#1a1a2a', letterSpacing: 1, textShadow: '1px 1px 0 rgba(255,255,255,0.35)' }}>
          CHARACTER SELECT
        </div>
      </div>

      {/* White divider */}
      <div style={{ position: 'absolute', top: 98, left: 0, width: '100%', height: 2, background: '#fff' }} />

      {/* Character list */}
      <div style={{ position: 'absolute', top: 135, left: 150, width: 300, height: 338 }}>
        <Panel title={`Characters (${SLOTS.filter(s => s.kind === 'filled').length}/${SLOTS.length})`} hint="↑/↓ choose · A confirm · B cancel">
          <div style={{ maxHeight: 270, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
            {SLOTS.map((s, i) => (
              <PillRow
                key={i}
                label={s.kind === 'filled' ? `${s.name}  ·  ${s.klass}  ·  Lv.${s.level}` : '(Empty Slot)'}
                rightText={s.kind === 'filled' ? fmtPlaytime(s.playtimeMin) : ''}
                selected={sel === i}
                onClick={() => setSel(i)}
              />
            ))}
          </div>
        </Panel>
      </div>

      {/* Model preview */}
      <div style={{ position: 'absolute', top: 135, left: 510, width: 300, height: 323, zIndex: 1 }}>
        <ModelPreview classId={slot.kind === 'filled' ? slot.klass.toLowerCase() : null} />
        {slot.kind === 'empty' && (
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: C.textLight, fontSize: 13, fontStyle: 'italic', opacity: 0.7, pointerEvents: 'none' }}>
            [ empty slot ]
          </div>
        )}
      </div>

      {/* Description */}
      <div style={{ position: 'absolute', top: 390, left: 502, width: 322, height: 68, zIndex: 2 }}>
        <div style={{
          background: C.bgLight, backgroundImage: SCANLINES, borderRadius: 4,
          padding: '9px 12px', border: '1px solid rgba(60,100,140,0.5)',
          fontSize: 12, color: C.text, lineHeight: 1.45, boxShadow: '0 2px 6px rgba(0,0,0,0.3)',
        }}>
          {slot.kind === 'filled' ? CLASS_FLAVOR[slot.klass] ?? 'Class flavor text TBD.' : 'No character in this slot yet — confirm to create one.'}
        </div>
      </div>

      {/* Next button */}
      <div style={{
        position: 'absolute', bottom: 15, right: 15, width: 180, height: 45,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: C.selectedGradient, color: C.textOnSelected,
        fontWeight: 700, fontSize: 15, borderRadius: 6,
        border: '1px solid rgba(0,0,0,0.25)', boxShadow: '0 3px 8px rgba(0,0,0,0.3)', cursor: 'pointer',
      }}>
        {nextLabel} ▶
      </div>
    </div>
  );
}
