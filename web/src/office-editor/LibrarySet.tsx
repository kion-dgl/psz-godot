import * as THREE from 'three';
import { useMemo } from 'react';
import { useTexture } from '@react-three/drei';
import { assetUrl } from '../utils/assets';

/**
 * PSZ Principal's-office library (#356), curved-room pass.
 *
 * Round hall: a circular marble floor, a curved apse wall wrapping the back
 * ~270° (open at the front entrance), the stained-glass sun window at the
 * apse's back-centre, bookshelves arranged along the arc facing inward, and a
 * wood desk on a dais. Textures: the office's own in-game marble floor +
 * carved-stone wall (city_e), plus CC0 wood (ambientCG Wood062) for the
 * shelves/desk. Built from primitives so it iterates against screenshots.
 */

// Dairon city textures, used by ZONE rather than tiled uniformly:
//   floor field  = tile1b (octagonal stone), tiled
//   floor centre = floor05 (ornate marble medallion), shown ONCE under the desk
//   wall flat     = wpwall03 (sa2, plain panelled wall), tiled
//   columns       = discrete fluted geometry (set02 flutes) flanking the window
const TILE1B = 'assets/stages/city_e/market/s00_0_tile1b.png';
const FLOOR05 = 'assets/stages/city_e/market/s00_0_floor05.png';
const WPWALL03 = 'assets/stages/city_e/s00e_sa2/lndmd/s00_0_wpwall03.png';
const COLUMN_TEX = 'assets/stages/city_e/market/s00_0_set02.png';
const WOOD_TEX = 'assets/cc0_textures/wood062_color.jpg';
const STONE_DARK = '#5a5147'; // border / trim separators
const STONE_PALE = '#cdc3aa'; // column base / capital

const R = 9; // room radius
const WALL_H = 6;

const SPINE_COLORS = [
  '#7c3b2f', '#3b5a7c', '#4a7c3b', '#7c6a3b', '#5a3b7c',
  '#7c3b5a', '#3b7c6a', '#6a3b3b', '#3b6a7c', '#7c5a3b',
];

// Place an object on the room arc at angle φ (0 = back-centre, +φ = toward the
// right side), facing the centre.
function onArc(phi: number, radius: number): { pos: [number, number, number]; rotY: number } {
  const x = Math.sin(phi) * radius;
  const z = -Math.cos(phi) * radius;
  return { pos: [x, 0, z], rotY: Math.atan2(x, z) + Math.PI };
}

function Bookshelf({ phi, wood }: { phi: number; wood: THREE.Texture }) {
  const shelves = 6;
  const unitW = 2.6;
  const unitH = 5.2;
  const { pos, rotY } = onArc(phi, R - 0.5);
  const books = useMemo(() => {
    const out: { x: number; y: number; h: number; w: number; color: string }[] = [];
    const gap = unitH / shelves;
    for (let s = 0; s < shelves; s++) {
      const y = 0.4 + s * gap;
      let x = -unitW / 2 + 0.2;
      let i = s * 7 + Math.round(phi * 13);
      while (x < unitW / 2 - 0.2) {
        const w = 0.12 + ((i * 37) % 9) / 60;
        const h = gap * (0.6 + ((i * 53) % 5) / 12);
        out.push({ x: x + w / 2, y: y + h / 2, h, w, color: SPINE_COLORS[(i * 17) % SPINE_COLORS.length] });
        x += w + 0.03;
        i++;
      }
    }
    return out;
  }, [phi]);

  return (
    <group position={pos} rotation={[0, rotY, 0]}>
      <mesh position={[0, unitH / 2, -0.18]} castShadow receiveShadow>
        <boxGeometry args={[unitW, unitH, 0.12]} />
        <meshStandardMaterial map={wood} color="#9b7547" roughness={0.85} />
      </mesh>
      {[-unitW / 2, unitW / 2].map((x) => (
        <mesh key={x} position={[x, unitH / 2, 0]} castShadow>
          <boxGeometry args={[0.16, unitH, 0.5]} />
          <meshStandardMaterial map={wood} roughness={0.8} />
        </mesh>
      ))}
      {Array.from({ length: shelves + 1 }).map((_, s) => (
        <mesh key={s} position={[0, 0.4 + s * (unitH / shelves), 0]} castShadow>
          <boxGeometry args={[unitW, 0.08, 0.46]} />
          <meshStandardMaterial map={wood} color="#c79a5e" roughness={0.8} />
        </mesh>
      ))}
      {books.map((b, i) => (
        <mesh key={i} position={[b.x, b.y, 0.05]} castShadow>
          <boxGeometry args={[b.w, b.h, 0.28]} />
          <meshStandardMaterial color={b.color} roughness={0.7} />
        </mesh>
      ))}
    </group>
  );
}

function SunWindow({ position }: { position: [number, number, number] }) {
  const rings = [
    { r: 3.0, color: '#2c6e7a', e: 0.5 },
    { r: 2.3, color: '#3fa9c9', e: 0.85 },
    { r: 1.5, color: '#bfe9f2', e: 1.1 },
    { r: 0.7, color: '#f2c94c', e: 1.5 },
  ];
  return (
    <group position={position}>
      {rings.map((ring, i) => (
        <mesh key={i} position={[0, 0, i * 0.015]}>
          <circleGeometry args={[ring.r, 48]} />
          <meshStandardMaterial color={ring.color} emissive={ring.color} emissiveIntensity={ring.e} roughness={0.35} metalness={0.1} />
        </mesh>
      ))}
      {Array.from({ length: 12 }).map((_, i) => {
        const a = (i / 12) * Math.PI * 2;
        return (
          <mesh key={i} position={[Math.cos(a) * 1.9, Math.sin(a) * 1.9, 0.07]} rotation={[0, 0, a]}>
            <boxGeometry args={[1.5, 0.16, 0.04]} />
            <meshStandardMaterial color="#e8d28a" emissive="#e8d28a" emissiveIntensity={0.6} />
          </mesh>
        );
      })}
      <mesh position={[0, 0, -0.1]}>
        <ringGeometry args={[3.0, 3.5, 48]} />
        <meshStandardMaterial color="#d8cdb0" roughness={1} side={THREE.DoubleSide} />
      </mesh>
    </group>
  );
}

function Column({ phi, fluted }: { phi: number; fluted: THREE.Texture }) {
  const { pos } = onArc(phi, R - 0.55);
  const h = WALL_H - 1.0;
  return (
    <group position={pos}>
      {/* base */}
      <mesh position={[0, 0.35, 0]} castShadow>
        <cylinderGeometry args={[0.55, 0.62, 0.7, 16]} />
        <meshStandardMaterial color={STONE_PALE} roughness={0.85} />
      </mesh>
      {/* fluted shaft */}
      <mesh position={[0, 0.7 + h / 2, 0]} castShadow>
        <cylinderGeometry args={[0.42, 0.48, h, 20]} />
        <meshStandardMaterial map={fluted} color={STONE_PALE} roughness={0.8} />
      </mesh>
      {/* capital */}
      <mesh position={[0, 0.7 + h + 0.25, 0]} castShadow>
        <cylinderGeometry args={[0.64, 0.5, 0.5, 16]} />
        <meshStandardMaterial color={STONE_PALE} roughness={0.85} />
      </mesh>
    </group>
  );
}

function CurvedScene() {
  const [fieldMap, medallionMap, wallMap, columnMap, woodMap] = useTexture([
    assetUrl(TILE1B), assetUrl(FLOOR05), assetUrl(WPWALL03), assetUrl(COLUMN_TEX), assetUrl(WOOD_TEX),
  ]);
  // Floor field — tiled stone. Medallion — shown once (no tiling).
  fieldMap.wrapS = fieldMap.wrapT = THREE.RepeatWrapping;
  fieldMap.repeat.set(5, 5);
  medallionMap.wrapS = medallionMap.wrapT = THREE.ClampToEdgeWrapping;
  medallionMap.repeat.set(1, 1);
  // Flat wall — one plain panelled texture, tiled.
  wallMap.wrapS = wallMap.wrapT = THREE.RepeatWrapping;
  wallMap.repeat.set(12, 3);
  // Column flutes wrap around the shaft.
  columnMap.wrapS = columnMap.wrapT = THREE.RepeatWrapping;
  columnMap.repeat.set(4, 1);
  woodMap.wrapS = woodMap.wrapT = THREE.RepeatWrapping;
  woodMap.repeat.set(1, 2);

  // Bookshelf angles along the back arc. Skip the very front (entrance) AND
  // φ=0 — directly behind the desk/sun window — so the window reads clean.
  const shelfPhis = [-2.2, -1.7, -1.2, -0.7, 0.7, 1.2, 1.7, 2.2];

  return (
    <group>
      {/* Floor — zoned: outer field, a dark border ring, a centre medallion */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0, 0]} receiveShadow>
        <circleGeometry args={[R, 64]} />
        <meshStandardMaterial map={fieldMap} roughness={0.8} />
      </mesh>
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.012, -4.5]} receiveShadow>
        <ringGeometry args={[4.0, 4.4, 48]} />
        <meshStandardMaterial color={STONE_DARK} roughness={0.9} />
      </mesh>
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.011, -4.5]} receiveShadow>
        <circleGeometry args={[4.0, 48]} />
        <meshStandardMaterial map={medallionMap} roughness={0.65} />
      </mesh>

      {/* Flat apse wall — one plain texture (wpwall03) */}
      <mesh position={[0, WALL_H / 2, 0]}>
        <cylinderGeometry args={[R, R, WALL_H, 64, 1, true, Math.PI * 0.25, Math.PI * 1.5]} />
        <meshStandardMaterial map={wallMap} roughness={0.9} side={THREE.BackSide} />
      </mesh>

      {/* Columns flanking the sun window, plus a pair at the apse opening */}
      {[-0.42, 0.42, -2.45, 2.45].map((p) => (
        <Column key={p} phi={p} fluted={columnMap} />
      ))}

      {/* Sun window at the apse back-centre */}
      <SunWindow position={[0, 3.2, -R + 0.3]} />

      {/* Bookshelves along the arc */}
      {shelfPhis.map((p) => (
        <Bookshelf key={p} phi={p} wood={woodMap} />
      ))}

      {/* Principal's desk on a low dais, centre, facing the entrance */}
      <group position={[0, 0, -4.5]}>
        <mesh position={[0, 0.15, 0]} receiveShadow castShadow>
          <cylinderGeometry args={[3.2, 3.4, 0.3, 32]} />
          <meshStandardMaterial color={STONE_DARK} roughness={0.8} />
        </mesh>
        <mesh position={[0, 1.2, 0]} castShadow receiveShadow>
          <boxGeometry args={[3.4, 0.25, 1.5]} />
          <meshStandardMaterial map={woodMap} color="#c79a5e" roughness={0.6} />
        </mesh>
        <mesh position={[0, 0.65, 0]} castShadow>
          <boxGeometry args={[3.2, 0.9, 1.3]} />
          <meshStandardMaterial map={woodMap} roughness={0.7} />
        </mesh>
      </group>
    </group>
  );
}

export default function LibrarySet() {
  return (
    <group>
      {/* Warm scholarly key + a cool glow from the window */}
      <ambientLight intensity={0.4} color="#cdb088" />
      <hemisphereLight args={['#e0cba0', '#3a2c1c', 0.55]} />
      <pointLight position={[0, 5, 2]} intensity={45} color="#ffd9a0" castShadow />
      <pointLight position={[0, 4, -7]} intensity={30} color="#9fe8ff" />
      <directionalLight position={[6, 10, 6]} intensity={0.35} color="#fff2dd" />
      <CurvedScene />
    </group>
  );
}
