// QuestObjectOverlay — colored markers for per-cell quest objects so the
// user knows where switches / fences / key drops / NPCs sit when authoring
// the stage's waypoint graph. Pure visual aid; doesn't write to anything.

import { Html } from '@react-three/drei';
import type { QuestObjectMarker, QuestObjectKind } from './useQuestObjects';

interface Props {
  markers: QuestObjectMarker[];
  highlightCell?: string | null;
}

const COLOR: Record<QuestObjectKind, string> = {
  switch: '#22d3ee',     // cyan
  fence: '#f87171',      // red
  key_drop: '#fbbf24',   // gold
  npc: '#a78bfa',        // purple
  story_prop: '#34d399', // green
  dialog: '#94a3b8',     // slate
};

const MARKER_SIZE: Record<QuestObjectKind, number> = {
  switch: 0.7,
  fence: 0.5,
  key_drop: 0.5,
  npc: 0.7,
  story_prop: 0.6,
  dialog: 0.4,
};

export default function QuestObjectOverlay({ markers, highlightCell }: Props) {
  return (
    <group>
      {markers.map((m, i) => {
        const isHighlighted = highlightCell == null || m.cellPos === highlightCell;
        const color = COLOR[m.kind];
        const size = MARKER_SIZE[m.kind];
        return (
          <group key={`${m.kind}_${m.cellPos}_${i}`} position={[m.position[0], m.position[1] + 0.3, m.position[2]]}>
            {/* Fence: render as a thin red bar instead of a sphere */}
            {m.kind === 'fence' ? (
              <mesh>
                <boxGeometry args={[3.0, 0.2, 0.3]} />
                <meshBasicMaterial color={color} opacity={isHighlighted ? 0.85 : 0.25} transparent />
              </mesh>
            ) : (
              <mesh>
                <sphereGeometry args={[size, 12, 8]} />
                <meshBasicMaterial color={color} opacity={isHighlighted ? 0.9 : 0.25} transparent />
              </mesh>
            )}
            {/* Vertical post so the marker is visible above the floor at any zoom */}
            <mesh position={[0, size + 0.5, 0]}>
              <cylinderGeometry args={[0.05, 0.05, 1.0, 6]} />
              <meshBasicMaterial color={color} opacity={isHighlighted ? 0.7 : 0.2} transparent />
            </mesh>
            {isHighlighted && (
              <Html
                center
                position={[0, size + 1.2, 0]}
                style={{
                  pointerEvents: 'none',
                  background: 'rgba(0, 0, 0, 0.75)',
                  color,
                  padding: '2px 6px',
                  borderRadius: 3,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  whiteSpace: 'nowrap',
                  border: `1px solid ${color}`,
                }}
              >
                {m.label}
              </Html>
            )}
          </group>
        );
      })}
    </group>
  );
}
