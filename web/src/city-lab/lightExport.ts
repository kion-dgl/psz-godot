/**
 * Light sidecar export — the #656/#636 transfer path.
 *
 * The tool authors lights in Godot units (energy / omni_range /
 * omni_attenuation) and writes a JSON sidecar that the Godot loader
 * (city_area_base._add_authored_lights) consumes 1:1 — no unit math on
 * either side. The GDScript preview mirrors the same values in the
 * shape of the legacy _add_interior_lights call so a PR diff can be
 * eyeballed without opening the JSON.
 */

import type { AmbientSpec, LightSpec, LightsDoc, Vec3 } from './types';

const f = (n: number): string => {
  // Always keep a decimal so GDScript reads a float, never an int.
  const s = n.toFixed(3).replace(/(\.\d*?)0+$/, '$1');
  return s.endsWith('.') ? s + '0' : s;
};

const v3 = (v: Vec3): string => `Vector3(${f(v[0])}, ${f(v[1])}, ${f(v[2])})`;
const col = (v: Vec3): string => `Color(${f(v[0])}, ${f(v[1])}, ${f(v[2])})`;

export function toLightsDoc(stage: string, lights: LightSpec[], ambient: AmbientSpec): LightsDoc {
  return { stage, ambient, lights };
}

export function lightsDocJson(doc: LightsDoc): string {
  return `${JSON.stringify(doc, null, 2)}\n`;
}

/** Inverse of lightsDocJson — for loading an existing sidecar into the tool.
 *  Returns null on anything malformed (the tool then starts from defaults). */
export function parseLightsDoc(text: string): LightsDoc | null {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof raw !== 'object' || raw === null) return null;
  const d = raw as Record<string, unknown>;
  if (typeof d.stage !== 'string' || !Array.isArray(d.lights)) return null;

  const vec = (v: unknown): Vec3 | null =>
    Array.isArray(v) && v.length === 3 && v.every((n) => typeof n === 'number' && Number.isFinite(n))
      ? [v[0] as number, v[1] as number, v[2] as number]
      : null;

  const lights: LightSpec[] = [];
  for (const item of d.lights) {
    if (typeof item !== 'object' || item === null) continue;
    const l = item as Record<string, unknown>;
    const pos = vec(l.pos);
    const color = vec(l.color);
    if (!pos || !color) continue;
    lights.push({
      id: typeof l.id === 'string' ? l.id : `light-${lights.length}`,
      name: typeof l.name === 'string' ? l.name : `Light${lights.length}`,
      pos,
      color,
      energy: typeof l.energy === 'number' ? l.energy : 2.0,
      range: typeof l.range === 'number' ? l.range : 15.0,
      attenuation: typeof l.attenuation === 'number' ? l.attenuation : 1.0,
      shadows: l.shadows === true,
    });
  }

  const ambRaw = (typeof d.ambient === 'object' && d.ambient !== null ? d.ambient : {}) as Record<string, unknown>;
  const ambColor = vec(ambRaw.color) ?? ([1, 1, 1] as Vec3);
  const ambient: AmbientSpec = {
    color: ambColor,
    energy: typeof ambRaw.energy === 'number' ? ambRaw.energy : 1.0,
  };
  return { stage: d.stage, ambient, lights };
}

/** Paste-ready GDScript mirroring the sidecar (for PR review / fallback). */
export function lightsGdscript(doc: LightsDoc): string {
  const lines: string[] = [
    `# Authored in web #/city-lab — source of truth is`,
    `# data/stage_configs/city-lights/${doc.stage}.json (${doc.lights.length} lights).`,
    `# Ambient: ${col(doc.ambient.color)} @ ${f(doc.ambient.energy)}`,
  ];
  for (const l of doc.lights) {
    lines.push(
      `#   ${l.name}: ${v3(l.pos)}  ${col(l.color)}  energy ${f(l.energy)}` +
        `  range ${f(l.range)}  attenuation ${f(l.attenuation)}  shadows ${l.shadows ? 'on' : 'off'}`,
    );
  }
  lines.push(
    '',
    'const AUTHORED_LIGHTS := [',
    ...doc.lights.map(
      (l) =>
        `\t{"name": "${l.name}", "pos": ${v3(l.pos)}, "color": ${col(l.color)}, ` +
        `"energy": ${f(l.energy)}, "range": ${f(l.range)}, ` +
        `"attenuation": ${f(l.attenuation)}, "shadows": ${l.shadows}},`,
    ),
    ']',
  );
  return lines.join('\n');
}
