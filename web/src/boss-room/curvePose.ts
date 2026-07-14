/**
 * Tentacle spline-poser math (#508, spec /states/bosses parts contract).
 *
 * The tentacle rigs are flat sibling bones under a root, spaced along local
 * +X (z_002_tt: 8 bones; z_002_st: 10, where the 2 extras are tip prongs at
 * the same arc offset with lateral z). Clips pose the bones absolutely, so
 * no IK is needed: a Catmull-Rom through the authored control points,
 * arc-length sampled at each bone's rest offset, IS the pose.
 *
 * Everything here is frame-agnostic pure math: control points in, per-bone
 * {pos, quat} out, in the same frame the points were given (the boss's local
 * frame, +z = facing). BossRoom converts to bone-parent locals.
 */
import * as THREE from 'three';

export type Vec3Tuple = [number, number, number];

/** Per-bone rest layout read off the rig: arc offset (rest x) + lateral (rest y, z). */
export interface RestBone {
  arc: number;
  lateral: [number, number];
}

export interface BonePose {
  pos: THREE.Vector3;
  quat: THREE.Quaternion;
}

const X_AXIS = new THREE.Vector3(1, 0, 0);

/**
 * Reusable arc-length sampler over the authored control points. Cache one
 * per curve edit — the clip-overlay path samples it every frame.
 */
export interface CurveSampler {
  length: number;
  /**
   * Pose at arc distance `arc` with a lateral offset applied in the tangent
   * frame. Outside [0, length] the pose extrapolates straight along the end
   * (resp. start) tangent — per the spec, the tube never stretches or bunches
   * when the authored curve is shorter than the rig.
   */
  poseAt(arc: number, lateral?: [number, number]): BonePose;
}

export function makeSampler(points: Vec3Tuple[]): CurveSampler {
  if (points.length < 2) throw new Error('curve needs >= 2 control points');
  const curve = new THREE.CatmullRomCurve3(
    points.map((p) => new THREE.Vector3(...p)),
    false,
    'centripetal',
  );
  const length = curve.getLength();
  const poseAt = (arc: number, lateral: [number, number] = [0, 0]): BonePose => {
    const pos = new THREE.Vector3();
    const tangent = new THREE.Vector3();
    if (arc <= 0) {
      tangent.copy(curve.getTangentAt(0));
      pos.copy(curve.getPointAt(0)).addScaledVector(tangent, arc);
    } else if (arc >= length) {
      tangent.copy(curve.getTangentAt(1));
      pos.copy(curve.getPointAt(1)).addScaledVector(tangent, arc - length);
    } else {
      const u = arc / length;
      tangent.copy(curve.getTangentAt(u));
      pos.copy(curve.getPointAt(u));
    }
    // Minimal rotation taking the rig's rest tube axis (+X) to the tangent.
    // Twist about the tube axis is not controlled — the tube is round.
    const quat = new THREE.Quaternion().setFromUnitVectors(X_AXIS, tangent);
    if (lateral[0] !== 0 || lateral[1] !== 0) {
      pos.add(new THREE.Vector3(0, lateral[0], lateral[1]).applyQuaternion(quat));
    }
    return { pos, quat };
  };
  return { length, poseAt };
}

/** Static pose for each rest bone along the authored curve (order preserved). */
export function poseBonesAlongCurve(rest: RestBone[], points: Vec3Tuple[]): BonePose[] {
  const sampler = makeSampler(points);
  return rest.map((b) => sampler.poseAt(b.arc, b.lateral));
}

// ——— parametric authoring (place → bend) ———
//
// The room's primary flow: click the ground to PLACE a tentacle (a default
// emergence → apex → tip arch is generated at the click), then BEND it —
// click a tip target, drag the lift slider, or fine-tune the rows. All pure
// curve edits; the sampler above turns the result into the pose.

/** Default horizontal reach of a placed arch — sized to the ~20u tentacle rigs. */
export const DEFAULT_REACH = 14;
/** Default apex lift of a placed arch. */
export const DEFAULT_LIFT = 5;

const apexBetween = (b: Vec3Tuple, t: Vec3Tuple, lift: number): Vec3Tuple => [
  (b[0] + t[0]) / 2,
  Math.max(b[1], t[1]) + lift,
  (b[2] + t[2]) / 2,
];

/**
 * Emergence → apex → tip arch at a clicked base. The tip runs `reach` units
 * along `outward` (default: away from the boss origin through the base;
 * straight +z when the base is at the origin), the apex halfway, `lift`
 * above the higher end.
 */
export function defaultArch(
  base: Vec3Tuple,
  outward?: [number, number],
  reach = DEFAULT_REACH,
  lift = DEFAULT_LIFT,
): Vec3Tuple[] {
  let [dx, dz] = outward ?? [base[0], base[2]];
  const len = Math.hypot(dx, dz);
  if (len < 1e-3) {
    dx = 0;
    dz = 1;
  } else {
    dx /= len;
    dz /= len;
  }
  const tip: Vec3Tuple = [base[0] + dx * reach, base[1], base[2] + dz * reach];
  return [base, apexBetween(base, tip, lift), tip];
}

/** Move the whole curve so it starts at newBase — the authored bend is preserved. */
export function translateCurve(pts: Vec3Tuple[], newBase: Vec3Tuple): Vec3Tuple[] {
  const d = [newBase[0] - pts[0][0], newBase[1] - pts[0][1], newBase[2] - pts[0][2]];
  return pts.map((p) => [p[0] + d[0], p[1] + d[1], p[2] + d[2]] as Vec3Tuple);
}

/** The arch lift read out of a curve: apex (highest interior y) above the higher end. */
export function curveLift(pts: Vec3Tuple[]): number {
  if (pts.length < 3) return 0;
  const apexY = Math.max(...pts.slice(1, -1).map((p) => p[1]));
  return apexY - Math.max(pts[0][1], pts[pts.length - 1][1]);
}

/**
 * Re-aim the bend: keep the base, set the tip, rebuild as a 3-point arch at
 * the curve's current lift (a freshly placed arch keeps DEFAULT_LIFT).
 */
export function retargetTip(pts: Vec3Tuple[], tip: Vec3Tuple): Vec3Tuple[] {
  const base = pts[0];
  return [base, apexBetween(base, tip, curveLift(pts)), tip];
}

/** Set the lift: shift every interior point's y so the apex sits `lift` above the ends. */
export function setLift(pts: Vec3Tuple[], lift: number): Vec3Tuple[] {
  if (pts.length < 3) return pts;
  const dy = lift - curveLift(pts);
  return pts.map((p, i) => (i === 0 || i === pts.length - 1 ? p : ([p[0], p[1] + dy, p[2]] as Vec3Tuple)));
}
