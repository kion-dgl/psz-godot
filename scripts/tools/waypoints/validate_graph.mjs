// The one definition of a valid autopilot nav graph.
//
// Imported by the `wp` CLI (wp_tool.mjs), the dev-server save endpoint
// (web/vite-plugin-stage-config-save.ts), and the CI coverage guard
// (web/src/__tests__/waypoint-coverage.test.ts) so a graph is judged the
// same way wherever it is checked. No shebang and no side effects on
// import — Vite's esbuild pass inlines this file into the dev config.

// Engine offsets: portal.position is the GATE; the player spawns 3m outward
// and the scene-change trigger sits 7m outward.
const SPAWN_OUTSET = 3;
const EXIT_OUTSET = 7;
const OUTWARD = { north: [0, -1], south: [0, 1], east: [1, 0], west: [-1, 0] };
// Tolerance for matching a node to its expected offset. The widest deviation
// across all 218 authored stages is 0.44m; 1.5m leaves room for hand-nudging
// a node off a floor seam without silently accepting a misplaced one.
const OFFSET_TOL = 1.5;

export const AREA_NAMES = {
  s01: "Gurhacia Valley",
  s02: "Ozette Wetlands",
  s03: "Rioh Snowfield",
  s04: "Makara Ruins",
  s05: "Oblivion City Paru",
  s06: "Arca Plant",
  s07: "Dark Shrine",
  s08: "Eternal Tower",
};

export const isFieldStage = (id) => Object.hasOwn(AREA_NAMES, id.slice(0, 3));
export const areaOf = (id) => id.slice(0, 3);

const dist2d = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);

// ── validation ─────────────────────────────────────────────

/**
 * Validate one stage's graph. Returns { errors, warnings, stats }.
 * `errors` are contract violations the autopilot will trip over; `warnings`
 * are things worth a look that don't break navigation.
 */
export function validateGraph(stageId, cfg) {
  const errors = [];
  const warnings = [];
  const waypoints = cfg.waypoints ?? [];
  const edges = cfg.waypointEdges ?? [];
  const portals = cfg.portals ?? [];

  if (waypoints.length === 0) {
    return { errors: ["no waypoints"], warnings, stats: { waypoints: 0, edges: 0 } };
  }

  // Shape + uniqueness.
  const byId = new Map();
  for (const w of waypoints) {
    if (!w.id) { errors.push("waypoint with no id"); continue; }
    if (byId.has(w.id)) errors.push(`duplicate waypoint id ${w.id}`);
    const p = w.position;
    if (!Array.isArray(p) || p.length !== 3 || p.some((n) => typeof n !== "number" || !Number.isFinite(n))) {
      errors.push(`${w.id}: position is not three finite numbers`);
      continue;
    }
    byId.set(w.id, w);
  }

  // Edges reference real nodes, aren't self-loops, aren't repeated.
  const adj = new Map([...byId.keys()].map((id) => [id, new Set()]));
  const seenEdge = new Set();
  for (const e of edges) {
    if (!Array.isArray(e) || e.length !== 2) { errors.push(`malformed edge ${JSON.stringify(e)}`); continue; }
    const [a, b] = e;
    if (!byId.has(a) || !byId.has(b)) { errors.push(`edge references unknown node: ${a} → ${b}`); continue; }
    if (a === b) { errors.push(`self-loop on ${a}`); continue; }
    const key = a < b ? `${a}|${b}` : `${b}|${a}`;
    if (seenEdge.has(key)) { warnings.push(`duplicate edge ${a} ↔ ${b}`); continue; }
    seenEdge.add(key);
    adj.get(a).add(b);
    adj.get(b).add(a);
  }

  for (const [id, ns] of adj) {
    if (ns.size === 0) errors.push(`${id} is isolated (no edges)`);
  }

  const nodesOfKind = (kind) => waypoints.filter((w) => w.kind === kind && byId.has(w.id));

  if (portals.length > 0) {
    // Each portal needs its spawn/exit pair, and they must be joined.
    for (const portal of portals) {
      const o = OUTWARD[portal.direction];
      if (!o) { errors.push(`portal ${portal.id ?? portal.direction}: unknown direction`); continue; }
      const [gx, , gz] = portal.position;
      const at = (m) => [gx + o[0] * m, 0, gz + o[1] * m];
      const nearest = (kind, m) => {
        const target = at(m);
        let best = null;
        for (const w of nodesOfKind(kind)) {
          const d = dist2d(target, w.position);
          if (d <= OFFSET_TOL && (best === null || d < best.d)) best = { w, d };
        }
        return best?.w ?? null;
      };
      const spawn = nearest("spawn", SPAWN_OUTSET);
      const exit = nearest("exit", EXIT_OUTSET);
      const label = `portal ${portal.direction}`;
      if (!spawn) errors.push(`${label}: no 'spawn' node ${SPAWN_OUTSET}m outward from the gate — use "Seed from gates + spawn"`);
      if (!exit) errors.push(`${label}: no 'exit' node ${EXIT_OUTSET}m outward from the gate — use "Seed from gates + spawn"`);
      if (spawn && exit && !adj.get(spawn.id).has(exit.id)) {
        errors.push(`${label}: spawn and exit nodes are not connected by an edge`);
      }
    }
  } else {
    // Portal-less arena (boss room): needs a spawn on the default spawn
    // point and enough interior coverage to route a fight around.
    const spawns = nodesOfKind("spawn");
    if (spawns.length === 0) {
      errors.push("portal-less arena with no 'spawn' node — use \"Seed from gates + spawn\" to drop one on defaultSpawn");
    } else if (cfg.defaultSpawn?.position) {
      const d = Math.min(...spawns.map((w) => dist2d(cfg.defaultSpawn.position, w.position)));
      if (d > 3) warnings.push(`nearest spawn node is ${d.toFixed(1)}m from defaultSpawn`);
    }
    if (waypoints.length < 4) {
      warnings.push(`only ${waypoints.length} node(s) for an arena — s03z_na1 uses 16`);
    }
  }

  // Everything the autopilot navigates between must be mutually reachable.
  const anchors = waypoints.filter((w) => (w.kind === "spawn" || w.kind === "exit") && byId.has(w.id));
  if (anchors.length > 0) {
    const start = anchors[0].id;
    const seen = new Set([start]);
    const stack = [start];
    while (stack.length > 0) {
      for (const n of adj.get(stack.pop())) {
        if (!seen.has(n)) { seen.add(n); stack.push(n); }
      }
    }
    const stranded = anchors.filter((w) => !seen.has(w.id));
    if (stranded.length > 0) {
      errors.push(`unreachable from ${anchors[0].label ?? start}: ${stranded.map((w) => w.label ?? w.id).join(", ")}`);
    }
  }

  return { errors, warnings, stats: { waypoints: waypoints.length, edges: seenEdge.size } };
}

