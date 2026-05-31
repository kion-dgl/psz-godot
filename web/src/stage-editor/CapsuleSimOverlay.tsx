// CapsuleSimOverlay — animates a capsule (sphere) along a polyline of world
// XZ corners, checking at each step that the current position is on a floor
// triangle. If it lands off-floor, the animation stops and a red marker
// pins the failure spot — same diagnostic the autopilot's floor-only mode
// uses, but visible in the editor at editor frame rate (no godot launch).
//
// Stops with status "ok" when it reaches the last corner without finding
// an off-floor sample.
//
// Two modes:
//   • Single-leg (path)   — walks one path; used for spot-checking the BFS
//     route between any two waypoints.
//   • Multi-leg (legs)    — walks a sequence of legs in order, with a
//     `switchActivationLegIndex` that marks when the linked-fence opens.
//     Used to play the full per-cell autopilot sequence
//     (spawn → switch → exit through opened fence).

import { useEffect, useRef, useState } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import { pointInTriangle, type Tri2D } from './manhattan/solver';

export interface SimLeg {
  path: { x: number; z: number }[];
  label?: string;
}

interface Props {
  /** Single-leg mode: polyline corners walked once. */
  path?: { x: number; z: number }[];
  /** Multi-leg mode: each leg walked in order. Overrides `path` when set. */
  legs?: SimLeg[];
  /** After leg index N completes, the linked-fence opens (rendered as faded
   *  green instead of red). Only meaningful when `legs` + `fences` are set. */
  switchActivationLegIndex?: number;
  /** Closed-fence positions to render as red bars (pre-switch) → faded green
   *  (post-switch). Visualization only; the floor-check ignores fences. */
  fences?: { x: number; z: number; halfWidth?: number }[];
  /** Floor triangle list (XZ projection). Used for the per-step floor test. */
  floor: Tri2D[];
  /** Capsule speed in meters per second. */
  speed?: number;
  /** Capsule radius (rendered as a sphere). */
  radius?: number;
  /** Sub-stepping for the floor probe — how many meters between samples
   *  along each leg (smaller catches narrower holes). */
  sampleStep?: number;
  /** Y for rendering the capsule above the ground. */
  y?: number;
  /** Called when the sim ends (either reached the end or hit a hole). */
  onComplete?: (result: { ok: boolean; failedAt?: { x: number; z: number }; legIndex?: number }) => void;
  /** Called when the capsule reaches the end of leg N. Used by the parent
   *  UI to update the phase indicator (pre-switch / post-switch). */
  onLegComplete?: (legIndex: number) => void;
  /** Restart counter — when this value changes, re-run from the start. */
  restartKey: number;
}

export default function CapsuleSimOverlay({
  path,
  legs,
  switchActivationLegIndex,
  fences = [],
  floor,
  speed = 6,
  radius = 0.4,
  sampleStep = 0.25,
  y = 0.4,
  onComplete,
  onLegComplete,
  restartKey,
}: Props) {
  // Flatten input to a single corner sequence with a parallel `legEndAt`
  // index → leg-end-marker map. This preserves the simple original
  // "iterate over consecutive corners" loop structure (which avoided the
  // edge case of landing exactly on a leg-boundary corner), while still
  // letting us fire `onLegComplete` and trigger fence-open on the right
  // boundary.
  const internalLegs: SimLeg[] = legs ?? (path && path.length >= 2 ? [{ path }] : []);
  const flatCorners: { x: number; z: number }[] = [];
  // legEndCornerIdx[i] = the corner index where leg i ends.
  const legEndCornerIdx: number[] = [];
  for (let li = 0; li < internalLegs.length; li++) {
    const lg = internalLegs[li];
    if (lg.path.length === 0) continue;
    if (flatCorners.length === 0) {
      flatCorners.push(lg.path[0]);
    } else {
      // Skip duplicate boundary if this leg starts where prev leg ended.
      const last = flatCorners[flatCorners.length - 1];
      const first = lg.path[0];
      if (Math.hypot(first.x - last.x, first.z - last.z) > 0.01) {
        flatCorners.push(first);
      }
    }
    for (let i = 1; i < lg.path.length; i++) flatCorners.push(lg.path[i]);
    legEndCornerIdx.push(flatCorners.length - 1);
  }

  const meshRef = useRef<THREE.Mesh>(null!);
  const stateRef = useRef({
    cornerIdx: 0,    // segment-start corner; segment = (cornerIdx → cornerIdx+1)
    segProgress: 0,  // meters along current segment
    finished: false,
    failedAt: null as { x: number; z: number } | null,
  });
  const [legsCompleted, setLegsCompleted] = useState(0);
  const [, forceRender] = useState(0);
  const [trailPoints, setTrailPoints] = useState<{ x: number; z: number }[]>([]);

  // Reset state on restart.
  useEffect(() => {
    stateRef.current = { cornerIdx: 0, segProgress: 0, finished: false, failedAt: null };
    setLegsCompleted(0);
    setTrailPoints([]);
    forceRender((n) => n + 1);
  }, [restartKey]);

  function isOnFloor(px: number, pz: number): boolean {
    for (let i = 0; i < floor.length; i++) {
      if (pointInTriangle(px, pz, floor[i])) return true;
    }
    return false;
  }

  useFrame((_state, delta) => {
    if (stateRef.current.finished || flatCorners.length < 2) return;
    let moveBudget = speed * delta;
    while (moveBudget > 0 && !stateRef.current.finished) {
      const i = stateRef.current.cornerIdx;
      if (i >= flatCorners.length - 1) {
        stateRef.current.finished = true;
        // Final leg(s) completion fire-through.
        for (let li = legsCompleted; li < legEndCornerIdx.length; li++) {
          onLegComplete?.(li);
        }
        setLegsCompleted(legEndCornerIdx.length);
        onComplete?.({ ok: true });
        break;
      }
      const a = flatCorners[i];
      const b = flatCorners[i + 1];
      const segLen = Math.hypot(b.x - a.x, b.z - a.z);
      const remaining = segLen - stateRef.current.segProgress;
      if (moveBudget >= remaining) {
        // Sample-step floor check along the consumed sub-segment.
        if (segLen > 0) {
          const startT = stateRef.current.segProgress / segLen;
          const endT = 1;
          const steps = Math.max(1, Math.ceil(remaining / sampleStep));
          for (let s = 1; s <= steps; s++) {
            const t = startT + ((endT - startT) * s) / steps;
            const sx = a.x + (b.x - a.x) * t;
            const sz = a.z + (b.z - a.z) * t;
            if (!isOnFloor(sx, sz)) {
              stateRef.current.failedAt = { x: sx, z: sz };
              stateRef.current.finished = true;
              if (meshRef.current) meshRef.current.position.set(sx, y, sz);
              // Figure out which leg this segment belonged to.
              let legIdx = 0;
              for (; legIdx < legEndCornerIdx.length; legIdx++) {
                if (legEndCornerIdx[legIdx] > i) break;
              }
              onComplete?.({ ok: false, failedAt: { x: sx, z: sz }, legIndex: legIdx });
              forceRender((n) => n + 1);
              return;
            }
          }
        }
        moveBudget -= remaining;
        stateRef.current.segProgress = 0;
        stateRef.current.cornerIdx += 1;
        if (meshRef.current) meshRef.current.position.set(b.x, y, b.z);
        setTrailPoints((pts) => [...pts, { x: b.x, z: b.z }]);
        // Did we just complete a leg boundary?
        const reachedCornerIdx = stateRef.current.cornerIdx;
        for (let li = 0; li < legEndCornerIdx.length; li++) {
          if (legEndCornerIdx[li] === reachedCornerIdx && li >= legsCompleted) {
            const fired = li + 1;
            setLegsCompleted(fired);
            onLegComplete?.(li);
            break;
          }
        }
        continue;
      }
      // Advance partway through current segment.
      if (segLen > 0) {
        const startT = stateRef.current.segProgress / segLen;
        const endProg = stateRef.current.segProgress + moveBudget;
        const endT = endProg / segLen;
        const steps = Math.max(1, Math.ceil(moveBudget / sampleStep));
        for (let s = 1; s <= steps; s++) {
          const t = startT + ((endT - startT) * s) / steps;
          const sx = a.x + (b.x - a.x) * t;
          const sz = a.z + (b.z - a.z) * t;
          if (!isOnFloor(sx, sz)) {
            stateRef.current.failedAt = { x: sx, z: sz };
            stateRef.current.finished = true;
            if (meshRef.current) meshRef.current.position.set(sx, y, sz);
            let legIdx = 0;
            for (; legIdx < legEndCornerIdx.length; legIdx++) {
              if (legEndCornerIdx[legIdx] > i) break;
            }
            onComplete?.({ ok: false, failedAt: { x: sx, z: sz }, legIndex: legIdx });
            forceRender((n) => n + 1);
            return;
          }
        }
        stateRef.current.segProgress += moveBudget;
        const lerpX = a.x + (b.x - a.x) * endT;
        const lerpZ = a.z + (b.z - a.z) * endT;
        if (meshRef.current) meshRef.current.position.set(lerpX, y, lerpZ);
      }
      moveBudget = 0;
    }
  });

  if (flatCorners.length < 2) return null;
  const failed = stateRef.current.failedAt;
  const fenceOpen = switchActivationLegIndex !== undefined && legsCompleted > switchActivationLegIndex;
  const firstCorner = flatCorners[0];

  return (
    <group>
      {/* Capsule (rendered as a sphere — easier to see at any angle). */}
      <mesh ref={meshRef} position={[firstCorner.x, y, firstCorner.z]}>
        <sphereGeometry args={[radius, 16, 12]} />
        <meshBasicMaterial color={failed ? '#ef4444' : '#22d3ee'} transparent opacity={0.85} />
      </mesh>
      {/* Failure marker (only after a fail). */}
      {failed && (
        <mesh position={[failed.x, y + 1.0, failed.z]}>
          <coneGeometry args={[0.4, 1.5, 6]} />
          <meshBasicMaterial color="#ef4444" />
        </mesh>
      )}
      {/* Trail dots — each reached corner gets a small marker so the user
          can see the path the capsule has taken so far. */}
      {trailPoints.map((p, i) => (
        <mesh key={i} position={[p.x, 0.1, p.z]}>
          <sphereGeometry args={[0.2, 8, 6]} />
          <meshBasicMaterial color="#22d3ee" />
        </mesh>
      ))}
      {/* Fences. Red box when closed (pre-switch); faded green when open
          (post-switch). Wide on XZ, ~2m tall so it's visible above floor. */}
      {fences.map((f, i) => {
        const half = f.halfWidth ?? 1.5;
        return (
          <mesh key={i} position={[f.x, 1.0, f.z]}>
            <boxGeometry args={[half * 2, 2.0, half * 2]} />
            <meshBasicMaterial
              color={fenceOpen ? '#22c55e' : '#ef4444'}
              transparent
              opacity={fenceOpen ? 0.25 : 0.65}
            />
          </mesh>
        );
      })}
    </group>
  );
}
