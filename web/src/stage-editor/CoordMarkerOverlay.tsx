// Pin a vertical post at a fixed XZ — the cheapest possible "go look at
// (x, z) in the editor" tool. The post is tall (~10 m) so it stays
// visible above whatever stage geometry obscures the ground at that
// point. Color = magenta so it doesn't blend with any of the existing
// overlays (green floor, red walls, yellow path, cyan waypoints).

interface Props {
  x: number;
  z: number;
}

export default function CoordMarkerOverlay({ x, z }: Props) {
  return (
    <group position={[x, 0, z]}>
      {/* Tall thin post — visible from any camera angle */}
      <mesh position={[0, 5, 0]}>
        <cylinderGeometry args={[0.15, 0.15, 10, 12]} />
        <meshBasicMaterial color="#ec4899" />
      </mesh>
      {/* Base ring on the ground for unambiguous XZ */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.05, 0]}>
        <ringGeometry args={[0.8, 1.2, 24]} />
        <meshBasicMaterial color="#ec4899" />
      </mesh>
      {/* Sphere at the top for visual punctuation */}
      <mesh position={[0, 10, 0]}>
        <sphereGeometry args={[0.4, 12, 8]} />
        <meshBasicMaterial color="#f9a8d4" />
      </mesh>
    </group>
  );
}
