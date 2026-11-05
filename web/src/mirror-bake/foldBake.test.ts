import { describe, expect, it } from 'vitest';
import * as T from 'three';
import { foldBake, mirrorFold, type BakeSettings } from './foldBake';

function fixture() {
  const g = new T.BufferGeometry();
  g.setAttribute('position', new T.Float32BufferAttribute([0,0,0, 1,0,0, 0,1,0], 3));
  g.setAttribute('uv', new T.Float32BufferAttribute([-2.3,-1.7, 3.2,-.1, -.4,2.8], 2));
  g.setAttribute('color', new T.Float32BufferAttribute([1,0,0, 0,1,0, 0,0,1], 3));
  g.setIndex([0,1,2]);
  g.addGroup(0,3,2);
  return g;
}
describe('static mirror bake', () => {
  for (const mirror of [[true,false], [false,true], [true,true], [false,false]] as [boolean,boolean][]) {
    it(`preserves area, winding, attributes and interior sampling: ${mirror}`, () => {
      const src = fixture(), before = src.getAttribute('uv').array.slice();
      const settings: BakeSettings = { repeat: [2.1,-.8], offset: [.37,-.21], mirror };
      const baked = foldBake(src, settings);
      const p = baked.getAttribute('position'), uv = baked.getAttribute('uv'), color = baked.getAttribute('color');
      let area = 0;
      for (let i = 0; i < p.count; i += 3) {
        const points = [0,1,2].map(j => new T.Vector3().fromBufferAttribute(p, i+j));
        const cross = points[1].clone().sub(points[0]).cross(points[2].clone().sub(points[0])).z;
        expect(cross).toBeGreaterThan(0); area += cross / 2;
        // Barycentric interior samples exercise whole faces, not just folded vertices.
        for (const weights of [[.2,.3,.5], [.7,.1,.2]]) {
          const x = points.reduce((s,v,j) => s+v.x*weights[j],0), y = points.reduce((s,v,j) => s+v.y*weights[j],0);
          for (let axis=0; axis<2; axis++) {
            const input = src.getAttribute('uv');
            const effective = ((1-x-y)*input.getComponent(0,axis)+x*input.getComponent(1,axis)+y*input.getComponent(2,axis))*settings.repeat[axis]+settings.offset[axis];
            const actual = weights.reduce((s,w,j) => s+w*uv.getComponent(i+j,axis),0);
            expect(actual).toBeCloseTo(mirror[axis] ? mirrorFold(effective) : effective, 5);
          }
        }
      }
      expect(area).toBeCloseTo(.5, 6);
      for (let i=0; i<p.count; i++) {
        expect(color.getX(i)).toBeCloseTo(1-p.getX(i)-p.getY(i), 6);
        expect(color.getY(i)).toBeCloseTo(p.getX(i), 6);
      }
      expect(baked.groups).toEqual([{start:0,count:p.count,materialIndex:2}]);
      expect(src.getAttribute('uv').array).toEqual(before);
      expect(foldBake(src, settings).getAttribute('uv').array).toEqual(uv.array);
    });
  }
  it('keeps triangles on exact fold boundaries and degenerate UVs', () => {
    const g = fixture(); g.setAttribute('uv', new T.Float32BufferAttribute([1,0, 1,1, 1,2],2));
    const b = foldBake(g,{repeat:[1,1],offset:[0,0],mirror:[true,false]});
    expect(b.getAttribute('position').count).toBe(3);
    expect(Array.from(b.getAttribute('uv').array)).toEqual([1,0,1,1,1,2]);
  });
  it('rejects unsupported deformation and excessive subdivision', () => {
    const g = fixture();
    expect(()=>foldBake(g,{repeat:[1e6,1],offset:[0,0],mirror:[true,false]})).toThrow('limit');
    g.setAttribute('skinIndex',new T.Uint16BufferAttribute(new Array(12).fill(0),4));
    expect(()=>foldBake(g,{repeat:[1,1],offset:[0,0],mirror:[true,true]})).toThrow('Skinned');
  });
  it('prevents applying the authored transform to a baked result twice', () => {
    const settings: BakeSettings = {repeat:[2,1],offset:[0,0],mirror:[true,false]};
    const baked = foldBake(fixture(), settings);
    expect(()=>foldBake(baked, settings)).toThrow('Already baked');
  });
});
