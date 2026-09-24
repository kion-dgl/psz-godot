import { describe, expect, it } from 'vitest';
import { auditTriangles, classifyFace, faceArea, type TriFace } from '../city-lab/triangleAudit';
import { lightsDocJson, lightsGdscript, parseLightsDoc, toLightsDoc } from '../city-lab/lightExport';
import { threePointLightProps } from '../city-lab/lightingRig';
import { STAGES } from '../city-lab/types';

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
});
