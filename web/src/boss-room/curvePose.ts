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

export function makeSampler(points: Vec3Tuple[], rollDeg = 0): CurveSampler {
  if (points.length < 2) throw new Error('curve needs >= 2 control points');
  const curve = new THREE.CatmullRomCurve3(
    points.map((p) => new THREE.Vector3(...p)),
    false,
    'centripetal',
  );
  const length = curve.getLength();
  // Constant roll about the tube axis, applied on top of the twist-free
  // frame — which bone-local side is the sucker side is a modeling artifact
  // of the rig, so the data can turn it to face down (instances[].roll_deg).
  const qRoll = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), (rollDeg * Math.PI) / 180);
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
    // Twist-free tangent frame: bone +X along the tangent, bone +Y kept as
    // close to world up as possible. A minimal rotation (setFromUnitVectors)
    // rolls the tube on 3D arcs and between headings — the sucker side would
    // corkscrew along the arm and differ per tentacle. Building the basis
    // from a world-up reference pins the roll everywhere (near-vertical
    // tangents fall back to +Z as the reference).
    const upRef = Math.abs(tangent.y) > 0.99 ? new THREE.Vector3(0, 0, 1) : new THREE.Vector3(0, 1, 0);
    const side = new THREE.Vector3().crossVectors(tangent, upRef).normalize();
    const up = new THREE.Vector3().crossVectors(side, tangent);
    const quat = new THREE.Quaternion()
      .setFromRotationMatrix(new THREE.Matrix4().makeBasis(tangent, up, side))
      .multiply(qRoll); // the lateral offsets (tip prongs) roll with the tube
    if (lateral[0] !== 0 || lateral[1] !== 0) {
      pos.add(new THREE.Vector3(0, lateral[0], lateral[1]).applyQuaternion(quat));
    }
    return { pos, quat };
  };
  return { length, poseAt };
}

/** Static pose for each rest bone along the authored curve (order preserved). */
export function poseBonesAlongCurve(rest: RestBone[], points: Vec3Tuple[], rollDeg = 0): BonePose[] {
  const sampler = makeSampler(points, rollDeg);
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
/** Default start depth: the emergence point sits this far below the clicked surface (the tentacles start in the water). */
export const DEFAULT_DIP = 2;

const apexBetween = (b: Vec3Tuple, t: Vec3Tuple, lift: number): Vec3Tuple => [
  (b[0] + t[0]) / 2,
  Math.max(b[1], t[1]) + lift,
  (b[2] + t[2]) / 2,
];

/**
 * Emergence → apex → tip arch at a clicked point. The emergence (base)
 * sits `dip` BELOW the click — the tentacles start in the water, and the
 * click lands on the water surface. The tip runs `reach` units along
 * `outward` (default: away from the boss origin through the click;
 * straight +z when the click is at the origin) at the click's height,
 * the apex halfway, `lift` above the higher end.
 */
export function defaultArch(
  click: Vec3Tuple,
  outward?: [number, number],
  reach = DEFAULT_REACH,
  lift = DEFAULT_LIFT,
  dip = 0,
): Vec3Tuple[] {
  let [dx, dz] = outward ?? [click[0], click[2]];
  const len = Math.hypot(dx, dz);
  if (len < 1e-3) {
    dx = 0;
    dz = 1;
  } else {
    dx /= len;
    dz /= len;
  }
  const base: Vec3Tuple = [click[0], click[1] - dip, click[2]];
  const tip: Vec3Tuple = [click[0] + dx * reach, click[1], click[2] + dz * reach];
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

/** The start depth read out of a curve: how far the emergence sits below the tip end. */
export function curveDip(pts: Vec3Tuple[]): number {
  return pts[pts.length - 1][1] - pts[0][1];
}

/** Set the start depth: sink/raise the emergence point relative to the tip end. */
export function setDip(pts: Vec3Tuple[], dip: number): Vec3Tuple[] {
  const base: Vec3Tuple = [pts[0][0], pts[pts.length - 1][1] - dip, pts[0][2]];
  return [base, ...pts.slice(1)];
}

/** Set the lift: shift every interior point's y so the apex sits `lift` above the ends. */
export function setLift(pts: Vec3Tuple[], lift: number): Vec3Tuple[] {
  if (pts.length < 3) return pts;
  const dy = lift - curveLift(pts);
  return pts.map((p, i) => (i === 0 || i === pts.length - 1 ? p : ([p[0], p[1] + dy, p[2]] as Vec3Tuple)));
}
