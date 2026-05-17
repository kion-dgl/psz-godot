#!/usr/bin/env bun
// Mobile-friendly quest editor — Bun-served SPA that edits data/quests/*.json directly.
// Designed for phone use over Tailscale. Bind 0.0.0.0.
//
// Run:  bun tools/mobile-quest-editor/server.ts
// URL:  http://100.89.189.126:4200

import { readdir, readFile, writeFile, stat } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..", "..");
const QUEST_DIR = join(REPO_ROOT, "data", "quests");
const STAGES_DIR = join(REPO_ROOT, "assets", "stages");
const PORT = 4200;

// --- helpers --------------------------------------------------------------

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function text(s: string, status = 200, contentType = "text/plain") {
  return new Response(s, { status, headers: { "Content-Type": contentType } });
}

type QuestSummary = {
  id: string;
  name: string;
  area_id: string;
  parent_quest: string | null;
  required_quests: string[];
  disabled: boolean;
  section_count: number;
  cell_count: number;
  depth: number;
};

async function listQuests(): Promise<QuestSummary[]> {
  const files = await readdir(QUEST_DIR);
  const summaries: QuestSummary[] = [];
  // Optional manifest ordering — quests not in manifest fall to the end.
  let manifestOrder: string[] = [];
  try {
    const m = JSON.parse(await readFile(join(QUEST_DIR, "manifest.json"), "utf8"));
    if (Array.isArray(m)) manifestOrder = m;
  } catch {
    // no manifest — fine
  }
  const manifestIdx = (id: string) => {
    const i = manifestOrder.indexOf(id);
    return i === -1 ? Number.MAX_SAFE_INTEGER : i;
  };

  for (const f of files) {
    if (!f.endsWith(".json")) continue;
    if (f === "manifest.json") continue;
    const raw = await readFile(join(QUEST_DIR, f), "utf8");
    let q: any;
    try {
      q = JSON.parse(raw);
    } catch {
      continue;
    }
    if (!q?.id) continue;
    const sections = Array.isArray(q.sections) ? q.sections : [];
    summaries.push({
      id: q.id,
      name: q.name ?? q.id,
      area_id: q.area_id ?? "",
      parent_quest: q.parent_quest ?? null,
      required_quests: Array.isArray(q.required_quests) ? q.required_quests : [],
      disabled: q.disabled === true,
      section_count: sections.length,
      cell_count: sections.reduce(
        (s: number, sec: any) => s + (sec.cells?.length ?? 0),
        0,
      ),
      depth: 0,
    });
  }

  // DFS tree sort: roots first (parent missing or null), siblings in manifest
  // order, depth tracked per node. Orphans (parent points to nonexistent
  // quest) are treated as roots so they remain visible.
  const byId = new Map<string, QuestSummary>(summaries.map(s => [s.id, s]));
  const childrenOf = new Map<string, QuestSummary[]>();
  childrenOf.set("", []);
  for (const s of summaries) {
    const pid = s.parent_quest && byId.has(s.parent_quest) ? s.parent_quest : "";
    if (!childrenOf.has(pid)) childrenOf.set(pid, []);
    childrenOf.get(pid)!.push(s);
  }
  for (const kids of childrenOf.values()) {
    kids.sort((a, b) => {
      const ai = manifestIdx(a.id);
      const bi = manifestIdx(b.id);
      if (ai !== bi) return ai - bi;
      return a.id.localeCompare(b.id);
    });
  }
  const out: QuestSummary[] = [];
  const stack: Array<{ node: QuestSummary; depth: number }> = [];
  const roots = childrenOf.get("") ?? [];
  for (let i = roots.length - 1; i >= 0; i--) stack.push({ node: roots[i], depth: 0 });
  while (stack.length) {
    const { node, depth } = stack.pop()!;
    node.depth = depth;
    out.push(node);
    const kids = childrenOf.get(node.id) ?? [];
    for (let i = kids.length - 1; i >= 0; i--) stack.push({ node: kids[i], depth: depth + 1 });
  }
  return out;
}

async function loadQuest(qid: string) {
  const path = join(QUEST_DIR, `${qid}.json`);
  const raw = await readFile(path, "utf8");
  return JSON.parse(raw);
}

async function saveQuest(qid: string, data: unknown) {
  const path = join(QUEST_DIR, `${qid}.json`);
  // sanity: must have matching id
  if ((data as any)?.id !== qid) {
    throw new Error(`id mismatch: payload.id=${(data as any)?.id} path=${qid}`);
  }
  await writeFile(path, JSON.stringify(data, null, 2) + "\n", "utf8");
}

async function listStagesByArea() {
  // Each direct subdir of assets/stages is an "area" folder (e.g. tower_0,
  // shrine_a, arca_a). Inside each is one or more stage_id directories
  // (e.g. s080_sa0). We expose { areaFolder: [stage_id, ...] }.
  const out: Record<string, string[]> = {};
  let areas: string[] = [];
  try {
    areas = await readdir(STAGES_DIR);
  } catch {
    return out;
  }
  for (const a of areas) {
    const aPath = join(STAGES_DIR, a);
    try {
      const s = await stat(aPath);
      if (!s.isDirectory()) continue;
      const children = await readdir(aPath);
      const stages: string[] = [];
      for (const c of children) {
        const cPath = join(aPath, c);
        try {
          const cs = await stat(cPath);
          if (cs.isDirectory()) stages.push(c);
        } catch {
          // ignore
        }
      }
      stages.sort();
      out[a] = stages;
    } catch {
      // ignore
    }
  }
  return out;
}

// NPC list — read from web/src/quest-editor/types.ts and parse the
// AVAILABLE_NPCS-style declarations. Fall back to a static list if unparseable.
async function listNpcs() {
  const fallback = [
    { id: "kai", name: "Kai" },
    { id: "sarisa", name: "Sarisa" },
    { id: "elio", name: "Elio" },
    { id: "dorn", name: "Dorn" },
    { id: "ren", name: "Ren" },
    { id: "fern", name: "Fern" },
    { id: "dr_carlo", name: "Dr. Carlo" },
    { id: "mira", name: "Mira" },
    { id: "ana", name: "Ana" },
  ];
  try {
    const path = join(REPO_ROOT, "web", "src", "quest-editor", "types.ts");
    const raw = await readFile(path, "utf8");
    const re = /\{\s*id:\s*['"]([a-z0-9_]+)['"]\s*,\s*name:\s*['"]([^'"]+)['"]\s*\}/g;
    const seen = new Set<string>();
    const out: Array<{ id: string; name: string }> = [];
    let m: RegExpExecArray | null;
    while ((m = re.exec(raw))) {
      if (!seen.has(m[1])) {
        seen.add(m[1]);
        out.push({ id: m[1], name: m[2] });
      }
    }
    return out.length ? out : fallback;
  } catch {
    return fallback;
  }
}

// --- server ---------------------------------------------------------------

const server = Bun.serve({
  port: PORT,
  hostname: "0.0.0.0",
  async fetch(req) {
    const url = new URL(req.url);
    const p = url.pathname;

    try {
      if (p === "/" || p === "/index.html") return text(INDEX_HTML, 200, "text/html; charset=utf-8");
      if (p === "/api/quests" && req.method === "GET") return json(await listQuests());
      if (p === "/api/stages" && req.method === "GET") return json(await listStagesByArea());
      if (p === "/api/npcs" && req.method === "GET") return json(await listNpcs());

      const questMatch = p.match(/^\/api\/quests\/([a-z0-9_]+)$/);
      if (questMatch) {
        const qid = questMatch[1];
        if (req.method === "GET") return json(await loadQuest(qid));
        if (req.method === "PUT") {
          const body = await req.json();
          await saveQuest(qid, body);
          return json({ ok: true, id: qid });
        }
      }

      return text("not found", 404);
    } catch (e: any) {
      console.error(`[${req.method}] ${p}`, e);
      return json({ error: String(e?.message ?? e) }, 500);
    }
  },
});

console.log(`Mobile quest editor on http://0.0.0.0:${server.port}`);
console.log(`Tailscale:  http://100.89.189.126:${server.port}`);

// --- frontend -------------------------------------------------------------

const INDEX_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>Quest Editor</title>
<style>
  :root {
    --bg: #1a1a1f;
    --panel: #25252d;
    --panel-2: #2f2f38;
    --border: #3a3a45;
    --text: #e8e8ed;
    --text-dim: #9a9aa8;
    --accent: #6ea8ff;
    --danger: #ff7676;
    --ok: #7ed87e;
    --warn: #f5c46a;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; background: var(--bg); color: var(--text); font: 16px/1.4 system-ui, -apple-system, sans-serif; }
  body { padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left); }
  a { color: var(--accent); }
  button {
    background: var(--panel-2);
    color: var(--text);
    border: 1px solid var(--border);
    padding: 12px 16px;
    border-radius: 8px;
    font-size: 16px;
    min-height: 44px;
    cursor: pointer;
  }
  button:active { background: var(--panel); }
  button.primary { background: var(--accent); color: #002040; border-color: var(--accent); font-weight: 600; }
  button.danger  { background: var(--danger); color: #2a0000; border-color: var(--danger); }
  button.ghost   { background: transparent; }
  input, select, textarea {
    background: var(--panel-2);
    color: var(--text);
    border: 1px solid var(--border);
    padding: 12px;
    border-radius: 8px;
    font-size: 16px;
    width: 100%;
  }
  textarea { font-family: inherit; min-height: 80px; resize: vertical; }
  header {
    position: sticky; top: 0; z-index: 10;
    background: var(--panel);
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    display: flex; align-items: center; gap: 12px;
  }
  header h1 { font-size: 18px; margin: 0; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  header button { padding: 8px 12px; min-height: 36px; font-size: 14px; }
  main { padding: 16px; }
  .row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  .row > * { flex: 1; }
  .brief-line-row > select { flex: 1 1 auto; }
  .brief-line-row > button { flex: 0 0 44px; min-width: 44px; padding: 8px; }
  .office-npc-row > select { flex: 2 1 auto; }
  .office-npc-row > input { flex: 1 1 70px; }
  .office-npc-row > button { flex: 0 0 44px; min-width: 44px; padding: 8px; }
  .brief-line { margin-bottom: 10px; }
  .stack { display: flex; flex-direction: column; gap: 12px; }
  .card {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 14px;
  }
  .card h2 { margin: 0 0 8px; font-size: 16px; }
  .meta { font-size: 13px; color: var(--text-dim); }
  .badge {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--panel-2);
    font-size: 12px;
    color: var(--text-dim);
    margin-left: 6px;
  }
  .badge.warn { background: #4a3a1a; color: var(--warn); }
  .badge.ok   { background: #1a3a2a; color: var(--ok); }
  /* Nested-UL tree. Each li::before draws the horizontal elbow into the
     node, and each ul (except the root) carries a left border that becomes
     the vertical trunk down to its children. */
  .tree, .tree ul {
    list-style: none;
    padding: 0;
    margin: 0;
  }
  .tree ul {
    margin-left: 14px;
    padding-left: 14px;
    border-left: 1.5px solid var(--border);
  }
  .tree li {
    position: relative;
    padding: 6px 0;
  }
  /* Horizontal elbow connecting trunk → node. Only on nested items. */
  .tree ul > li::before {
    content: "";
    position: absolute;
    left: -14px;
    top: 22px;
    width: 12px;
    border-top: 1.5px solid var(--border);
  }
  /* Last child: trim the trunk so it stops at this child's elbow. */
  .tree ul > li:last-child::after {
    content: "";
    position: absolute;
    left: -15.5px;
    top: 22px;
    bottom: -7px;
    width: 1.5px;
    background: var(--bg);
  }
  .node {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 10px 12px;
    cursor: pointer;
    display: block;
    min-height: 44px;
  }
  .node:active { background: var(--panel-2); }
  .node .name { font-size: 15px; font-weight: 600; display: flex; align-items: center; flex-wrap: wrap; gap: 6px; }
  .node .meta { font-size: 12px; color: var(--text-dim); margin-top: 2px; }
  .node.disabled { opacity: 0.6; }
  .grid-wrap { overflow: auto; padding: 8px; background: var(--panel-2); border-radius: 8px; }
  .grid { display: grid; gap: 6px; justify-content: start; }
  .cell {
    width: 70px; height: 70px;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    font-size: 10px; text-align: center;
    cursor: pointer;
    padding: 4px;
    position: relative;
    overflow: hidden;
  }
  .cell.start { border-color: var(--ok); }
  .cell.end   { border-color: var(--accent); }
  .cell.gate  { border-color: var(--warn); }
  .cell.empty {
    background: transparent;
    border-style: dashed;
    color: var(--text-dim);
  }
  .cell .pos   { font-size: 9px; color: var(--text-dim); position: absolute; top: 2px; left: 4px; }
  .cell .sid   { font-size: 10px; word-break: break-all; }
  .cell .flags { position: absolute; top: 2px; right: 4px; font-size: 9px; color: var(--warn); }
  .modal-backdrop {
    position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: flex; align-items: flex-end;
    z-index: 100;
  }
  .modal {
    background: var(--bg); width: 100%; max-height: 90vh; overflow-y: auto;
    border-top-left-radius: 16px; border-top-right-radius: 16px;
    padding: 16px;
  }
  .modal h3 { margin-top: 0; }
  label { display: block; margin-bottom: 6px; font-size: 13px; color: var(--text-dim); }
  .field { margin-bottom: 14px; }
  .toggle-row { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; }
  .toggle-row label {
    display: flex; align-items: center; gap: 8px;
    background: var(--panel-2); padding: 10px; border-radius: 8px;
    font-size: 14px; color: var(--text);
    cursor: pointer;
  }
  .toggle-row input[type=checkbox] { width: auto; margin: 0; }
  .toast {
    position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%);
    background: var(--panel); border: 1px solid var(--border); padding: 12px 16px;
    border-radius: 8px; z-index: 200; opacity: 0; transition: opacity 0.2s;
    pointer-events: none;
  }
  .toast.show { opacity: 1; }
  .toast.ok { border-color: var(--ok); }
  .toast.err { border-color: var(--danger); }
  details > summary { cursor: pointer; padding: 8px 0; font-weight: 600; }
  .conn-row { display: grid; grid-template-columns: 60px 1fr; gap: 8px; align-items: center; margin-bottom: 8px; }
  .conn-row label { margin: 0; }
  .dialog-line {
    display: grid; grid-template-columns: 90px 1fr auto; gap: 6px; margin-bottom: 6px;
  }
  .dialog-line button { padding: 6px 10px; min-height: 36px; }
</style>
</head>
<body>
<header>
  <button id="back" class="ghost" style="display:none">← Back</button>
  <h1 id="title">Quests</h1>
  <button id="save" class="primary" style="display:none">Save</button>
</header>
<main id="app"></main>
<div id="toast" class="toast"></div>

<script>
"use strict";

// --- state ---------------------------------------------------------------
const state = {
  view: "list",           // "list" | "quest" | "section"
  quests: [],
  stagesByArea: {},
  npcs: [],
  currentQuest: null,
  currentQuestDirty: false,
  currentSectionIdx: 0,
  editingCellIdx: null,   // index into section.cells, or null
  history: [],            // back-stack of {view, sectionIdx}
};

// --- api -----------------------------------------------------------------
async function api(path, opts = {}) {
  const r = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...opts,
  });
  if (!r.ok) {
    const txt = await r.text().catch(() => "");
    throw new Error(\`\${r.status} \${r.statusText}: \${txt}\`);
  }
  return r.json();
}

// --- toast ---------------------------------------------------------------
function toast(msg, kind = "ok") {
  const t = document.getElementById("toast");
  t.textContent = msg;
  t.className = \`toast show \${kind}\`;
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => { t.className = "toast"; }, 2200);
}

// --- helpers -------------------------------------------------------------
function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") e.className = v;
    else if (k === "style") e.style.cssText = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (v === false || v == null) continue;
    else if (v === true) e.setAttribute(k, "");
    else e.setAttribute(k, v);
  }
  for (const c of children) {
    if (c == null || c === false) continue;
    e.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
  }
  return e;
}

function parsePos(s) {
  if (!s) return [0, 0];
  const [x, y] = s.split(",").map(n => parseInt(n, 10));
  return [Number.isNaN(x) ? 0 : x, Number.isNaN(y) ? 0 : y];
}
function fmtPos(x, y) { return \`\${x},\${y}\`; }

function setDirty(v) {
  state.currentQuestDirty = v;
  const save = document.getElementById("save");
  save.style.display = state.view !== "list" && state.currentQuest ? "" : "none";
  save.textContent = v ? "Save *" : "Save";
}

function pushHistory() {
  state.history.push({ view: state.view, sectionIdx: state.currentSectionIdx });
}
function goBack() {
  if (state.history.length === 0) {
    if (state.currentQuestDirty && !confirm("Discard unsaved changes?")) return;
    state.view = "list";
    state.currentQuest = null;
    state.currentQuestDirty = false;
    render();
    return;
  }
  const prev = state.history.pop();
  state.view = prev.view;
  state.currentSectionIdx = prev.sectionIdx;
  render();
}

// --- rendering -----------------------------------------------------------
function render() {
  const app = document.getElementById("app");
  app.innerHTML = "";
  const title = document.getElementById("title");
  const back = document.getElementById("back");
  const save = document.getElementById("save");

  back.style.display = state.view === "list" ? "none" : "";
  save.style.display = state.view !== "list" && state.currentQuest ? "" : "none";
  save.textContent = state.currentQuestDirty ? "Save *" : "Save";

  if (state.view === "list") {
    title.textContent = "Quests";
    app.appendChild(renderList());
  } else if (state.view === "quest") {
    title.textContent = state.currentQuest?.name ?? state.currentQuest?.id ?? "Quest";
    app.appendChild(renderQuest());
  } else if (state.view === "section") {
    const s = state.currentQuest.sections[state.currentSectionIdx];
    title.textContent = \`\${state.currentQuest.name} — Section \${s?.area ?? state.currentSectionIdx}\`;
    app.appendChild(renderSection());
  }
}

function renderList() {
  // Build children map from the flat DFS list (parent_quest fields).
  const byId = new Map();
  for (const q of state.quests) byId.set(q.id, q);
  const childrenOf = new Map();
  const roots = [];
  for (const q of state.quests) {
    const pid = q.parent_quest && byId.has(q.parent_quest) ? q.parent_quest : null;
    if (!pid) roots.push(q);
    else {
      if (!childrenOf.has(pid)) childrenOf.set(pid, []);
      childrenOf.get(pid).push(q);
    }
  }

  function renderNode(q) {
    const kids = childrenOf.get(q.id) ?? [];
    const li = el("li", {});
    const cls = q.disabled ? "node disabled" : "node";
    const card = el("div",
      { class: cls, onclick: () => openQuest(q.id) },
      el("div", { class: "name" },
        q.name,
        q.disabled ? el("span", { class: "badge warn" }, "disabled") : null,
      ),
      el("div", { class: "meta" },
        \`\${q.area_id || "—"} · \${q.section_count} sec · \${q.cell_count} cells\`,
      ),
      q.required_quests?.length
        ? el("div", { class: "meta" }, \`requires: \${q.required_quests.join(", ")}\`)
        : null,
    );
    li.appendChild(card);
    if (kids.length) {
      const ul = el("ul", {});
      for (const k of kids) ul.appendChild(renderNode(k));
      li.appendChild(ul);
    }
    return li;
  }

  const rootUl = el("ul", { class: "tree" });
  for (const r of roots) rootUl.appendChild(renderNode(r));
  return rootUl;
}

async function openQuest(qid) {
  try {
    const q = await api(\`/api/quests/\${qid}\`);
    state.currentQuest = q;
    state.currentQuestDirty = false;
    state.history = [];
    state.view = "quest";
    render();
  } catch (e) {
    toast("load failed: " + e.message, "err");
  }
}

function renderQuest() {
  const q = state.currentQuest;
  const wrap = el("div", { class: "stack" });

  // metadata card
  const meta = el("div", { class: "card stack" });
  meta.appendChild(el("h2", {}, "Metadata"));
  meta.appendChild(field("Name", el("input", {
    type: "text", value: q.name ?? "",
    oninput: e => { q.name = e.target.value; setDirty(true); },
  })));
  meta.appendChild(field("Description", el("textarea", {
    oninput: e => { q.description = e.target.value; setDirty(true); },
  }, q.description ?? "")));
  meta.appendChild(field("Area ID", el("input", {
    type: "text", value: q.area_id ?? "",
    oninput: e => { q.area_id = e.target.value; setDirty(true); },
  })));
  meta.appendChild(field("Parent quest", el("input", {
    type: "text", value: q.parent_quest ?? "",
    placeholder: "(none)",
    oninput: e => { q.parent_quest = e.target.value || null; setDirty(true); },
  })));
  meta.appendChild(field("Required quests (comma)",
    el("input", {
      type: "text",
      value: (q.required_quests ?? []).join(", "),
      placeholder: "(none)",
      oninput: e => {
        q.required_quests = e.target.value.split(",").map(s => s.trim()).filter(Boolean);
        setDirty(true);
      },
    })));
  meta.appendChild(field("",
    el("label", { class: "toggle-row" },
      el("input", {
        type: "checkbox", checked: q.disabled === true,
        onchange: e => { q.disabled = e.target.checked; setDirty(true); },
      }),
      "Disabled (beta / hidden in alpha)",
    )));
  wrap.appendChild(meta);

  // briefing dialog card — the opening dialog the player sees
  const briefCard = el("div", { class: "card stack" });
  briefCard.appendChild(el("h2", {}, "Opening Dialog"));
  q.briefing_dialog = q.briefing_dialog ?? [];
  q.briefing_dialog.forEach((line, i) => {
    const speakers = ["", "Principal", ...state.npcs.map(n => n.name)];
    if (line.speaker && !speakers.includes(line.speaker)) speakers.push(line.speaker);
    const speakerSelect = el("select", {
      onchange: e => { line.speaker = e.target.value; setDirty(true); },
    });
    for (const s of speakers) {
      const o = el("option", { value: s }, s || "(speaker)");
      if (line.speaker === s) o.setAttribute("selected", "");
      speakerSelect.appendChild(o);
    }
    briefCard.appendChild(el("div", { class: "brief-line stack" },
      el("div", { class: "row brief-line-row" },
        speakerSelect,
        el("button", { onclick: () => {
          if (i > 0) {
            const arr = q.briefing_dialog;
            [arr[i-1], arr[i]] = [arr[i], arr[i-1]];
            setDirty(true); render();
          }
        } }, "↑"),
        el("button", { onclick: () => {
          if (i < q.briefing_dialog.length - 1) {
            const arr = q.briefing_dialog;
            [arr[i+1], arr[i]] = [arr[i], arr[i+1]];
            setDirty(true); render();
          }
        } }, "↓"),
        el("button", { class: "danger", onclick: () => {
          if (!confirm("Delete this line?")) return;
          q.briefing_dialog.splice(i, 1);
          setDirty(true); render();
        } }, "✕"),
      ),
      el("textarea", {
        rows: 2,
        oninput: e => { line.text = e.target.value; setDirty(true); },
      }, line.text ?? ""),
    ));
  });
  briefCard.appendChild(el("button", { onclick: () => {
    q.briefing_dialog = q.briefing_dialog ?? [];
    q.briefing_dialog.push({ speaker: "", text: "" });
    setDirty(true); render();
  } }, "+ Add line"));
  wrap.appendChild(briefCard);

  // NPCs card — office NPCs (in guild office) + companions (join the party)
  const npcCard = el("div", { class: "card stack" });
  npcCard.appendChild(el("h2", {}, "NPCs"));
  q.office_npcs = q.office_npcs ?? [];
  npcCard.appendChild(el("label", {}, "Office NPCs (visible in guild office)"));
  q.office_npcs.forEach((o, i) => {
    const npcSelect = el("select", {
      onchange: e => {
        const npc = state.npcs.find(n => n.id === e.target.value);
        o.npc_id = e.target.value;
        o.npc_name = npc?.name ?? e.target.value;
        setDirty(true);
      },
    });
    npcSelect.appendChild(el("option", { value: "" }, "(pick NPC)"));
    for (const n of state.npcs) {
      const opt = el("option", { value: n.id }, n.name);
      if (o.npc_id === n.id) opt.setAttribute("selected", "");
      npcSelect.appendChild(opt);
    }
    npcCard.appendChild(el("div", { class: "row office-npc-row" },
      npcSelect,
      el("input", {
        type: "text",
        value: o.office_position ?? "",
        placeholder: "pos_1",
        oninput: e => { o.office_position = e.target.value; setDirty(true); },
      }),
      el("button", { class: "danger", onclick: () => {
        q.office_npcs.splice(i, 1);
        setDirty(true); render();
      } }, "✕"),
    ));
  });
  npcCard.appendChild(el("button", { onclick: () => {
    const pos = "pos_" + (q.office_npcs.length + 1);
    q.office_npcs.push({ npc_id: "", npc_name: "", office_position: pos });
    setDirty(true); render();
  } }, "+ Add office NPC"));

  q.companions = q.companions ?? [];
  npcCard.appendChild(el("label", { style: "margin-top: 14px;" }, "Quest companions (join the party in-quest)"));
  const compToggles = el("div", { class: "toggle-row" });
  for (const n of state.npcs) {
    compToggles.appendChild(el("label", {},
      el("input", {
        type: "checkbox",
        checked: q.companions.includes(n.id),
        onchange: e => {
          if (e.target.checked) {
            if (!q.companions.includes(n.id)) q.companions.push(n.id);
          } else {
            q.companions = q.companions.filter(x => x !== n.id);
          }
          setDirty(true);
        },
      }),
      n.name,
    ));
  }
  npcCard.appendChild(compToggles);
  wrap.appendChild(npcCard);

  // Clear condition (derived from is_end cells in sections)
  const clearCard = el("div", { class: "card stack" });
  clearCard.appendChild(el("h2", {}, "Clear Condition"));
  const sectionsArr = q.sections ?? [];
  const endCells = [];
  sectionsArr.forEach((sec, si) => {
    (sec.cells ?? []).forEach(c => {
      if (c.is_end) {
        const dialogLines = (c.objects ?? [])
          .filter(o => o.type === "dialog_trigger")
          .flatMap(o => o.dialog ?? [])
          .map(d => (d.speaker ? d.speaker + ": " : "") + (d.text ?? ""));
        endCells.push({ sec: sec.area ?? si, pos: c.pos, dialog: dialogLines });
      }
    });
  });
  if (endCells.length === 0) {
    clearCard.appendChild(el("div", { class: "meta" },
      "No end cell marked. In the section editor, mark a cell as 'End' to define quest completion."));
  } else {
    for (const ec of endCells) {
      const block = el("div", { class: "card", style: "background: var(--panel-2);" },
        el("strong", {}, \`Section \${ec.sec} → ends at \${ec.pos}\`),
      );
      if (ec.dialog.length) {
        for (const d of ec.dialog) {
          block.appendChild(el("div", { class: "meta" }, d));
        }
      } else {
        block.appendChild(el("div", { class: "meta" }, "(no end-cell dialog yet)"));
      }
      clearCard.appendChild(block);
    }
  }
  wrap.appendChild(clearCard);

  // sections card
  const secs = el("div", { class: "card stack" });
  secs.appendChild(el("h2", {}, "Sections"));
  (q.sections ?? []).forEach((s, i) => {
    const cellCount = (s.cells ?? []).length;
    secs.appendChild(el("div",
      { class: "card", style: "background: var(--panel-2);", onclick: () => openSection(i) },
      el("strong", {}, \`Section \${s.area ?? i}\`),
      el("div", { class: "meta" }, \`\${cellCount} cells · start \${s.start_pos ?? "?"} → end \${s.end_pos ?? "?"}\`),
    ));
  });
  secs.appendChild(el("button", { onclick: addSection }, "+ Add Section"));
  wrap.appendChild(secs);

  return wrap;
}

function field(label, input) {
  return el("div", { class: "field" }, el("label", {}, label), input);
}

function addSection() {
  const q = state.currentQuest;
  q.sections = q.sections ?? [];
  const nextLetter = String.fromCharCode("a".charCodeAt(0) + q.sections.length);
  q.sections.push({
    type: "grid",
    area: nextLetter,
    start_pos: "0,0",
    end_pos: "0,0",
    cells: [],
  });
  setDirty(true);
  render();
}

function openSection(idx) {
  pushHistory();
  state.view = "section";
  state.currentSectionIdx = idx;
  render();
}

function renderSection() {
  const q = state.currentQuest;
  const sec = q.sections[state.currentSectionIdx];
  const cells = sec.cells ?? [];
  const wrap = el("div", { class: "stack" });

  // section meta
  const meta = el("div", { class: "card stack" });
  meta.appendChild(el("h2", {}, "Section " + (sec.area ?? "")));
  meta.appendChild(field("Area letter", el("input", {
    type: "text", value: sec.area ?? "",
    oninput: e => { sec.area = e.target.value; setDirty(true); },
  })));
  meta.appendChild(el("div", { class: "row" },
    el("div", { class: "field" },
      el("label", {}, "Start pos"),
      el("input", { type: "text", value: sec.start_pos ?? "", oninput: e => { sec.start_pos = e.target.value; setDirty(true); } })),
    el("div", { class: "field" },
      el("label", {}, "End pos"),
      el("input", { type: "text", value: sec.end_pos ?? "", oninput: e => { sec.end_pos = e.target.value; setDirty(true); } })),
  ));
  wrap.appendChild(meta);

  // grid
  const gridCard = el("div", { class: "card" });
  gridCard.appendChild(el("h2", {}, "Cells (tap to edit, tap empty to add)"));

  // bounds
  let minX = 0, maxX = 0, minY = 0, maxY = 0;
  cells.forEach(c => {
    const [x, y] = parsePos(c.pos);
    minX = Math.min(minX, x); maxX = Math.max(maxX, x);
    minY = Math.min(minY, y); maxY = Math.max(maxY, y);
  });
  // pad by 1 on each side
  minX--; maxX++; minY--; maxY++;
  const cols = maxX - minX + 1;
  const rows = maxY - minY + 1;

  const grid = el("div", {
    class: "grid",
    style: \`grid-template-columns: repeat(\${cols}, 70px); grid-template-rows: repeat(\${rows}, 70px);\`,
  });

  const cellByPos = new Map();
  cells.forEach((c, i) => cellByPos.set(c.pos, { c, i }));

  // render row by row, top to bottom — Y axis grows downward visually
  for (let y = minY; y <= maxY; y++) {
    for (let x = minX; x <= maxX; x++) {
      const posKey = fmtPos(x, y);
      const existing = cellByPos.get(posKey);
      if (existing) {
        const { c, i } = existing;
        const classes = ["cell"];
        if (c.is_start) classes.push("start");
        if (c.is_end) classes.push("end");
        if (c.is_key_gate) classes.push("gate");
        const flags = [];
        if (c.is_start) flags.push("S");
        if (c.is_end) flags.push("E");
        if (c.is_key_gate) flags.push("G");
        if (c.has_key) flags.push("K");
        grid.appendChild(el("div",
          {
            class: classes.join(" "),
            onclick: () => openCell(i),
          },
          el("span", { class: "pos" }, posKey),
          el("span", { class: "sid" }, c.stage_id || "(none)"),
          flags.length ? el("span", { class: "flags" }, flags.join("")) : null,
        ));
      } else {
        grid.appendChild(el("div",
          {
            class: "cell empty",
            onclick: () => addCellAt(posKey),
          },
          el("span", { class: "pos" }, posKey),
          el("span", { class: "sid" }, "+"),
        ));
      }
    }
  }
  const gridWrap = el("div", { class: "grid-wrap" }, grid);
  gridCard.appendChild(gridWrap);
  wrap.appendChild(gridCard);

  return wrap;
}

function addCellAt(pos) {
  const sec = state.currentQuest.sections[state.currentSectionIdx];
  sec.cells = sec.cells ?? [];
  sec.cells.push({
    pos,
    stage_id: "",
    rotation: 0,
    connections: {},
    portals: {},
    is_start: false,
    is_end: false,
    is_branch: false,
    has_key: false,
    key_for_cell: "",
    is_key_gate: false,
    key_gate_direction: "",
    key_drop: "",
    required_keys: 0,
    warp_edge: "",
    path_order: 0,
    objects: [],
  });
  setDirty(true);
  openCell(sec.cells.length - 1);
}

function openCell(idx) {
  state.editingCellIdx = idx;
  showCellModal();
}

function closeModal() {
  const m = document.getElementById("modal");
  if (m) m.remove();
  state.editingCellIdx = null;
}

function showCellModal() {
  const sec = state.currentQuest.sections[state.currentSectionIdx];
  const cell = sec.cells[state.editingCellIdx];
  if (!cell) return;

  // figure stages for this section's area letter
  // the stage_id pattern is sNN_AREA_VARIANT — we just present all stages
  // grouped by area folder. For convenience, surface ones matching the
  // current quest area_id first.
  const qArea = state.currentQuest.area_id ?? "";
  const allFolders = Object.keys(state.stagesByArea).sort();
  // Folders whose name starts with the quest area (e.g. "tower" → "tower_0".."tower_e")
  const preferred = allFolders.filter(f => f.startsWith(qArea));
  const ordered = preferred.length ? [...preferred, ...allFolders.filter(f => !preferred.includes(f))] : allFolders;

  const stageSelect = el("select", {
    onchange: e => { cell.stage_id = e.target.value; setDirty(true); },
  });
  stageSelect.appendChild(el("option", { value: "" }, "(pick a stage)"));
  for (const folder of ordered) {
    const stages = state.stagesByArea[folder] ?? [];
    const grp = el("optgroup", { label: folder });
    for (const s of stages) {
      const o = el("option", { value: s }, s);
      if (cell.stage_id === s) o.setAttribute("selected", "");
      grp.appendChild(o);
    }
    if (stages.length) stageSelect.appendChild(grp);
  }
  // if cell.stage_id is set but not present in any group (e.g. custom), add it
  if (cell.stage_id && !Array.from(stageSelect.querySelectorAll("option")).some(o => o.value === cell.stage_id)) {
    const o = el("option", { value: cell.stage_id, selected: true }, cell.stage_id + " (custom)");
    stageSelect.insertBefore(o, stageSelect.firstChild.nextSibling);
  }

  const rotSelect = el("select", {
    onchange: e => { cell.rotation = parseInt(e.target.value, 10); setDirty(true); },
  });
  for (const r of [0, 90, 180, 270]) {
    const o = el("option", { value: String(r) }, r + "°");
    if ((cell.rotation ?? 0) === r) o.setAttribute("selected", "");
    rotSelect.appendChild(o);
  }

  const flag = (key, label) => el("label", {},
    el("input", {
      type: "checkbox", checked: cell[key] === true,
      onchange: e => { cell[key] = e.target.checked; setDirty(true); },
    }),
    label,
  );

  // connections — N/E/S/W as text inputs (target "x,y")
  const dirs = [["north", "N"], ["east", "E"], ["south", "S"], ["west", "W"]];
  const connRows = dirs.map(([dir, abbr]) => el("div", { class: "conn-row" },
    el("label", {}, abbr),
    el("input", {
      type: "text",
      value: cell.connections?.[dir] ?? "",
      placeholder: "x,y or empty",
      oninput: e => {
        cell.connections = cell.connections ?? {};
        if (e.target.value) cell.connections[dir] = e.target.value;
        else delete cell.connections[dir];
        setDirty(true);
      },
    }),
  ));

  const modal = el("div", { id: "modal", class: "modal-backdrop", onclick: e => {
    if (e.target.id === "modal") closeModal();
  } },
    el("div", { class: "modal" },
      el("h3", {}, "Cell " + cell.pos),
      field("Stage ID", stageSelect),
      field("Rotation", rotSelect),
      el("div", { class: "field" },
        el("label", {}, "Flags"),
        el("div", { class: "toggle-row" },
          flag("is_start", "Start"),
          flag("is_end", "End"),
          flag("is_key_gate", "Key gate"),
          flag("has_key", "Has key"),
        ),
      ),
      el("div", { class: "field" },
        el("label", {}, "Connections (target pos)"),
        ...connRows,
      ),
      el("div", { class: "row" },
        el("button", { class: "danger", onclick: () => deleteCurrentCell() }, "Delete cell"),
        el("button", { class: "primary", onclick: closeModal }, "Done"),
      ),
    ),
  );
  document.body.appendChild(modal);
}

function deleteCurrentCell() {
  if (!confirm("Delete this cell?")) return;
  const sec = state.currentQuest.sections[state.currentSectionIdx];
  sec.cells.splice(state.editingCellIdx, 1);
  setDirty(true);
  closeModal();
  render();
}

async function saveCurrentQuest() {
  if (!state.currentQuest) return;
  const qid = state.currentQuest.id;
  try {
    await api(\`/api/quests/\${qid}\`, {
      method: "PUT",
      body: JSON.stringify(state.currentQuest),
    });
    setDirty(false);
    toast("Saved " + qid);
  } catch (e) {
    toast("save failed: " + e.message, "err");
  }
}

// --- boot ----------------------------------------------------------------
document.getElementById("back").addEventListener("click", goBack);
document.getElementById("save").addEventListener("click", saveCurrentQuest);

(async () => {
  try {
    const [quests, stages, npcs] = await Promise.all([
      api("/api/quests"),
      api("/api/stages"),
      api("/api/npcs"),
    ]);
    state.quests = quests;
    state.stagesByArea = stages;
    state.npcs = npcs;
    render();
  } catch (e) {
    document.getElementById("app").textContent = "Failed to load: " + e.message;
  }
})();
</script>
</body>
</html>`;
