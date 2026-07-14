/**
 * Tentacle spline-poser math (#508) — pins the spec /states/bosses parts
 * contract: arc-length sampling at rest bone offsets, straight extrapolation
 * past the curve's end (no stretch/bunch), lateral offsets in the tangent
 * frame, bone +X aligned to the tangent.
 */
import { describe, it, expect } from 'vitest';
import * as THREE from 'three';
import {
  DEFAULT_LIFT,
  DEFAULT_REACH,
  curveLift,
  defaultArch,
  makeSampler,
  poseBonesAlongCurve,
  retargetTip,
  setLift,
  translateCurve,
  type RestBone,
  type Vec3Tuple,
} from '../boss-room/curvePose';

// The real z_002_tt layout read off the GLB: root at 0, siblings ~2.5u apart.
const TT_REST: RestBone[] = [0, 4.98, 7.48, 9.99, 12.48, 14.99, 17.47, 19.96].map((arc) => ({
  arc,
  lateral: [0, 0],
}));

const X = new THREE.Vector3(1, 0, 0);

describe('curvePose — straight line', () => {
  // A straight run along +Z, longer than the rig (rig spans ~20u).
  const line: Vec3Tuple[] = [
    [0, 0, 0],
    [0, 0, 12],
    [0, 0, 25],
  ];

  it('places each bone at its rest arc offset along the line', () => {
    const poses = poseBonesAlongCurve(TT_REST, line);
    poses.forEach((p, i) => {
      expect(p.pos.x).toBeCloseTo(0, 3);
      expect(p.pos.y).toBeCloseTo(0, 3);
      expect(p.pos.z).toBeCloseTo(TT_REST[i].arc, 2);
    });
  });

  it('aligns bone +X to the tangent', () => {
    const poses = poseBonesAlongCurve(TT_REST, line);
    for (const p of poses) {
      const dir = X.clone().applyQuaternion(p.quat);
      expect(dir.z).toBeCloseTo(1, 4);
    }
  });

  it('extrapolates straight past the end without bunching', () => {
    const short: Vec3Tuple[] = [
      [0, 0, 0],
      [0, 0, 10],
    ];
    const s = makeSampler(short);
    const past = s.poseAt(15);
    expect(past.pos.z).toBeCloseTo(15, 3);
    const before = s.poseAt(-2);
    expect(before.pos.z).toBeCloseTo(-2, 3);
  });
});

describe('curvePose — lateral offsets (tip prongs)', () => {
  it('applies the lateral offset perpendicular to the tangent, magnitude preserved', () => {
    // A bend, so the tangent frame actually rotates.
    const bend: Vec3Tuple[] = [
      [0, 0, 0],
      [0, 2, 8],
      [0, 6, 14],
      [0, 12, 16],
    ];
    const s = makeSampler(bend);
    // z_002_st prongs: same arc, lateral z = +0.67 / -0.35.
    for (const lateral of [[0, 0.67] as [number, number], [0, -0.35] as [number, number]]) {
      const spine = s.poseAt(10);
      const prong = s.poseAt(10, lateral);
      const offset = prong.pos.clone().sub(spine.pos);
      expect(offset.length()).toBeCloseTo(Math.hypot(...lateral), 4);
      const tangent = X.clone().applyQuaternion(spine.quat);
      expect(Math.abs(offset.dot(tangent))).toBeLessThan(1e-4);
    }
  });
});

describe('curvePose — bone spacing on a bend', () => {
  it('keeps consecutive bones ~rest spacing apart (arc-length parameterization)', () => {
    // Emergence → apex → tip target, the poser's authoring shape.
    const arc: Vec3Tuple[] = [
      [0, -3, 0],
      [0, 2, 6],
      [0, 5, 12],
      [0, 3, 18],
    ];
    const poses = poseBonesAlongCurve(TT_REST, arc);
    for (let i = 1; i < poses.length; i++) {
      const gap = poses[i].pos.distanceTo(poses[i - 1].pos);
      const restGap = TT_REST[i].arc - TT_REST[i - 1].arc;
      // Chord ≤ arc always; a gentle authored bend should stay within ~10%.
      expect(gap).toBeLessThanOrEqual(restGap + 1e-3);
      expect(gap).toBeGreaterThan(restGap * 0.9);
    }
  });

  it('rejects fewer than 2 control points', () => {
    expect(() => makeSampler([[0, 0, 0]])).toThrow();
  });
});

describe('curvePose — parametric authoring (place → bend)', () => {
  it('defaultArch arcs outward from the boss origin through the base', () => {
    const arch = defaultArch([6, -0.8, 8]);
    expect(arch).toHaveLength(3);
    expect(arch[0]).toEqual([6, -0.8, 8]);
    // tip = base + outward(normalize(6,8)) * reach
    expect(arch[2][0]).toBeCloseTo(6 + 0.6 * DEFAULT_REACH, 4);
    expect(arch[2][2]).toBeCloseTo(8 + 0.8 * DEFAULT_REACH, 4);
    expect(arch[2][1]).toBeCloseTo(-0.8, 4);
    // apex halfway, lifted above the higher end
    expect(arch[1][0]).toBeCloseTo((arch[0][0] + arch[2][0]) / 2, 4);
    expect(arch[1][1]).toBeCloseTo(-0.8 + DEFAULT_LIFT, 4);
  });

  it('defaultArch at the origin falls back to +z (facing)', () => {
    const arch = defaultArch([0, 0, 0]);
    expect(arch[2]).toEqual([0, 0, DEFAULT_REACH]);
  });

  it('translateCurve moves the curve to a new base, bend preserved', () => {
    const arch = defaultArch([6, 0, 8]);
    const moved = translateCurve(arch, [-3, -1, 4]);
    expect(moved[0]).toEqual([-3, -1, 4]);
    for (let i = 1; i < arch.length; i++) {
      for (let a = 0; a < 3; a++) {
        expect(moved[i][a] - moved[0][a]).toBeCloseTo(arch[i][a] - arch[0][a], 6);
      }
    }
  });

  it('retargetTip keeps the base and lift, re-aims the tip', () => {
    const arch = defaultArch([6, 0, 8]);
    const bent = retargetTip(arch, [0, 0, 20]);
    expect(bent[0]).toEqual(arch[0]);
    expect(bent[2]).toEqual([0, 0, 20]);
    expect(curveLift(bent)).toBeCloseTo(curveLift(arch), 4);
  });

  it('setLift shifts interior points to the target lift; ends stay put', () => {
    const arch = defaultArch([6, 0, 8]);
    const lifted = setLift(arch, 9);
    expect(curveLift(lifted)).toBeCloseTo(9, 4);
    expect(lifted[0]).toEqual(arch[0]);
    expect(lifted[2]).toEqual(arch[2]);
    const flat = setLift(lifted, 0);
    expect(curveLift(flat)).toBeCloseTo(0, 4);
    // 2-point curves have no interior to lift
    expect(setLift([[0, 0, 0], [0, 0, 5]], 4)).toEqual([[0, 0, 0], [0, 0, 5]]);
  });
});
