/**
 * Triangle audit — classify malformed triangles in a loaded city GLB.
 *
 * Pure math over world-space faces so it is unit-testable without a
 * renderer. Classes, in severity order:
 *
 *   nonfinite (3)      a coordinate is NaN/±Inf — the mesh is corrupt at
 *                      this face; exporters and collision cookers choke.
 *   zero-area (2)      the face collapses to a line/point (area < ZERO_AREA).
 *                      Renders as an invisible sliver but still costs a
 *                      draw and can produce NaN normals.
 *   duplicate-vertex   two of the three vertices are the same point — the
 *                      prelude to zero-area, kept distinct because the fix
 *                      differs (weld vs delete).
 *   sliver (1)         area > 0 but the shape is a needle:
 *                      aspect = longestEdge² / (4·√3·area) > SLIVER_ASPECT.
 *                      An equilateral scores 1; a legit 10:1 plank scores
 *                      ~3, so 40 only flags true needles.
 */

import type { AuditStats, IssueClass, TriangleIssue, Vec3 } from './types';

export const ZERO_AREA_EPS = 1e-9;
export const SLIVER_ASPECT = 40;
export const DUPLICATE_EPS = 1e-9;
/** Below this UV span a duplicate-UV face is a deliberate flat-color fill
 *  (one texel region of the atlas), not a striping bug. */
export const UV_SPAN_MIN = 0.05;
export const UV_DUP_EPS = 1e-4;

export type Vec2 = [number, number];

export interface TriFace {
  meshName: string;
  faceIndex: number;
  v0: Vec3;
  v1: Vec3;
  v2: Vec3;
  /** Per-vertex UVs, when the mesh carries TEXCOORD_0. */
  uvs?: [Vec2, Vec2, Vec2];
}

function dist(a: Vec3, b: Vec3): number {
  const dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

function finite(...vs: Vec3[]): boolean {
  for (const v of vs) {
    for (const c of v) {
      if (!Number.isFinite(c)) return false;
    }
  }
  return true;
}

/** Twice the triangle area (cross product magnitude) — avoids the sqrt. */
function cross2(a: Vec3, b: Vec3, c: Vec3): number {
  const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
  const vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
  const cx = uy * vz - uz * vy;
  const cy = uz * vx - ux * vz;
  const cz = ux * vy - uy * vx;
  return Math.sqrt(cx * cx + cy * cy + cz * cz);
}

export function classifyFace(f: TriFace): TriangleIssue | null {
  const { v0, v1, v2 } = f;
  const base = {
    key: `${f.meshName}#${f.faceIndex}`,
    meshName: f.meshName,
    faceIndex: f.faceIndex,
    v0, v1, v2,
    centroid: [
      (v0[0] + v1[0] + v2[0]) / 3,
      (v0[1] + v1[1] + v2[1]) / 3,
      (v0[2] + v1[2] + v2[2]) / 3,
    ] as Vec3,
  };

  if (!finite(v0, v1, v2)) {
    return { ...base, cls: 'nonfinite', severity: 3, area: 0, aspect: Infinity };
  }

  if (
    dist(v0, v1) < DUPLICATE_EPS ||
    dist(v1, v2) < DUPLICATE_EPS ||
    dist(v0, v2) < DUPLICATE_EPS
  ) {
    return { ...base, cls: 'duplicate-vertex', severity: 2, area: 0, aspect: Infinity };
  }

  const area = cross2(v0, v1, v2) / 2;
  if (area < ZERO_AREA_EPS) {
    return { ...base, cls: 'zero-area', severity: 2, area, aspect: Infinity };
  }

  const longest = Math.max(dist(v0, v1), dist(v1, v2), dist(v0, v2));
  const aspect = (longest * longest) / (4 * Math.sqrt(3) * area);

  // Texture-space degeneracy: two verts share a UV, so the face maps onto
  // a single texel line stretched across real area — visible as stripes
  // when the sampled line has color variation (flat-band atlas fills do
  // this harmlessly, hence the span floor). Ranked below the geometric
  // classes but above slivers, which are the weakest signal.
  if (f.uvs) {
    const [a, c, d] = f.uvs;
    const duvs = [dist2d(a, c), dist2d(c, d), dist2d(a, d)];
    const hasDup = duvs.some((d2) => d2 < UV_DUP_EPS);
    const span = Math.max(...duvs);
    if (hasDup && span > UV_SPAN_MIN) {
      return { ...base, cls: 'uv-degenerate', severity: 1, area, aspect };
    }
  }

  if (aspect > SLIVER_ASPECT) {
    return { ...base, cls: 'sliver', severity: 1, area, aspect };
  }

  return null;
}

function dist2d(a: Vec2, b: Vec2): number {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

/**
 * Audit a whole stage dump. Faces arrive pre-transformed to world space
 * (the canvas walks the loaded scene); issues sort most-severe first,
 * then by area ascending, so the worst needle is always row one.
 */
export function auditTriangles(faces: TriFace[]): { issues: TriangleIssue[]; stats: AuditStats } {
  const byClass: Record<IssueClass, number> = {
    nonfinite: 0,
    'zero-area': 0,
    'duplicate-vertex': 0,
    'uv-degenerate': 0,
    sliver: 0,
  };
  const meshes = new Set<string>();
  const issues: TriangleIssue[] = [];
  for (const f of faces) {
    meshes.add(f.meshName);
    const issue = classifyFace(f);
    if (issue) {
      byClass[issue.cls]++;
      issues.push(issue);
    }
  }
  issues.sort((a, b) => b.severity - a.severity || a.area - b.area);
  return {
    issues,
    stats: {
      meshes: meshes.size,
      faces: faces.length,
      issues: issues.length,
      byClass,
    },
  };
}

/** Face area helper shared by the inspector panel (world space, m²). */
export function faceArea(v0: Vec3, v1: Vec3, v2: Vec3): number {
  return cross2(v0, v1, v2) / 2;
}
