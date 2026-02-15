import { useMemo, useRef, useCallback } from 'react';
import type { ThreeEvent } from '@react-three/fiber';
import * as THREE from 'three';
import type { FloorTriangle } from './types';

interface FloorOverlayProps {
  triangles: FloorTriangle[];
  yOffset?: number;
  onTriangleClick?: (triangleId: string) => void;
  interactive?: boolean;
}

export default function FloorOverlay({
  triangles,
  yOffset = 0.1,
  onTriangleClick,
  interactive = false,
}: FloorOverlayProps) {
  const meshRef = useRef<THREE.Mesh>(null);

  // Build geometry with vertex colors
  const geometry = useMemo(() => {
    if (triangles.length === 0) return null;

    const geo = new THREE.BufferGeometry();
    const vertices: number[] = [];
    const colors: number[] = [];

    // Colors for included (green) and excluded (red)
    const includedColor = new THREE.Color(0x00ff00);
    const excludedColor = new THREE.Color(0xff4444);

    triangles.forEach((tri) => {
      const color = tri.included ? includedColor : excludedColor;

      tri.vertices.forEach((v) => {
        vertices.push(v.x, v.y + yOffset, v.z);
        colors.push(color.r, color.g, color.b);
      });
    });

    geo.setAttribute('position', new THREE.Float32BufferAttribute(vertices, 3));
    geo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    geo.computeVertexNormals();

    return geo;
  }, [triangles, yOffset]);

  // Handle click - find which triangle was clicked
  const handleClick = useCallback(
    (event: ThreeEvent<MouseEvent>) => {
      if (!onTriangleClick || !interactive) return;

      event.stopPropagation();

      // Get the face index from the intersection
      const faceIndex = event.faceIndex;
      if (faceIndex === undefined || faceIndex === null) return;

      // Each triangle is one face, so faceIndex directly maps to triangle index
      if (faceIndex >= 0 && faceIndex < triangles.length) {
        const triangle = triangles[faceIndex];
        onTriangleClick(triangle.id);
      }
    },
    [triangles, onTriangleClick, interactive]
  );

  // Handle pointer for hover effect
  const handlePointerOver = useCallback(
    (event: ThreeEvent<PointerEvent>) => {
      if (!interactive) return;
      event.stopPropagation();
      document.body.style.cursor = 'pointer';
    },
    [interactive]
  );

  const handlePointerOut = useCallback(() => {
    if (!interactive) return;
    document.body.style.cursor = 'auto';
  }, [interactive]);

  if (!geometry) return null;

  return (
    <mesh
      ref={meshRef}
      geometry={geometry}
      onClick={handleClick}
      onPointerOver={handlePointerOver}
      onPointerOut={handlePointerOut}
    >
      <meshBasicMaterial
        vertexColors
        transparent
        opacity={interactive ? 0.5 : 0.4}
        side={THREE.DoubleSide}
        depthWrite={false}
      />
    </mesh>
  );
}
