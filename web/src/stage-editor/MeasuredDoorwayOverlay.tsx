import { useEffect, useState } from 'react';
import { assetUrl } from '../utils/assets';

/**
 * psz-re's MEASURED doorways, drawn over the stage so an authored portal can be
 * compared against the real thing.
 *
 * The portals in unified-stage-configs.json were hand-placed in this editor.
 * Measured against psz-re's doorway segments they are better than expected
 * ALONG the wall — median 0.11 units — and wrong in DEPTH: a gate sits a median
 * 1.88 units inside the room wall, with a tail that reaches 20. This overlay is
 * how you see which is which per stage instead of trusting an aggregate.
 *
 * THE TWO TABLES DISAGREE ABOUT NORTH. psz-re names the -z wall `south`; this
 * project names it `north`. East and west agree. Mapping N/S only gives 553
 * portals matched with none more than 2 units out along the wall; mapping E/W
 * as well invents 85 outliers of ±32 that arrive in symmetric east/west pairs.
 * Nothing here needs the wall name — the segment carries its own coordinates —
 * but it is recorded because reading these two files together without knowing
 * it produces a convincing-looking disaster.
 *
 * A doorway is a segment running from the room wall (|22|) out to the end of
 * its stub (|25|). Drawn as a slab over that span, so you can see whether the
 * gate marker sits in the mouth, inside the room, or out past the stub — that
 * last one being what broke the autopilot when the depth migration was tried:
 * the load trigger derives from the gate at +7 and its near face at +4, so a
 * gate on the wall puts the trigger past the end of the stub, over nothing.
 */

interface DoorwayRoom {
  doors: number;
  segments: [[number, number], [number, number]][];
  walls?: { wall: string; offset: number }[];
}

interface Props {
  /** Stage id as the configs key it, e.g. `s01a_ga1`. */
  stageId: string;
  /** Ground height to draw at; stages sit at y=0. */
  y?: number;
}

export default function MeasuredDoorwayOverlay({ stageId, y = 0.08 }: Props) {
  const [rooms, setRooms] = useState<Record<string, DoorwayRoom> | null>(null);

  useEffect(() => {
    fetch(assetUrl('/data/re_reference/room_doorways.json'))
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => setRooms(d?.rooms ?? null))
      .catch(() => setRooms(null));
  }, []);

  const room = rooms?.[stageId];
  if (!room) return null;

  return (
    <group>
      {room.segments.map((seg, i) => {
        const [[x1, z1], [x2, z2]] = seg;
        const cx = (x1 + x2) / 2;
        const cz = (z1 + z2) / 2;
        const dx = x2 - x1;
        const dz = z2 - z1;
        const len = Math.hypot(dx, dz) || 1;
        // Segments run along the depth axis (wall -> stub end), so the slab is
        // oriented by the segment itself rather than by a wall name.
        const angle = Math.atan2(dz, dx);
        return (
          <group key={i} position={[cx, y, cz]} rotation={[0, -angle, 0]}>
            {/* The doorway span, wall end to stub end. */}
            <mesh rotation={[-Math.PI / 2, 0, 0]}>
              <planeGeometry args={[len, 1.2]} />
              <meshBasicMaterial color="#38bdf8" transparent opacity={0.45} />
            </mesh>
            {/* The wall end — where a gate belongs geometrically. */}
            <mesh position={[-len / 2, 0.3, 0]}>
              <boxGeometry args={[0.25, 2.4, 3.0]} />
              <meshBasicMaterial color="#0ea5e9" />
            </mesh>
            {/* The stub end — nothing past this, which is the constraint the
                load trigger has to respect. */}
            <mesh position={[len / 2, 0.15, 0]}>
              <boxGeometry args={[0.25, 1.0, 3.0]} />
              <meshBasicMaterial color="#7dd3fc" transparent opacity={0.8} />
            </mesh>
          </group>
        );
      })}
    </group>
  );
}
