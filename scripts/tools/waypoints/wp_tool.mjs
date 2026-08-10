#!/usr/bin/env node
// wp — waypoint authoring companion for the stage editor.
//
// The nav graphs the autopilot walks are hand-authored in the Vite stage
// editor (#/stage-editor?stage=<id>), which persists to the browser's
// localStorage — not to the repo. This script closes that loop:
//
//   todo   which field stages still have no graph, with editor URLs
//   paste  read the editor's "Copy JSON" payload off the clipboard and
//          merge it into data/stage_configs/unified-stage-configs.json
//   apply  same, but from files (per-stage export, or a bulk export)
//   check  validate every committed graph against the authoring conventions
//
// Conventions enforced by `check` were derived from the 218 stages that
// already ship a graph — every one of them satisfies these, so a new graph
// that doesn't is authored wrong, not merely unusual:
//   • Per portal: a `spawn` node 3m outward from the gate and an `exit`
//     node 7m outward, joined by an edge (matches the engine's spawn pose
//     and scene-change trigger — see valley_field_controller.gd).
//   • No orphan nodes; every spawn and exit reachable from every other.
//   • Portal-less boss arenas instead carry a `spawn` node on the config's
//     defaultSpawn plus a connected ring of interior points (s03z_na1 is
//     the reference).

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { validateGraph, AREA_NAMES, isFieldStage, areaOf } from "./validate_graph.mjs";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const CFG_PATH = join(REPO, "data", "stage_configs", "unified-stage-configs.json");
const BASELINE_PATH = join(REPO, "data", "stage_configs", "waypoint_coverage_baseline.json");

// Editor origin. The Vite dev server serves the SPA under /psz-godot/ —
// omitting the base path loads a blank page.
const EDITOR_BASE = process.env.WP_EDITOR_BASE ?? "http://localhost:5173";
const editorUrl = (stageId) => `${EDITOR_BASE}/psz-godot/#/stage-editor?stage=${stageId}`;

// ── config io ──────────────────────────────────────────────

function loadConfigs() {
  return JSON.parse(readFileSync(CFG_PATH, "utf8"));
}

// Round-trips byte-identically with the committed file, so a merge diffs
// only the stages it actually touched.
function writeConfigs(configs) {
  writeFileSync(CFG_PATH, JSON.stringify(configs, null, 2) + "\n");
}

// ── merging ────────────────────────────────────────────────

/**
 * Pull { mapId, waypoints, waypointEdges } records out of whatever the
 * editor handed us: the WaypointTab "Copy JSON" payload, a per-stage
 * `<mapId>_config.json` export, or a bulk `unified-stage-configs.json`.
 */
function extractGraphs(payload, sourceLabel) {
  const out = [];
  const take = (obj, id) => {
    const mapId = obj.mapId ?? id;
    if (!mapId || !Array.isArray(obj.waypoints)) return;
    out.push({ mapId, waypoints: obj.waypoints, waypointEdges: obj.waypointEdges ?? [] });
  };
  if (Array.isArray(payload)) {
    for (const entry of payload) take(entry);
  } else if (payload.mapId || Array.isArray(payload.waypoints)) {
    take(payload);
  } else {
    // Bulk export: a map of mapId → config.
    for (const [id, entry] of Object.entries(payload)) {
      if (entry && typeof entry === "object") take(entry, id);
    }
  }
  if (out.length === 0) throw new Error(`${sourceLabel}: no {mapId, waypoints} record found`);
  return out;
}

function mergeGraphs(graphs, { force, quiet } = {}) {
  const configs = loadConfigs();
  const applied = [];
  const skipped = [];

  for (const g of graphs) {
    const existing = configs[g.mapId];
    if (!existing) {
      skipped.push({ mapId: g.mapId, why: "not in unified-stage-configs.json" });
      continue;
    }
    if (g.waypoints.length === 0) {
      skipped.push({ mapId: g.mapId, why: "payload has zero waypoints" });
      continue;
    }
    const before = JSON.stringify([existing.waypoints ?? [], existing.waypointEdges ?? []]);
    const after = JSON.stringify([g.waypoints, g.waypointEdges]);
    if (before === after) {
      skipped.push({ mapId: g.mapId, why: "unchanged" });
      continue;
    }

    const candidate = { ...existing, waypoints: g.waypoints, waypointEdges: g.waypointEdges };
    const { errors, warnings, stats } = validateGraph(g.mapId, candidate);
    if (errors.length > 0 && !force) {
      skipped.push({ mapId: g.mapId, why: "failed validation", errors });
      continue;
    }

    candidate.lastModified = new Date().toISOString();
    configs[g.mapId] = candidate;
    applied.push({ mapId: g.mapId, stats, warnings, errors: force ? errors : [] });
  }

  if (applied.length > 0) writeConfigs(configs);

  if (!quiet) {
    for (const a of applied) {
      const flag = a.errors.length > 0 ? " ⚠ forced past validation" : "";
      console.log(`  ✓ ${a.mapId.padEnd(12)} ${String(a.stats.waypoints).padStart(3)} waypoints  ${String(a.stats.edges).padStart(3)} edges${flag}`);
      for (const e of a.errors) console.log(`      error: ${e}`);
      for (const w of a.warnings) console.log(`      warn:  ${w}`);
    }
    for (const s of skipped) {
      const icon = s.why === "unchanged" ? "◌" : "✗";
      console.log(`  ${icon} ${s.mapId.padEnd(12)} ${s.why}`);
      for (const e of s.errors ?? []) console.log(`      ${e}`);
    }
    if (skipped.some((s) => s.why === "failed validation")) {
      console.log("\n  Fix in the editor and re-copy, or re-run with --force to merge anyway.");
    }
  }

  return { applied, skipped };
}

// ── commands ───────────────────────────────────────────────

function missingStages(configs) {
  return Object.keys(configs)
    .filter((id) => isFieldStage(id))
    .filter((id) => (configs[id].waypoints ?? []).length === 0)
    .sort();
}

function cmdTodo(args) {
  const configs = loadConfigs();
  const areaFilter = argValue(args, "--area");
  const limit = Number(argValue(args, "--next") ?? 0);
  let missing = missingStages(configs);
  if (areaFilter) missing = missing.filter((id) => areaOf(id) === areaFilter);
  if (limit > 0) missing = missing.slice(0, limit);

  const total = missingStages(configs).length;
  const done = Object.keys(configs).filter((id) => isFieldStage(id)).length - total;
  console.log(`Waypoint coverage: ${done}/${done + total} field stages authored — ${total} to go\n`);

  let currentArea = null;
  for (const id of missing) {
    const area = areaOf(id);
    if (area !== currentArea) {
      currentArea = area;
      const areaTotal = missing.filter((m) => areaOf(m) === area).length;
      console.log(`\n${AREA_NAMES[area]} (${area}) — ${areaTotal} room${areaTotal === 1 ? "" : "s"}`);
    }
    const portals = configs[id].portals ?? [];
    const shape = portals.length === 0
      ? "arena (no portals — ring of points + default spawn)"
      : `${portals.length} portal${portals.length === 1 ? "" : "s"}: ${portals.map((p) => p.direction).join(", ")}`;
    console.log(`  ${id}  ${shape}`);
    console.log(`    ${editorUrl(id)}`);
  }
  if (missing.length === 0) console.log("Nothing left in scope. 🎉");
}

function cmdPaste(args) {
  let text;
  try {
    text = execFileSync("pbpaste", { encoding: "utf8" });
  } catch {
    console.error("Could not read the clipboard (pbpaste failed). Use: wp apply <file>");
    process.exit(1);
  }
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    console.error("Clipboard does not contain JSON. Click \"Copy JSON\" in the editor's Waypoints tab first.");
    process.exit(1);
  }
  console.log("From clipboard:");
  const { applied, skipped } = mergeGraphs(extractGraphs(payload, "clipboard"), { force: args.includes("--force") });
  reportNext(applied, skipped);
}

function cmdApply(args) {
  const files = args.filter((a) => !a.startsWith("--"));
  if (files.length === 0) {
    console.error("usage: wp apply <file.json> [more.json ...] [--force]");
    process.exit(1);
  }
  const graphs = [];
  for (const f of files) {
    if (!existsSync(f)) { console.error(`no such file: ${f}`); process.exit(1); }
    graphs.push(...extractGraphs(JSON.parse(readFileSync(f, "utf8")), f));
  }
  const { applied, skipped } = mergeGraphs(graphs, { force: args.includes("--force") });
  reportNext(applied, skipped);
}

function reportNext(applied, skipped) {
  if (applied.length === 0 && skipped.every((s) => s.why === "unchanged")) return;
  const remaining = missingStages(loadConfigs());
  console.log(`\n${remaining.length} stage${remaining.length === 1 ? "" : "s"} left.`);
  if (remaining.length > 0) console.log(`Next: ${remaining[0]}\n  ${editorUrl(remaining[0])}`);
}

function cmdCheck(args) {
  const configs = loadConfigs();
  const only = argValue(args, "--stage");
  const strict = args.includes("--strict");
  // Filter up front so the summary counts the same set it inspected — with
  // --stage it must not report on all 294.
  const ids = Object.keys(configs)
    .filter((id) => isFieldStage(id))
    .filter((id) => !only || id === only)
    .sort();
  if (only && ids.length === 0) {
    console.error(`no such field stage: ${only}`);
    process.exit(1);
  }

  let missing = 0;
  let bad = 0;
  let warned = 0;
  for (const id of ids) {
    const cfg = configs[id];
    if ((cfg.waypoints ?? []).length === 0) {
      missing++;
      if (only) console.log(`◌ ${id}: no waypoints yet`);
      continue;
    }
    const { errors, warnings, stats } = validateGraph(id, cfg);
    if (errors.length > 0) {
      bad++;
      console.log(`✗ ${id}  (${stats.waypoints} wpts, ${stats.edges} edges)`);
      for (const e of errors) console.log(`    ${e}`);
    } else if (warnings.length > 0) {
      warned++;
      console.log(`⚠ ${id}  (${stats.waypoints} wpts, ${stats.edges} edges)`);
      for (const w of warnings) console.log(`    ${w}`);
    } else if (only) {
      console.log(`✓ ${id}  (${stats.waypoints} wpts, ${stats.edges} edges)`);
    }
  }

  console.log(`\n${ids.length - missing}/${ids.length} field stages authored — ${bad} invalid, ${warned} with warnings, ${missing} not started`);
  process.exit(bad > 0 || (strict && missing > 0) ? 1 : 0);
}

// Rewrite the coverage baseline to the current set of unauthored stages.
// The vitest guard fails when a stage regresses OUT of coverage; this is how
// you record progress after authoring a batch.
function cmdBaseline() {
  const configs = loadConfigs();
  const missing = missingStages(configs);
  const invalid = Object.keys(configs)
    .filter((id) => isFieldStage(id) && (configs[id].waypoints ?? []).length > 0)
    .filter((id) => validateGraph(id, configs[id]).errors.length > 0)
    .sort();
  const prev = existsSync(BASELINE_PATH)
    ? JSON.parse(readFileSync(BASELINE_PATH, "utf8"))
    : { missing: [], invalid: [] };
  writeFileSync(BASELINE_PATH, JSON.stringify({
    comment: "Waypoint-coverage debt. `missing` = field stages with no authored nav graph; `invalid` = graphs that exist but violate the authoring contract. Both shrink as rooms are authored (docs/waypoint-authoring.md). web/src/__tests__/waypoint-coverage.test.ts fails if either grows — re-run `npm run wp:baseline` to record progress.",
    missing,
    invalid,
  }, null, 2) + "\n");
  const fixed = (prev.missing ?? []).filter((id) => !missing.includes(id));
  const repaired = (prev.invalid ?? []).filter((id) => !invalid.includes(id));
  console.log(`baseline: ${missing.length} missing (was ${(prev.missing ?? []).length}), ${invalid.length} invalid (was ${(prev.invalid ?? []).length})`);
  if (fixed.length > 0) console.log(`  authored since last update: ${fixed.join(", ")}`);
  if (repaired.length > 0) console.log(`  repaired since last update: ${repaired.join(", ")}`);
}

function argValue(args, flag) {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
}

// Importable as a module (the vitest coverage guard reuses validateGraph);
// the CLI only runs when this file is the entry point.
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
const [cmd, ...rest] = process.argv.slice(2);
if (isMain) switch (cmd) {
  case "todo": cmdTodo(rest); break;
  case "paste": cmdPaste(rest); break;
  case "apply": cmdApply(rest); break;
  case "check": cmdCheck(rest); break;
  case "baseline": cmdBaseline(rest); break;
  default:
    console.error(`usage: node scripts/tools/waypoints/wp_tool.mjs <command>

  todo [--area s02] [--next 5]   stages still needing a graph, with editor URLs
  paste [--force]                merge the editor's "Copy JSON" payload from the clipboard
  apply <file...> [--force]      merge from exported JSON files
  check [--stage <id>] [--strict]  validate committed graphs
  baseline                       record current coverage in the CI baseline

  WP_EDITOR_BASE overrides the editor origin (default ${EDITOR_BASE}).`);
    process.exit(1);
}
