import { useEffect, useMemo, useState } from 'react';
import { assetUrl } from '../utils/assets';
import { filterByLayout } from './layoutMasks';

/**
 * The objects the ORIGINAL authors into this room, drawn where it puts them.
 *
 * Boxes, walls and all nine trap families are authored per room in
 * set/<NN>/<v>/<room>/*.rel, imported to data/re_reference/room_objects.json.
 * Room-local (x, y, z) in the same frame as room_doorways.json, plus a 16-bit
 * facing. Nothing is scattered at runtime — which is why a ring of boxes never
 * lined up with anything, and why this can be checked against the geometry at
 * all.
 *
 * WHAT YOU ARE LOOKING AT IS THE TABLE, NOT ONE INSTANCE. A room does not
 * build everything here: a file is six groups, one of five layout masks picks
 * which of groups 0..4 get built, and group 5 is rolled 0..3 at 40/20/20/20. So a real
 * visit shows a subset. Group is on the label so the subsets are legible —
 * everything in the same group arrives together. The Authored tab can also
 * filter this overlay to ONE layout's outcome (`layoutMask` + `group5Count`);
 * without it, every record renders regardless of group.
 */

interface AuthoredObject {
  g?: number | null;
  k: string;
  x: number;
  y: number;
  z: number;
  a?: number;
  m?: string;
  link?: string;
}

interface Props {
  /** Stage id, e.g. `s01a_td1`. The table is keyed `<stage>_<set>`. */
  stageId: string;
  /** Deploy set; psz-godot rolls from `d` (FieldPopulation.DEPLOY_SET). */
  set?: string;
  /** Only draw these kinds; undefined draws all. */
  kinds?: string[];
  /** A layout-mask value renders only that layout's outcome; null/undefined
   * renders the whole table. */
  layoutMask?: number | null;
  /** Group 5's rolled count (0–3) when previewing a layout. */
  group5Count?: number;
}

/** Colour per family, so a room reads at a glance rather than by hovering. */
const KIND_COLOR: Record<string, string> = {
  box: '#c9a06e',
  rare_box: '#ffd166',
  wall: '#8a8a9a',
  fence: '#38bdf8',
  step_switch: '#a78bfa',
  needler_trap: '#ff6b6b',
  burn_trap: '#ff8a5c',
  gun_trap: '#f472b6',
  capture_trap: '#fb7185',
  poison_trap: '#84cc16',
  heal_trap: '#6ee7b7',
  heat_trap: '#fca5a5',
  light_trap: '#fde68a',
  ice_trap: '#93c5fd',
};

const FALLBACK = '#e0e0e0';

interface ReferenceRoom {
  objects?: { k: string; m?: string; x: number; y: number; z: number }[];
  enemies?: { x: number; y: number; z: number }[];
  blocks?: number;
  flags?: number[];
}

export default function AuthoredObjectOverlay({ stageId, set = 'd', kinds, layoutMask, group5Count }: Props) {
  const [rooms, setRooms] = useState<Record<string, { objects: AuthoredObject[] }> | null>(null);
  // The REFERENCE layer: what the original has here that we do not place.
  // Separate file, separate risk — nothing in it reaches the game.
  const [reference, setReference] = useState<Record<string, ReferenceRoom> | null>(null);

  useEffect(() => {
    fetch(assetUrl('/data/re_reference/room_objects.json'))
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => setRooms(d?.rooms ?? null))
      .catch(() => setRooms(null));
    fetch(assetUrl('/data/re_reference/room_reference.json'))
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => setReference(d?.rooms ?? null))
      .catch(() => setReference(null));
  }, []);

  const objects = useMemo(() => {
    const entry = rooms?.[`${stageId}_${set}`];
    if (!entry) return [];
    const list = kinds ? entry.objects.filter((o) => kinds.includes(o.k)) : entry.objects;
    return layoutMask == null ? list : filterByLayout(list, layoutMask, group5Count ?? 0);
  }, [rooms, stageId, set, kinds, layoutMask, group5Count]);

  const ref = reference?.[`${stageId}_${set}`];
  const refObjects = (ref?.objects ?? []).filter(
    (o) => !kinds || kinds.includes(o.k),
  );
  const spawns = !kinds || kinds.includes('enemy spawn') ? ref?.enemies ?? [] : [];

  if (objects.length === 0 && refObjects.length === 0 && spawns.length === 0) return null;

  return (
    <group>
      {/* WHAT THE ORIGINAL HAS AND WE DO NOT PLACE. Drawn as open wireframe so
          it never reads as something the game builds: authored keys (the
          original places them per room; we scatter by rule), enemy spawn slots
          (we still use a blind 5-unit ring), and kinds nobody has identified. */}
      {refObjects.map((o, i) => (
        <group key={`ref${i}`} position={[o.x, o.y, o.z]}>
          <mesh position={[0, 0.9, 0]}>
            <boxGeometry args={[1.2, 1.8, 1.2]} />
            <meshBasicMaterial
              color={o.k === 'key' ? '#ffd166' : '#7a7f9a'}
              wireframe
            />
          </mesh>
        </group>
      ))}
      {spawns.map((e, i) => (
        <group key={`spawn${i}`} position={[e.x, e.y, e.z]}>
          {/* Elevation matters here — a slot sitting above the floor is the
              "enemies standing on rocks" case, so the post shows the drop. */}
          <mesh position={[0, 0.9, 0]}>
            <cylinderGeometry args={[0.55, 0.55, 1.8, 10]} />
            <meshBasicMaterial color="#f87171" wireframe />
          </mesh>
          <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.04, 0]}>
            <ringGeometry args={[0.5, 0.75, 14]} />
            <meshBasicMaterial color="#f87171" />
          </mesh>
        </group>
      ))}
      {objects.map((o, i) => {
        const color = KIND_COLOR[o.k] ?? FALLBACK;
        // Facing is 16 bits per turn, 0 = +Z toward +X — the same convention
        // Godot's rotation.y uses, so this is a scale and nothing else.
        const yaw = ((o.a ?? 0) / 65536) * Math.PI * 2;
        const isWall = o.k === 'wall';
        const isTrap = o.k.endsWith('_trap');
        return (
          <group key={i} position={[o.x, o.y, o.z]} rotation={[0, yaw, 0]}>
            {/* A box-ish body for containers and walls, a flat disc for traps —
                traps sit ON the floor and a tall box would hide the geometry
                under them, which is the thing being checked. */}
            {isTrap ? (
              <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.06, 0]}>
                <circleGeometry args={[1.1, 20]} />
                <meshBasicMaterial color={color} transparent opacity={0.75} />
              </mesh>
            ) : (
              <mesh position={[0, isWall ? 1.4 : 0.7, 0]}>
                <boxGeometry args={isWall ? [4.0, 2.8, 0.5] : [1.6, 1.4, 1.6]} />
                <meshBasicMaterial color={color} transparent opacity={0.65} />
              </mesh>
            )}
            {/* Ground ring, so an object hovering over a hole is obvious. */}
            <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.03, 0]}>
              <ringGeometry args={[0.75, 1.0, 16]} />
              <meshBasicMaterial color={color} />
            </mesh>
          </group>
        );
      })}
    </group>
  );
}

export { KIND_COLOR };
export type { AuthoredObject };
