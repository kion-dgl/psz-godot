import { Component, Suspense, useEffect, useMemo, useState } from 'react';
import * as THREE from 'three';
import { assetUrl } from '../utils/assets';
import { filterByLayout } from './layoutMasks';
import { authoredModelFor } from './authoredModelMap';
import { getAreaFromMapId } from './constants';
import AuthoredObjectModel from './AuthoredObjectModel';
import type { AuthoredModel } from './authoredModelMap';

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
 * everything in the same group arrives together. The Authored tab filters
 * this overlay to ONE layout's outcome (`layoutMask` + `group5Count`); kinds
 * with an identified model render as that model, the rest as markers.
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
  /** The loaded stage mesh — spawn slots floor-snap against it, mirroring
   * cell_object_spawner._floor_y_at. Null while the stage streams in. */
  stageScene?: THREE.Group | null;
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
/** A model that failed to load renders its marker in this, so a dead fetch
 * never reads as "still loading" or as a kind colour. */
const ERROR_COLOR = '#ff2d55';

/** The coloured placeholder for one record — a box-ish body for containers
 * and walls, a flat disc for traps (traps sit ON the floor; a tall box would
 * hide the geometry under them, which is the thing being checked). Doubles as
 * the fallback while a model streams in and when its GLB fails to load. */
function Marker({ k, color }: { k: string; color: string }) {
  const isWall = k === 'wall';
  const isTrap = k.endsWith('_trap');
  return isTrap ? (
    <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.06, 0]}>
      <circleGeometry args={[1.1, 20]} />
      <meshBasicMaterial color={color} transparent opacity={0.75} />
    </mesh>
  ) : (
    <mesh position={[0, isWall ? 1.4 : 0.7, 0]}>
      <boxGeometry args={isWall ? [4.0, 2.8, 0.5] : [1.6, 1.4, 1.6]} />
      <meshBasicMaterial color={color} transparent opacity={0.65} />
    </mesh>
  );
}

/** Keeps a failed model render (CDN hiccup, missing GLB, bad mesh) from
 * taking the whole canvas down. The fallback marker renders in signal red so
 * a failure is visible in the viewport rather than silently back to normal. */
class ModelBoundary extends Component<
  { fallback: React.ReactNode; children: React.ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch(error: unknown) {
    console.error('[authored models] falling back to marker:', error);
  }
  render() {
    return this.state.failed ? this.props.fallback : this.props.children;
  }
}

interface ReferenceRoom {
  objects?: { k: string; m?: string; g?: number | null; x: number; y: number; z: number }[];
  enemies?: { x: number; y: number; z: number }[];
  blocks?: number;
  flags?: number[];
}

export default function AuthoredObjectOverlay({ stageId, set = 'd', kinds, layoutMask, group5Count, stageScene }: Props) {
  // The area picks per-field box/wall art from the catalog.
  const area = useMemo(() => getAreaFromMapId(stageId) ?? undefined, [stageId]);
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
  // The reference layer renders in EVERY layout: keys exist regardless of the
  // drawn mask (field_population.key_slot_positions prefers in-mask slots and
  // falls back to all — which rooms hold keys is the gate economy's
  // decision), enemy slots belong to the room's wave, and treasure boxes /
  // unidentified kinds are measured but not placed. The group tag on a record
  // says which arrangement its position belongs to, not whether it appears.
  const refObjects = useMemo(
    () => (ref?.objects ?? []).filter((o) => !kinds || kinds.includes(o.k)),
    [ref, kinds],
  );
  const spawns = !kinds || kinds.includes('enemy spawn') ? ref?.enemies ?? [] : [];

  // Everything drawn from the measured tables floor-snaps before display,
  // because that is what the game does: cell_object_spawner._place_on_floor
  // rays y 60→−60 against floor/environment for enemies (#604) and key
  // pickups (#627), so the authored y never reaches the world. This mirrors
  // that ray against the stage mesh — a slot whose surface turns out to be a
  // rock top is visible as such; a slot with NO surface under it stays at
  // its authored height and is a real finding (the game would relocate it
  // toward the room centre).
  const snapY = useMemo(() => {
    if (!stageScene) return null;
    stageScene.updateMatrixWorld(true);
    const ray = new THREE.Raycaster();
    ray.ray.direction.set(0, -1, 0);
    return (x: number, z: number): number | null => {
      ray.ray.origin.set(x, 60, z);
      const hit = ray.intersectObject(stageScene, true)[0];
      return hit ? hit.point.y : null;
    };
  }, [stageScene]);

  const snappedSpawns = useMemo(
    () => spawns.map((e) => ({ ...e, floorY: snapY?.(e.x, e.z) ?? null })),
    [spawns, snapY],
  );

  const snappedRefs = useMemo(
    () => refObjects.map((o) => ({ ...o, floorY: snapY?.(o.x, o.z) ?? null })),
    [refObjects, snapY],
  );

  if (objects.length === 0 && refObjects.length === 0 && spawns.length === 0) return null;

  return (
    <group>
      {/* WHAT THE ORIGINAL HAS AND WE DO NOT PLACE. Drawn as open wireframe so
          it never reads as something the game builds: authored keys (the
          original places them per room; we scatter by rule), enemy spawn slots
          (we still use a blind 5-unit ring), and kinds nobody has identified. */}
      {snappedRefs.map((o, i) => (
        <group key={`ref${i}`} position={[o.x, o.floorY ?? o.y, o.z]}>
          {o.floorY == null && o.y > 0.01 && (
            <mesh position={[0, -o.y / 2, 0]}>
              <cylinderGeometry args={[0.05, 0.05, o.y, 6]} />
              <meshBasicMaterial
                color={o.k === 'key' ? '#ffd166' : '#7a7f9a'}
                transparent
                opacity={0.6}
              />
            </mesh>
          )}
          <mesh position={[0, 0.9, 0]}>
            <boxGeometry args={[1.2, 1.8, 1.2]} />
            <meshBasicMaterial
              color={o.k === 'key' ? '#ffd166' : '#7a7f9a'}
              wireframe
            />
          </mesh>
        </group>
      ))}
      {snappedSpawns.map((e, i) => (
        <group key={`spawn${i}`} position={[e.x, e.floorY ?? e.y, e.z]}>
          {/* No surface under the slot (the ray missed): keep the authored
              height and drop a line to the floor so the gap is what you see
              — in-game _place_on_floor would relocate this slot. */}
          {e.floorY == null && e.y > 0.01 && (
            <mesh position={[0, -e.y / 2, 0]}>
              <cylinderGeometry args={[0.05, 0.05, e.y, 6]} />
              <meshBasicMaterial color="#f87171" transparent opacity={0.6} />
            </mesh>
          )}
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
        const model = authoredModelFor(o.k, o.m, area);
        return (
          <group key={i} position={[o.x, o.y, o.z]} rotation={[0, yaw, 0]}>
            {/* The storybook model when the kind has one — the marker while
                it streams in, when it fails (in red), and for kinds with no
                identified model (the elemental trap families). */}
            {model ? (
              <ModelBoundary fallback={<Marker k={o.k} color={ERROR_COLOR} />}>
                <Suspense fallback={<Marker k={o.k} color={color} />}>
                  <AuthoredObjectModel model={model} />
                </Suspense>
              </ModelBoundary>
            ) : (
              <Marker k={o.k} color={color} />
            )}
            {/* Ground ring, so an object hovering over a hole is obvious —
                kept in model mode too, as the position anchor. */}
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
