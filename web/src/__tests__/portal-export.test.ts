/**
 * Unit tests for computePortalPositions logic from quest-io.ts
 *
 * We replicate the pure function here since it's not exported and depends on
 * module-level constants. This keeps tests independent of browser/fetch code.
 */
import { describe, it, expect } from 'vitest';

// --- Replicated from quest-io.ts (pure math, no imports) ---

type Vec3 = [number, number, number];

const DIRECTION_ROTATIONS: Record<string, number> = {
  north: 0,
  south: Math.PI,
  east: Math.PI / 2,
  west: -Math.PI / 2,
};

const GATE_MODEL_ROTATIONS: Record<string, number> = {
  north: 0,
  south: Math.PI,
  east: -Math.PI / 2,
  west: Math.PI / 2,
};

const CONFIG_DIR_TO_COMPASS: Record<string, string> = {
  north: 'N',
  south: 'S',
  east: 'E',
  west: 'W',
};

interface PortalConfig {
  id?: string;
  direction: string;
  position: Vec3;
  compass_label?: string;
  rotationOffset?: number;
}

function round3(v: Vec3): Vec3 {
  return [+v[0].toFixed(2), +v[1].toFixed(2), +v[2].toFixed(2)];
}

function getPortalRotation(portal: PortalConfig): number {
  return (DIRECTION_ROTATIONS[portal.direction] ?? 0) + ((portal.rotationOffset || 0) * Math.PI) / 180;
}

function computePortalPositions(portal: PortalConfig) {
  const [x, , z] = portal.position;
  const rotation = getPortalRotation(portal);
  const spawnOutset = 3;
  const triggerOutset = 7;
  const cos = Math.cos(rotation);
  const sin = Math.sin(rotation);
  const gateYRot = GATE_MODEL_ROTATIONS[portal.direction] ?? 0;
  const compassLabel = portal.compass_label ?? CONFIG_DIR_TO_COMPASS[portal.direction] ?? portal.direction[0].toUpperCase();

  return {
    gate: round3(portal.position),
    spawn: round3([x - sin * spawnOutset, 1, z - cos * spawnOutset]),
    trigger: round3([x - sin * triggerOutset, 0, z - cos * triggerOutset]),
    gate_rot: round3([0, gateYRot, 0]),
    compass_label: compassLabel,
  };
}

// --- Tests ---

// After round3, Math.PI becomes 3.14, Math.PI/2 becomes 1.57, etc.
const CARDINAL_Y_ROTS_ROUNDED = [0, +Math.PI.toFixed(2), +(Math.PI / 2).toFixed(2), +(-Math.PI / 2).toFixed(2)];

function isCardinalYRot(y: number): boolean {
  return CARDINAL_Y_ROTS_ROUNDED.some(v => Math.abs(y - v) < 0.01);
}

describe('computePortalPositions', () => {
  const testPortals: PortalConfig[] = [
    { id: 'p1', direction: 'north', position: [5, 0, -20] },
    { id: 'p2', direction: 'south', position: [-3, 0, 15] },
    { id: 'p3', direction: 'east', position: [18, 0, 2] },
    { id: 'p4', direction: 'west', position: [-18, 0, -5] },
  ];

  it.each(testPortals)('gate/spawn/trigger are collinear ($direction)', (portal) => {
    const result = computePortalPositions(portal);
    const { gate, spawn, trigger } = result;

    // All three points should share the same axis alignment:
    // Either X is constant (north/south portals) or Z is constant (east/west portals)
    const dx_gs = Math.abs(gate[0] - spawn[0]);
    const dz_gs = Math.abs(gate[2] - spawn[2]);
    const dx_gt = Math.abs(gate[0] - trigger[0]);
    const dz_gt = Math.abs(gate[2] - trigger[2]);

    // One axis should be ~constant (< 0.01 difference)
    const xConstant = dx_gs < 0.01 && dx_gt < 0.01;
    const zConstant = dz_gs < 0.01 && dz_gt < 0.01;
    expect(xConstant || zConstant, `Not collinear: gate=${gate}, spawn=${spawn}, trigger=${trigger}`).toBe(true);
  });

  it.each(testPortals)('spawn is between gate and trigger ($direction)', (portal) => {
    const result = computePortalPositions(portal);
    const { gate, spawn, trigger } = result;

    // spawn distance from gate should be less than trigger distance from gate
    const distSpawn = Math.hypot(spawn[0] - gate[0], spawn[2] - gate[2]);
    const distTrigger = Math.hypot(trigger[0] - gate[0], trigger[2] - gate[2]);
    expect(distSpawn).toBeLessThan(distTrigger);
  });

  it.each(testPortals)('gate_rot is a cardinal Y rotation ($direction)', (portal) => {
    const result = computePortalPositions(portal);
    const yRot = result.gate_rot[1];
    expect(isCardinalYRot(yRot), `gate_rot Y=${yRot} is not cardinal`).toBe(true);
    // X and Z rotation should be 0
    expect(result.gate_rot[0]).toBe(0);
    expect(result.gate_rot[2]).toBe(0);
  });

  it('compass_label uses config compass_label when set', () => {
    const portal: PortalConfig = { id: 'cl1', direction: 'north', position: [0, 0, -10], compass_label: 'W' };
    const result = computePortalPositions(portal);
    expect(result.compass_label).toBe('W');
  });

  it('compass_label falls back to direction mapping', () => {
    const portal: PortalConfig = { id: 'cl2', direction: 'east', position: [10, 0, 0] };
    const result = computePortalPositions(portal);
    expect(result.compass_label).toBe('E');
  });

  it.each(['north', 'south', 'east', 'west'])('direction %s produces correct default compass_label', (dir) => {
    const portal: PortalConfig = { id: 'dl', direction: dir, position: [5, 0, 5] };
    const result = computePortalPositions(portal);
    expect(result.compass_label).toBe(CONFIG_DIR_TO_COMPASS[dir]);
  });
});
