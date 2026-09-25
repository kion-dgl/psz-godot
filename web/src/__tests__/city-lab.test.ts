import { describe, expect, it } from 'vitest';
import * as THREE from 'three';
import { auditTriangles, classifyFace, faceArea, type TriFace } from '../city-lab/triangleAudit';
import { lightsDocJson, lightsGdscript, parseLightsDoc, toLightsDoc } from '../city-lab/lightExport';
import { robustStageBox, threePointLightProps } from '../city-lab/lightingRig';
import { STAGES } from '../city-lab/types';

const faceWithUvs = (
  meshName: string,
  faceIndex: number,
  v0: number[],
  v1: number[],
  v2: number[],
  uvs: [number, number][],
): TriFace => ({
  meshName,
  faceIndex,
  v0: [v0[0], v0[1], v0[2]],
  v1: [v1[0], v1[1], v1[2]],
  v2: [v2[0], v2[1], v2[2]],
  uvs: [
    [uvs[0][0], uvs[0][1]],
    [uvs[1][0], uvs[1][1]],
    [uvs[2][0], uvs[2][1]],
  ],
});

const face = (meshName: string, faceIndex: number, v0: number[], v1: number[], v2: number[]): TriFace => ({
  meshName,
  faceIndex,
  v0: [v0[0], v0[1], v0[2]],
  v1: [v1[0], v1[1], v1[2]],
  v2: [v2[0], v2[1], v2[2]],
});

describe('classifyFace', () => {
  it('passes a clean equilateral-ish face', () => {
    expect(classifyFace(face('m', 0, [0, 0, 0], [1, 0, 0], [0, 1, 0]))).toBeNull();
  });

  it('passes a legit long plank (10:1 right triangle, aspect ≈ 2.9)', () => {
    expect(classifyFace(face('m', 0, [0, 0, 0], [10, 0, 0], [0, 1, 0]))).toBeNull();
  });

  it('flags nonfinite coordinates as severity 3', () => {
    const issue = classifyFace(face('m', 3, [0, 0, 0], [NaN, 1, 0], [0, 1, 1]));
    expect(issue?.cls).toBe('nonfinite');
    expect(issue?.severity).toBe(3);
  });

  it('flags duplicate vertices', () => {
    const issue = classifyFace(face('m', 7, [1, 1, 1], [1, 1, 1], [0, 0, 0]));
    expect(issue?.cls).toBe('duplicate-vertex');
    expect(issue?.severity).toBe(2);
  });

  it('flags zero-area (collinear) faces', () => {
    const issue = classifyFace(face('m', 9, [0, 0, 0], [1, 1, 1], [2, 2, 2]));
    expect(issue?.cls).toBe('zero-area');
    expect(issue?.area).toBe(0);
  });

  it('flags a needle sliver but reports its real area', () => {
    const issue = classifyFace(face('m', 12, [0, 0, 0], [10, 0, 0], [10, 0.01, 0]));
    expect(issue?.cls).toBe('sliver');
    expect(issue?.severity).toBe(1);
    expect(issue?.area).toBeGreaterThan(0);
    expect(issue?.aspect).toBeGreaterThan(40);
  });

  it('keys issues by mesh#face', () => {
    const issue = classifyFace(face('s00e_sa1_m.001', 42, [0, 0, 0], [NaN, 0, 0], [1, 1, 1]));
    expect(issue?.key).toBe('s00e_sa1_m.001#42');
  });
});

describe('uv-degenerate faces (stripes)', () => {
  // The exact dairon2 shape: two of three verts share a UV with real
  // span — the whole face samples one texel line = stripes.
  it('flags a duplicate-UV pair with real span', () => {
    const issue = classifyFace(
      faceWithUvs('m', 318, [-13.048, 0.73, 37.113], [-8.443, 1.398, 39.043], [-7.689, -0.015, 38.421], [
        [1.75, 0.753], [2.25, 0.753], [2.25, 0.753],
      ]),
    );
    expect(issue?.cls).toBe('uv-degenerate');
    expect(issue?.severity).toBe(1);
  });

  it('leaves deliberate single-texel fills alone (all UVs identical)', () => {
    expect(
      classifyFace(faceWithUvs('m', 0, [0, 0, 0], [1, 0, 0], [0, 1, 0], [[0.5, 0.5], [0.5, 0.5], [0.5, 0.5]])),
    ).toBeNull();
  });

  it('leaves healthy UV triangles alone', () => {
    expect(
      classifyFace(faceWithUvs('m', 1, [0, 0, 0], [1, 0, 0], [0, 1, 0], [[0, 0], [0.5, 0], [0, 0.5]])),
    ).toBeNull();
  });

  it('ranks below geometric degenerates', () => {
    const issue = classifyFace(
      faceWithUvs('m', 2, [0, 0, 0], [1, 1, 1], [2, 2, 2], [[0, 0], [0.5, 0], [0.5, 0]]),
    );
    expect(issue?.cls).toBe('zero-area');
  });
});

describe('auditTriangles', () => {
  it('counts and sorts by severity, worst first', () => {
    const { issues, stats } = auditTriangles([
      face('a', 0, [0, 0, 0], [1, 0, 0], [0, 1, 0]),          // clean
      face('a', 1, [0, 0, 0], [10, 0, 0], [10, 0.01, 0]),      // sliver
      face('a', 2, [0, 0, 0], [NaN, 1, 0], [0, 1, 1]),         // nonfinite
      face('b', 0, [0, 0, 0], [1, 1, 1], [2, 2, 2]),           // zero-area
    ]);
    expect(stats.faces).toBe(4);
    expect(stats.meshes).toBe(2);
    expect(stats.issues).toBe(3);
    expect(stats.byClass.nonfinite).toBe(1);
    expect(stats.byClass['zero-area']).toBe(1);
    expect(stats.byClass.sliver).toBe(1);
    expect(issues[0].cls).toBe('nonfinite');
  });

  it('returns an empty, valid report for a clean mesh', () => {
    const { issues, stats } = auditTriangles([face('a', 0, [0, 0, 0], [1, 0, 0], [0, 1, 0])]);
    expect(issues).toHaveLength(0);
    expect(stats.issues).toBe(0);
  });
});

describe('faceArea', () => {
  it('computes world-space area', () => {
    expect(faceArea([0, 0, 0], [2, 0, 0], [0, 2, 0])).toBeCloseTo(2, 9);
  });
});

describe('lightExport', () => {
  const doc = toLightsDoc(
    's00e_sa2',
    [
      {
        id: 'L1',
        name: 'CounterPool',
        pos: [-7.86, -8.7, 111.39],
        color: [1.0, 0.7, 0.3],
        energy: 5,
        range: 11,
        attenuation: 1,
        shadows: true,
      },
    ],
    { color: [0.9, 0.88, 0.82], energy: 1.5 },
  );

  it('round-trips through JSON', () => {
    const parsed = parseLightsDoc(lightsDocJson(doc));
    expect(parsed).not.toBeNull();
    expect(parsed?.stage).toBe('s00e_sa2');
    expect(parsed?.lights).toHaveLength(1);
    expect(parsed?.lights[0].pos).toEqual([-7.86, -8.7, 111.39]);
    expect(parsed?.lights[0].energy).toBe(5);
    expect(parsed?.ambient.energy).toBe(1.5);
  });

  it('rejects malformed sidecars', () => {
    expect(parseLightsDoc('not json')).toBeNull();
    expect(parseLightsDoc('{"stage": "x"}')).toBeNull();
    expect(parseLightsDoc('{"stage":"s00e_sa2","lights":"nope"}')).toBeNull();
  });

  it('skips lights with bad vectors instead of failing the doc', () => {
    const parsed = parseLightsDoc(
      JSON.stringify({
        stage: 's00e_sa2',
        ambient: { color: [1, 1, 1], energy: 1 },
        lights: [
          { name: 'ok', pos: [0, 0, 0], color: [1, 1, 1], energy: 2 },
          { name: 'bad', pos: [0, 0], color: [1, 1, 1] },
        ],
      }),
    );
    expect(parsed?.lights).toHaveLength(1);
    expect(parsed?.lights[0].name).toBe('ok');
  });

  it('emits GDScript with Godot-typed values', () => {
    const gs = lightsGdscript(doc);
    expect(gs).toContain('Vector3(-7.86, -8.7, 111.39)');
    expect(gs).toContain('Color(1.0, 0.7, 0.3)');
    expect(gs).toContain('"energy": 5.0');
    expect(gs).toContain('shadows on');
  });

  it('emits floats GDScript can parse (never bare ints)', () => {
    const gs = lightsGdscript(
      toLightsDoc(
        's00e_sa2',
        [{ id: 'L', name: 'Zero', pos: [0, 0, 0], color: [1, 1, 1], energy: 2, range: 15, attenuation: 1, shadows: false }],
        { color: [1, 1, 1], energy: 1 },
      ),
    );
    expect(gs).toContain('Vector3(0.0, 0.0, 0.0)');
  });
});

describe('threePointLightProps', () => {
  it('maps Godot omni params 1:1 into three', () => {
    const props = threePointLightProps({
      id: 'L', name: 'n', pos: [0, 0, 0], color: [1, 0.5, 0.25],
      energy: 5, range: 11, attenuation: 1, shadows: true,
    });
    expect(props.intensity).toBe(5);
    expect(props.distance).toBe(11);
    expect(props.decay).toBe(1);
    expect(props.color.r).toBeCloseTo(1, 5);
    expect(props.color.g).toBeCloseTo(0.5, 5);
  });
});

describe('stage table', () => {
  it('gives the counter a sidecar id and the market a lineage export path', () => {
    const counter = STAGES.find((s) => s.id === 'counter');
    expect(counter?.lightStageId).toBe('s00e_sa2');
    expect(counter?.vertexColors).toBe(false);
    const market = STAGES.find((s) => s.id === 'market');
    expect(market?.exportPath).toBe('assets/stages/city_e/market/dairon3.glb');
  });

  it('pairs the market with its fixed dairon3 build (what the game renders)', () => {
    const fixed = STAGES.find((s) => s.id === 'market-fixed');
    expect(fixed?.models[0].path).toBe('assets/stages/city_e/market/dairon3.glb');
    expect(fixed?.exportPath).toBeUndefined();
  });
});

describe('robustStageBox', () => {
  const boxMesh = (w: number, h: number, d: number, x = 0, y = 0, z = 0) => {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d));
    mesh.position.set(x, y, z);
    return mesh;
  };

  it('frames a clean stage normally', () => {
    const root = new THREE.Group();
    root.add(boxMesh(10, 10, 10, 0, 0, 0), boxMesh(4, 4, 4, 30, 0, 0));
    const box = robustStageBox(root);
    expect(box.min.x).toBeCloseTo(-5, 5);
    expect(box.max.x).toBeCloseTo(32, 5);
  });

  it('ignores dairon2-style spike vertices a billion units out', () => {
    // Reproduces the blank-market bug: one mesh carries stray vertices at
    // y = -1e9 (the six spike triangles), poisoning a whole-stage Box3.
    const root = new THREE.Group();
    root.add(boxMesh(20, 20, 20, 0, 0, 100));
    const spike = new THREE.BufferGeometry();
    spike.setAttribute(
      'position',
      new THREE.BufferAttribute(
        new Float32Array([
          -32.69, -1e9, 25.23,
          -32.6, -1e9, 24.97,
          -32.6, 11.09, 24.97,
        ]),
        3,
      ),
    );
    const spikeMesh = new THREE.Mesh(spike);
    spikeMesh.position.set(0, 0, 100);
    root.add(spikeMesh);
    const box = robustStageBox(root);
    expect(box.min.y).toBeGreaterThan(-1e6);
    expect(box.getSize(new THREE.Vector3()).length()).toBeLessThan(100);
  });

  it('falls back to every mesh when all boxes are uniformly huge', () => {
    const root = new THREE.Group();
    root.add(boxMesh(5000, 5000, 5000), boxMesh(6000, 6000, 6000));
    const box = robustStageBox(root);
    expect(box.isEmpty()).toBe(false);
  });
});
