import * as T from 'three';
import type { BakeSettings } from './foldBake';

/** Expanded triangles keep the fixture independent of GLB importers and skins.
 * Godot reverses winding when constructing its ArrayMesh; coordinates stay intact.
 */
function geometryData(geometry: T.BufferGeometry) {
  const data: Record<string, number[]> = {};
  const count = geometry.index?.count ?? geometry.getAttribute('position').count;
  for (const name of ['position', 'normal', 'uv']) {
    const attr = geometry.getAttribute(name);
    if (!attr) throw new Error(`Godot fixture needs ${name}`);
    data[name] = [];
    for (let i = 0; i < count; i++) {
      const index = geometry.index ? geometry.index.getX(i) : i;
      for (let c = 0; c < attr.itemSize; c++) data[name].push(attr.getComponent(index, c));
    }
  }
  return data;
}

export function godotFixture(source: string, original: T.BufferGeometry, baked: T.BufferGeometry, texture: T.Texture, settings: BakeSettings) {
  const image = texture.image;
  const canvas = document.createElement('canvas'); canvas.width = image.width; canvas.height = image.height;
  const context = canvas.getContext('2d')!;
  // Godot Image UV origin is top-left; match Three's actual upload orientation.
  if (texture.flipY) { context.translate(0, canvas.height); context.scale(1, -1); }
  context.drawImage(image, 0, 0);
  return {
    version: 1, source, settings, staticSnapshot: true,
    provenance: source === 'stage' ? 'assets/stages/valley_a/s01a_ga1/lndmd/s01a_ga1_m.glb : 1_pass1 (normalized rest pose)' : 'MirrorBakeLab asymmetric test card',
    original: geometryData(original), baked: geometryData(baked),
    texturePng: canvas.toDataURL('image/png').split(',')[1],
  };
}
