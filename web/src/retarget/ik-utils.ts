import * as THREE from 'three';

// Analytic 2-bone inverse-kinematics. The motivation here is a different
// trade-off than buildRetargetedClip (rotation-copy retargeting): when the
// source (PSO) and target (VRM) skeletons disagree on rest pose — arms-
// down vs. T-pose — copying rotations frame-by-frame leaves the target
// looking subtly wrong even after the F-correction step. IK sidesteps that
// by treating the source's joint positions as targets and letting the
// target's natural rest pose stand: the VRM shoulder bends however its rig
// wants, just so the hand ends up where PSO's hand is.
//
// The downside is well-known: position alone doesn't pin twist around the
// bone axis. For forearms that's usually fine (the wrist constraint pins
// the lower-arm direction), but for upper arms / upper legs an explicit
// pole-vector hint is needed to keep the elbow / knee from popping.

/** World-space chain measurements taken from the rest pose of a target
 *  rig. Captured once at load time, reused every frame the IK runs. */
export interface ChainRest {
  upperLength: number;
  lowerLength: number;
  /** Local-space unit vector inside the upper bone that points at the
   *  middle joint (elbow / knee) in rest pose. Used to convert the
   *  IK-computed world direction into a local quaternion via
   *  setFromUnitVectors. */
  upperChildRestLocal: THREE.Vector3;
  /** Same idea for the lower bone, pointing at the end effector. */
  lowerChildRestLocal: THREE.Vector3;
}

export function measureChain(
  upperBone: THREE.Bone,
  lowerBone: THREE.Bone,
  endEffector: THREE.Bone,
): ChainRest {
  // Compute lengths in world space (rest pose) so they're independent of
  // any local scale on the bones themselves.
  const upperWorld = new THREE.Vector3();
  const lowerWorld = new THREE.Vector3();
  const endWorld = new THREE.Vector3();
  upperBone.getWorldPosition(upperWorld);
  lowerBone.getWorldPosition(lowerWorld);
  endEffector.getWorldPosition(endWorld);

  const upperLength = upperWorld.distanceTo(lowerWorld);
  const lowerLength = lowerWorld.distanceTo(endWorld);

  // The "rest forward" direction for each bone is the direction it
  // points at its child in rest pose, expressed in the bone's local
  // frame. For a typical rig the upper-arm's child is at its +Y or
  // -Y, but we don't want to hardcode that — derive it.
  const upperChildRestLocal = lowerBone.position.clone().normalize();
  const lowerChildRestLocal = endEffector.position.clone().normalize();

  return { upperLength, lowerLength, upperChildRestLocal, lowerChildRestLocal };
}

/** Solve a 2-bone chain so the end-effector reaches `targetWorld`, with
 *  the middle joint biased toward `poleWorld`. Sets bone.quaternion on
 *  `upperBone` and `lowerBone` in-place. Caller is expected to call
 *  updateMatrixWorld on the rig after all chains are solved (or per
 *  chain — both work, with a small perf cost). */
export function solveTwoBoneIK(
  upperBone: THREE.Bone,
  lowerBone: THREE.Bone,
  targetWorld: THREE.Vector3,
  poleWorld: THREE.Vector3,
  rest: ChainRest,
): void {
  if (!upperBone.parent || !lowerBone.parent) return;

  // Make sure parent transforms are current before we read shoulder pos.
  upperBone.parent.updateMatrixWorld(true);

  const shoulderWorld = new THREE.Vector3();
  upperBone.getWorldPosition(shoulderWorld);

  const { upperLength, lowerLength, upperChildRestLocal, lowerChildRestLocal } = rest;
  const totalReach = upperLength + lowerLength;
  const minReach = Math.abs(upperLength - lowerLength);

  // If the target is out of reach, clamp it onto the sphere of max
  // reach — leaves the chain fully extended toward the original target
  // rather than the elbow-locked snap that an unclamped solve produces.
  let dist = targetWorld.distanceTo(shoulderWorld);
  const dirToTarget = new THREE.Vector3().subVectors(targetWorld, shoulderWorld);
  if (dist < 1e-6) {
    // Degenerate: target coincides with shoulder. Keep current pose.
    return;
  }
  dirToTarget.divideScalar(dist);
  const reachedTarget =
    dist > totalReach - 1e-4
      ? new THREE.Vector3().copy(shoulderWorld).addScaledVector(dirToTarget, totalReach - 1e-4)
      : targetWorld.clone();
  dist = Math.max(minReach + 1e-4, Math.min(totalReach - 1e-4, dist));

  // Law of cosines → elbow offset along/perpendicular to shoulder-target line.
  const a = (upperLength * upperLength - lowerLength * lowerLength + dist * dist) / (2 * dist);
  const h = Math.sqrt(Math.max(0, upperLength * upperLength - a * a));

  // Project pole hint onto the plane perpendicular to shoulder→target.
  // That perpendicular direction is where the elbow lives.
  const poleRel = new THREE.Vector3().subVectors(poleWorld, shoulderWorld);
  const polePerp = poleRel.sub(dirToTarget.clone().multiplyScalar(poleRel.dot(dirToTarget)));
  if (polePerp.lengthSq() < 1e-6) {
    // Pole hint sits on the shoulder-target axis — fall back to a
    // generic side direction so the elbow doesn't NaN.
    polePerp.set(0, 0, 1);
  }
  polePerp.normalize();

  const elbowWorld = new THREE.Vector3()
    .copy(shoulderWorld)
    .addScaledVector(dirToTarget, a)
    .addScaledVector(polePerp, h);

  // Aim the upper bone at the elbow position. We need the elbow
  // expressed in the upper bone's parent-local space (so the rotation
  // is correct relative to whatever the spine is doing this frame),
  // then take the direction from upper-bone's local origin.
  const parentInvUpper = new THREE.Matrix4().copy(upperBone.parent.matrixWorld).invert();
  const elbowInUpperParent = elbowWorld.clone().applyMatrix4(parentInvUpper);
  const upperLocalDir = elbowInUpperParent.sub(upperBone.position).normalize();
  upperBone.quaternion.setFromUnitVectors(upperChildRestLocal, upperLocalDir);
  upperBone.updateMatrixWorld(true);

  // Now aim the lower bone at the actual target (the clamped one) in
  // the lower bone's parent-local space. Since lowerBone.parent is the
  // upper bone, this naturally uses the newly-set upper orientation.
  const parentInvLower = new THREE.Matrix4().copy(lowerBone.parent.matrixWorld).invert();
  const targetInLowerParent = reachedTarget.clone().applyMatrix4(parentInvLower);
  const lowerLocalDir = targetInLowerParent.sub(lowerBone.position).normalize();
  lowerBone.quaternion.setFromUnitVectors(lowerChildRestLocal, lowerLocalDir);
  lowerBone.updateMatrixWorld(true);
}
