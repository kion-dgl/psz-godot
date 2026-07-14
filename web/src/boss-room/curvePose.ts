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
