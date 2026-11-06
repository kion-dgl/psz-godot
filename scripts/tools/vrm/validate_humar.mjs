// Independent glTF validator + real three-vrm parser. No browser/GPU required.
// Texture decoding is stubbed only in the Node parser; the embedded PNG is
// separately checked here and visually verified in the Godot comparison.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { VRMLoaderPlugin } from '@pixiv/three-vrm';
import validator from 'gltf-validator';

const root = fileURLToPath(new URL('../../../assets/player/', import.meta.url));
const paths = process.argv.includes('--all')
  ? Array.from({length: 56}, (_, i) => { const id = `pc_${String(Math.floor(i / 4)).padStart(2, '0')}${i % 4}`; return `${root}${id}/${id}.vrm`; })
  : [`${root}pc_000/pc_000.vrm`];
for (const path of paths) await validate(path);
console.log(`Validated ${paths.length} VRM models.`);
async function validate(path) {
const bytes = fs.readFileSync(path);
const result = await validator.validateBytes(new Uint8Array(bytes), { uri: 'humar.vrm' });
assert.equal(result.issues.numWarnings, 0, path);
if (result.issues.numErrors) console.log(result.issues);
assert.equal(result.issues.numErrors, 0);
const doc = JSON.parse(bytes.subarray(20, 20 + bytes.readUInt32LE(12)).toString());
const binaryStart = 28 + bytes.readUInt32LE(12);
const imageView = doc.bufferViews[doc.images[0].bufferView];
assert.equal(bytes.subarray(binaryStart + imageView.byteOffset, binaryStart + imageView.byteOffset + 8).toString('hex'), '89504e470d0a1a0a');
assert.equal(doc.images[0].uri, undefined, 'texture is embedded');
globalThis.self = globalThis;
const loader = new GLTFLoader();
loader.register(() => ({ name: 'NodeTextureStub', loadTexture: async () => new THREE.Texture() }));
loader.register(parser => new VRMLoaderPlugin(parser, { autoUpdateHumanBones: true }));
const gltf = await loader.parseAsync(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), '');
const vrm = gltf.userData.vrm;
assert.ok(vrm?.humanoid, 'three-vrm recognizes a humanoid');
assert.equal(vrm.meta.metaVersion, '1');
const roles = Object.keys(doc.extensions.VRMC_vrm.humanoid.humanBones);
assert.equal(roles.length, 15);
for (const role of roles) assert.ok(vrm.humanoid.getRawBoneNode(role), role);
vrm.scene.updateMatrixWorld(true);
for (const side of ['left', 'right']) {
  const shoulder = vrm.humanoid.getRawBoneNode(side + 'UpperArm').getWorldPosition(new THREE.Vector3());
  const elbow = vrm.humanoid.getRawBoneNode(side + 'LowerArm').getWorldPosition(new THREE.Vector3());
  const hand = vrm.humanoid.getRawBoneNode(side + 'Hand').getWorldPosition(new THREE.Vector3());
  assert.ok(Math.abs(shoulder.y - elbow.y) < 1e-5 && Math.abs(elbow.y - hand.y) < 1e-5, side + ' arm is horizontal');
  const direction = side === 'left' ? 1 : -1;
  assert.ok(shoulder.x * direction > 0 && (elbow.x - shoulder.x) * direction > 0 && (hand.x - elbow.x) * direction > 0, side + ' arm extends outward');
  assert.ok(Math.abs(shoulder.z - hand.z) < 1e-5, side + ' arm extends along X');
}
const bounds = new THREE.Box3().setFromObject(vrm.scene);
assert.ok(Math.abs(bounds.min.y) < 1e-5, 'soles are grounded');
// Prove the added endpoints actually deform weighted vertices.
for (const role of ['leftHand', 'rightHand', 'leftFoot', 'rightFoot']) {
  const bone = vrm.humanoid.getRawBoneNode(role);
  const meshes = [];
  vrm.scene.traverse(object => { if (object.isSkinnedMesh) meshes.push(object); });
  const before = meshes.map(mesh => {
    mesh.skeleton.update();
    return Array.from({length: mesh.geometry.attributes.position.count}, (_, i) => mesh.getVertexPosition(i, new THREE.Vector3()));
  });
  const saved = bone.quaternion.clone();
  bone.rotateZ(0.25);
  vrm.scene.updateMatrixWorld(true);
  let moved = 0;
  meshes.forEach((mesh, m) => {
    mesh.skeleton.update();
    before[m].forEach((position, i) => { if (mesh.getVertexPosition(i, new THREE.Vector3()).distanceTo(position) > 1e-5) moved++; });
  });
  assert.ok(moved > 0, role + ' deforms the mesh');
  bone.quaternion.copy(saved);
  vrm.scene.updateMatrixWorld(true);
}
console.log('three-vrm:', JSON.stringify({ humanoidBones: roles.length, bounds: { min: bounds.min, max: bounds.max }, meta: vrm.meta.name }));
console.log('PASS', path);

}
