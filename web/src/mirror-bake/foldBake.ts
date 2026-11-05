import * as THREE from 'three';

export interface BakeSettings {
  repeat: [number, number];
  offset: [number, number];
  mirror: [boolean, boolean];
}
type Vertex = { uv: [number, number]; weights: [number, number, number] };
export const mirrorFold = (x: number) => 1 - Math.abs(((x % 2) + 2) % 2 - 1);

function clip(poly: Vertex[], axis: number, boundary: number, lower: boolean): Vertex[] {
  const out: Vertex[] = [];
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    const insideA = lower ? a.uv[axis] <= boundary : a.uv[axis] >= boundary;
    const insideB = lower ? b.uv[axis] <= boundary : b.uv[axis] >= boundary;
    if (insideA) out.push(a);
    if (insideA !== insideB) {
      const t = (boundary - a.uv[axis]) / (b.uv[axis] - a.uv[axis]);
      const v: Vertex = {
        uv: a.uv.map((x, j) => x + t * (b.uv[j] - x)) as Vertex['uv'],
        weights: a.weights.map((x, j) => x + t * (b.weights[j] - x)) as Vertex['weights'],
      };
      v.uv[axis] = boundary;
      out.push(v);
    }
  }
  // Boundary vertices can be emitted by both an edge and its intersection.
  return out.filter((v, i) => !v.weights.every((w, j) => Math.abs(w - out[(i + 1) % out.length].weights[j]) < 1e-12));
}

/** Static triangle meshes only. Inputs are never mutated. UVs include the transform;
 * output textures must reset repeat/offset and CLAMP each baked mirror axis.
 * No half-texel shrink: native clamp supplies the duplicated edge texel.
 */
export function foldBake(source: THREE.BufferGeometry, settings: BakeSettings): THREE.BufferGeometry {
  if (source.userData.mirrorBake) throw new Error('Already baked: restart from the source geometry');
  if (![...settings.repeat, ...settings.offset].every(Number.isFinite)) throw new Error('Non-finite UV transform');
  if (source.getAttribute('skinIndex') || source.getAttribute('skinWeight') || Object.keys(source.morphAttributes).length) {
    throw new Error('Skinned and morph meshes are not supported by the static bake');
  }
  const uv = source.getAttribute('uv'), position = source.getAttribute('position');
  if (!uv || uv.itemSize !== 2 || !position) throw new Error('Position and UV attributes are required');
  const count = source.index?.count ?? position.count;
  if (count % 3 || source.drawRange.start !== 0 || source.drawRange.count < count) throw new Error('Full triangle draw range required');
  const names = Object.keys(source.attributes);
  for (const name of names) {
    const attr = source.getAttribute(name);
    if (attr.count !== position.count) throw new Error(`Mismatched attribute: ${name}`);
  }
  const data: Record<string, number[]> = Object.fromEntries(names.map(n => [n, []]));
  const result = new THREE.BufferGeometry();
  let emitted = 0;
  for (let tri = 0; tri < count; tri += 3) {
    const ids = [0, 1, 2].map(i => source.index ? source.index.getX(tri + i) : tri + i);
    const vertices: Vertex[] = ids.map((id, i) => ({
      uv: [uv.getX(id) * settings.repeat[0] + settings.offset[0], uv.getY(id) * settings.repeat[1] + settings.offset[1]],
      weights: [i === 0 ? 1 : 0, i === 1 ? 1 : 0, i === 2 ? 1 : 0],
    }));
    if (!vertices.every(v => v.uv.every(Number.isFinite))) throw new Error('Non-finite UV');
    let pieces = [vertices];
    for (let axis = 0; axis < 2; axis++) {
      if (!settings.mirror[axis]) continue;
      const min = Math.min(...vertices.map(v => v.uv[axis]));
      const max = Math.max(...vertices.map(v => v.uv[axis]));
      if (max - min > 2048 || Math.abs(min) > 1e7 || Math.abs(max) > 1e7) throw new Error('UV span exceeds bake limit');
      for (let boundary = Math.floor(min) + 1; boundary < max; boundary++) {
        pieces = pieces.flatMap(poly => {
          if (!poly.some(v => v.uv[axis] < boundary) || !poly.some(v => v.uv[axis] > boundary)) return [poly];
          return [clip(poly, axis, boundary, true), clip(poly, axis, boundary, false)].filter(p => p.length >= 3);
        });
        if (pieces.length > 100000) throw new Error('Bake exceeds polygon limit');
      }
    }
    const start = emitted;
    for (const poly of pieces) for (let k = 1; k < poly.length - 1; k++) {
      const triangle = [poly[0], poly[k], poly[k + 1]];
      // Reject zero-area barycentric slivers without discarding UV-degenerate faces.
      const [a, b, c] = triangle.map(v => v.weights);
      if (Math.abs((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])) < 1e-14) continue;
      for (const v of triangle) for (const name of names) {
        const attr = source.getAttribute(name);
        if (name === 'uv') data[name].push(...v.uv.map((x, axis) => settings.mirror[axis] ? mirrorFold(x) : x));
        else for (let component = 0; component < attr.itemSize; component++) {
          data[name].push(ids.reduce((sum, id, j) => sum + attr.getComponent(id, component) * v.weights[j], 0));
        }
      }
      emitted += 3;
      if (emitted > 1000000) throw new Error('Bake exceeds vertex limit');
    }
    for (const group of source.groups) {
      if (tri >= group.start && tri + 3 <= group.start + group.count) {
        const last = result.groups[result.groups.length - 1];
        if (last && last.materialIndex === group.materialIndex && last.start + last.count === start) last.count += emitted - start;
        else result.addGroup(start, emitted - start, group.materialIndex);
      }
    }
  }
  for (const name of names) result.setAttribute(name, new THREE.Float32BufferAttribute(data[name], source.getAttribute(name).itemSize));
  result.name = source.name;
  result.userData = { ...source.userData, mirrorBake: { version: 1, settings: structuredClone(settings) } };
  result.computeBoundingBox();
  result.computeBoundingSphere();
  return result;
}
