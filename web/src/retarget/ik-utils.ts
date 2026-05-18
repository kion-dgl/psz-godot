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

/** Rotate `bone` so its local "child rest direction" points at
 *  `targetWorld` in world space. childRestLocal is the unit vector
 *  in the bone's own local frame that points toward its child at
 *  rest (typically `child.position.clone().normalize()`). Uses
 *  setFromUnitVectors, which gives shortest-path rotation — twist
 *  around the bone axis is unspecified and must be corrected
 *  separately if needed (see swingTwistDecomposition + a rotation-
 *  copy blend). */
export function aimBoneAtTarget(
  bone: THREE.Bone,
  targetWorld: THREE.Vector3,
  childRestLocal: THREE.Vector3,
): void {
  if (!bone.parent) return;
  bone.parent.updateMatrixWorld(true);
  const parentInv = new THREE.Matrix4().copy(bone.parent.matrixWorld).invert();
  const targetInParent = targetWorld.clone().applyMatrix4(parentInv);
  const localDir = targetInParent.sub(bone.position).normalize();
  bone.quaternion.setFromUnitVectors(childRestLocal, localDir);
  bone.updateMatrixWorld(true);
}

/** Direction-driven 2-bone chain retarget. Aims each VRM bone so its
 *  child lands at VRM-rest-length away in PSO's parent→child
 *  direction (world space). Replaces analytic-IK-with-fixed-pole:
 *  the elbow/knee goes exactly where PSO has it, not where the pole
 *  bias guesses. Validated to <0.000002° per-bone aim error across
 *  all 572 PSO clips at 60 samples/clip (web/scripts/validate-pso-
 *  vrm-ik.mjs). Twist around the bone axis still needs a separate
 *  rotation-copy blend — this only fixes swing. */
export function retargetChainByDirection(
  vrmUpper: THREE.Bone,
  vrmLower: THREE.Bone,
  psoUpper: THREE.Object3D,
  psoLower: THREE.Object3D,
  psoEnd: THREE.Object3D,
  vrmUpperLen: number,
  vrmLowerLen: number,
  upperChildRestLocal: THREE.Vector3,
  lowerChildRestLocal: THREE.Vector3,
): void {
  const pU = new THREE.Vector3(); psoUpper.getWorldPosition(pU);
  const pL = new THREE.Vector3(); psoLower.getWorldPosition(pL);
  const pE = new THREE.Vector3(); psoEnd.getWorldPosition(pE);

  // Aim upper bone at where elbow should land: VRM-upper-length away
  // from VRM shoulder, in PSO's shoulder→elbow direction (world).
  const upperDir = new THREE.Vector3().subVectors(pL, pU);
  if (upperDir.lengthSq() < 1e-12) return;
  upperDir.normalize();
  const vSw = new THREE.Vector3(); vrmUpper.getWorldPosition(vSw);
  const elbowTarget = upperDir.multiplyScalar(vrmUpperLen).add(vSw);
  aimBoneAtTarget(vrmUpper, elbowTarget, upperChildRestLocal);

  // After upper rotates, lower's world position has shifted. Re-read,
  // then aim lower at the hand target (VRM-lower-length from elbow,
  // in PSO's elbow→hand direction).
  vrmLower.updateMatrixWorld(true);
  const vEw = new THREE.Vector3(); vrmLower.getWorldPosition(vEw);
  const lowerDir = new THREE.Vector3().subVectors(pE, pL);
  if (lowerDir.lengthSq() < 1e-12) return;
  lowerDir.normalize();
  const handTarget = lowerDir.multiplyScalar(vrmLowerLen).add(vEw);
  aimBoneAtTarget(vrmLower, handTarget, lowerChildRestLocal);
}

/** Joint constraint for hinge joints (elbow, knee). The direction-
 *  driven retarget reproduces PSO's bone directions exactly — but
 *  PSO source data occasionally has anatomically impossible poses
 *  (elbow hyperextended past straight, knee bent forward instead of
 *  back). This snaps the lower bone back to a natural bend when
 *  that happens, leaving the bend magnitude intact but flipping the
 *  bend direction so it goes the way the joint actually works.
 *
 *  `bodyForward` is the world-space direction the character faces
 *  (typically +Z for VRoid VRMs). `bendSign` is +1 for joints that
 *  bend toward body-forward (arms — forearm comes forward to touch
 *  the chest), -1 for joints that bend away (legs — calf goes back
 *  toward the butt).
 *
 *  Returns true if the constraint actually fired (useful for
 *  counting how often the source is anatomically weird). */
export interface HingeJointConstraint {
  bodyForward: THREE.Vector3;
  bendSign: number;
}

export function enforceNaturalBend(
  vrmUpper: THREE.Bone,
  vrmLower: THREE.Bone,
  vrmLowerEndChild: THREE.Object3D,
  lowerChildRestLocal: THREE.Vector3,
  vrmLowerLen: number,
  constraint: HingeJointConstraint,
): boolean {
  const upperW = new THREE.Vector3(); vrmUpper.getWorldPosition(upperW);
  const lowerW = new THREE.Vector3(); vrmLower.getWorldPosition(lowerW);
  const endW = new THREE.Vector3(); vrmLowerEndChild.getWorldPosition(endW);

  const upperDir = lowerW.clone().sub(upperW);
  if (upperDir.lengthSq() < 1e-12) return false;
  upperDir.normalize();
  const lowerDir = endW.clone().sub(lowerW);
  if (lowerDir.lengthSq() < 1e-12) return false;
  lowerDir.normalize();

  // Natural bend axis = cross(upper, bendDir). For arms (bendSign=+1)
  // this picks the axis the elbow naturally hinges around as the
  // forearm comes forward; for legs (bendSign=-1) the axis the knee
  // hinges around as the calf goes back.
  const bendDir = constraint.bodyForward.clone().multiplyScalar(constraint.bendSign);
  const naturalBendAxis = new THREE.Vector3().crossVectors(upperDir, bendDir);
  if (naturalBendAxis.lengthSq() < 1e-6) return false;
  naturalBendAxis.normalize();

  // Actual bend axis = cross(upper, lower). If it points in the
  // OPPOSITE direction from the natural axis, the joint is bending
  // the wrong way (hyperextension).
  const actualBendAxis = new THREE.Vector3().crossVectors(upperDir, lowerDir);
  if (actualBendAxis.dot(naturalBendAxis) >= 0) return false;

  // Reflect lower direction across the plane spanned by upperDir and
  // bendDir. naturalBendAxis is the plane's normal, so the reflection
  // is `lower - 2 * (lower · n) * n`.
  const reflected = lowerDir.clone().sub(
    naturalBendAxis.multiplyScalar(2 * lowerDir.dot(naturalBendAxis)),
  );
  const newTarget = reflected.multiplyScalar(vrmLowerLen).add(lowerW);
  aimBoneAtTarget(vrmLower, newTarget, lowerChildRestLocal);
  return true;
}

/** Swing-twist decomposition. Splits a quaternion into the rotation
 *  around `axis` (twist — e.g. forearm roll for palm-up vs palm-down)
 *  and everything else (swing — bone bend / aim). Used by the hybrid
 *  retargeter: IK gives us the right swing (elbow points toward
 *  wrist), but its twist is whatever setFromUnitVectors happened to
 *  pick. We restore the source animation's twist by extracting it
 *  from the rotation-copy result and re-attaching to the IK swing.
 *
 *  `axis` must be a unit vector in the bone's local frame, pointing
 *  along the bone's length (toward its child in rest pose). */
export function swingTwistDecomposition(
  q: THREE.Quaternion,
  axis: THREE.Vector3,
): { swing: THREE.Quaternion; twist: THREE.Quaternion } {
  // Project q's vector part onto axis → twist's vector part.
  const dot = q.x * axis.x + q.y * axis.y + q.z * axis.z;
  const px = axis.x * dot;
  const py = axis.y * dot;
  const pz = axis.z * dot;
  let twist = new THREE.Quaternion(px, py, pz, q.w);
  const lenSq = twist.x * twist.x + twist.y * twist.y + twist.z * twist.z + twist.w * twist.w;
  if (lenSq < 1e-12) {
    // q is a pure swing (180° around an axis perp to `axis`). Twist = identity.
    twist = new THREE.Quaternion();
  } else {
    twist.normalize();
  }
  // swing = q * inv(twist)
  const swing = q.clone().multiply(twist.clone().invert());
  return { swing, twist };
}

