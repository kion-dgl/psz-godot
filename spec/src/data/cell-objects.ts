// Per-object documentation specs. One entry per field cell-object type.
// `slug` is the URL segment under /states/objects/. `glb` is a CDN asset
// path consumed by <ObjectViewer> (assetUrl resolves it); null means the
// object has no single canonical model (varies at runtime) and the viewer
// renders a placeholder. Schema mined from web/src/elements + the field
// controller's CellObjectSpawner.

export interface ConfigField {
  name: string;
  type: string;
  default?: string;
  note: string;
}

export interface CellObjectSpec {
  slug: string;
  title: string;
  type: string;
  glb: string | null;
  scale?: number;
  configFields: ConfigField[];
  spawns: string;
  state: string;
  interactions: string;
  notes?: string;
}

export const cellObjects: CellObjectSpec[] = [
  {
    slug: 'box',
    title: 'Box',
    type: 'box / rare_box',
    glb: '/assets/objects/valley/o01_cont.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
      { name: 'rotation', type: 'number', default: '0', note: 'yaw in degrees' },
      { name: 'drop_type', type: 'string', note: '"meseta" | "item" | "material" | "none"' },
      { name: 'drop_value', type: 'number | string', note: 'amount (meseta) or item / material id' },
    ],
    spawns: 'A breakable container placed at spawn from the stage config. The `rare_box` variant uses the same model but carries a rarer drop table.',
    state: 'Persisted state is `intact` → `broken`. Once broken it MUST NOT reappear on cell re-entry, and it MUST NOT re-roll or re-drop its loot.',
    interactions: 'The player attacks the box to break it. Breaking spawns the configured drop (meseta / item / material) as a ground pickup; the pickup itself is then a normal drop tracked in the cell snapshot.',
  },
  {
    slug: 'wall',
    title: 'Wall',
    type: 'wall',
    glb: '/assets/objects/valley/o01_wall.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
      { name: 'rotation', type: 'number', default: '0', note: 'yaw in degrees' },
      { name: 'destructible', type: 'bool', default: 'false', note: 'if true the wall can be cleared by attacks' },
    ],
    spawns: 'A static blocker placed from the stage config. Forms part of the cell collision so the player and pathing MUST route around it.',
    state: 'Persisted state is `intact` → `destroyed`. A destroyed destructible wall MUST stay destroyed on re-entry.',
    interactions: 'A non-`destructible` wall is a permanent blocker. A `destructible` wall can be attacked until destroyed, opening the path it blocked.',
  },
  {
    slug: 'fence',
    title: 'Fence',
    type: 'fence',
    glb: '/assets/objects/valley/o0c_fence.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
      { name: 'link_id', type: 'string', note: 'pairs the fence to a step-switch with the same link_id' },
      { name: 'scale_x', type: 'number', default: '1', note: 'stretches the fence span along X' },
    ],
    spawns: 'A toggleable barrier placed from the stage config. Starts solid (raised) and blocks the exit / path it spans.',
    state: 'Link state (raised / lowered) is persisted with the cell. A fence lowered by its switch MUST stay lowered on re-entry.',
    interactions: 'A fence is not attacked. It is toggled by stepping on the step-switch that shares its `link_id` (the `flip_switch` plan action). A switch is bound to a specific fence link, so it only ever affects its own fence(s).',
    notes: 'Distinct from gates: a fence is switch-driven and link-scoped, whereas a key is section-scoped.',
  },
  {
    slug: 'switch',
    title: 'Step Switch',
    type: 'step_switch',
    glb: '/assets/objects/valley/o0c_switchs.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
      { name: 'link_id', type: 'string', note: 'links to the fence(s) with the same link_id' },
    ],
    spawns: 'A floor pressure plate placed from the stage config.',
    state: 'Pressed / unpressed link state is persisted with the cell alongside its linked fence.',
    interactions: 'Stepping onto the switch (`flip_switch` plan action) toggles every fence sharing its `link_id`. The switch only affects its own linked fence(s) — never an unrelated barrier.',
  },
  {
    slug: 'message',
    title: 'Message Pack',
    type: 'message',
    glb: '/assets/objects/valley/o0c_mspack.glb',
    configFields: [
      { name: 'text', type: 'string', note: 'message body shown when read' },
      { name: 'locked', type: 'bool', default: 'false', note: 'if true the pack cannot be read until unlocked' },
      { name: 'reaction_dialog', type: 'array', note: 'optional dialog lines fired on read' },
      { name: 'objective_item_id', type: 'string', note: 'optional — reading ticks this objective count' },
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
    ],
    spawns: 'A readable message pack placed from the stage config.',
    state: 'Persisted state is `available` → `read`. A read message MUST stay read on re-entry.',
    interactions: 'The player reads the pack. Reading MAY advance an objective (when `objective_item_id` is set) and MAY fire `reaction_dialog`. The objective tick is guarded so re-reads do not double-count.',
  },
  {
    slug: 'needle-trap',
    title: 'Needle Trap',
    type: 'needle_trap',
    glb: '/assets/objects/valley/o0c_needle.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
    ],
    spawns: 'A floor trap placed from the stage config.',
    state: 'Armed / sprung. Whether a sprung trap re-arms on re-entry follows the cell snapshot.',
    interactions: 'Stepping onto the trap deals damage to the player on contact.',
  },
  {
    slug: 'bear-trap',
    title: 'Bear Trap',
    type: 'bear_trap',
    glb: '/assets/objects/valley/o0c_torabasami.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
    ],
    spawns: 'A floor trap placed from the stage config.',
    state: 'Armed / sprung, tracked with the cell snapshot.',
    interactions: 'Stepping onto the trap immobilizes the player on contact (rather than dealing damage outright).',
  },
  {
    slug: 'gate',
    title: 'Gate',
    type: 'gate',
    glb: '/assets/objects/valley/o0c_gate.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
      { name: 'kind', type: 'string', note: '"normal" | "key" | "area"' },
      { name: 'link_id', type: 'string', note: 'for area gates — the target section / connection' },
    ],
    spawns: 'A barrier across a cell exit, placed from the stage config. Its direction resolves through `StageRotation` so a rotated cell still opens the correct physical exit.',
    state: 'Persisted as opened / closed. An opened gate MUST stay open on re-entry.',
    interactions: 'Three kinds: a **normal** gate unlocks once every enemy in the room is cleared (`kill_all`); a **key** gate is opened with a section key (`pickup_key` then `open_gate`); an **area** gate is an `area_warp` connecting to a different section.',
    notes: 'Keys are section-scoped: any key found anywhere in a section opens any key gate in that section.',
  },
  {
    slug: 'key',
    title: 'Key',
    type: 'key',
    glb: '/assets/objects/valley/o0c_key.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
    ],
    spawns: 'A pickup, typically dropped when a sibling cell is cleared. Placed / spawned per the stage config.',
    state: 'Persisted as collected once picked up (tracked in controller-level `_keys_collected`). A collected key MUST stay collected.',
    interactions: 'The player collects the key (`pickup_key`). Keys are **section-scoped** — any key opens any key gate in the same section; they are not paired one-to-one with a specific gate.',
  },
  {
    slug: 'area-warp',
    title: 'Area Warp',
    type: 'warp (area gate)',
    glb: '/assets/objects/special/o0s_warpm.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
      { name: 'link_id', type: 'string', note: 'the target section this gate connects to' },
    ],
    spawns: 'An area gate placed from the stage config — not a barrier within a section but a connection to a different section.',
    state: '—',
    interactions: 'Passing through transitions the player across sections. A clearer name would be *area gate*; it is the cross-section counterpart to a key / normal gate.',
  },
  {
    slug: 'warp-point',
    title: 'Warp Point',
    type: 'warp',
    glb: '/assets/objects/valley/o0c_point.glb',
    configFields: [
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
      { name: 'link_id', type: 'string', note: 'the target section / cell to move the player to' },
    ],
    spawns: 'A teleport pad placed from the stage config.',
    state: '—',
    interactions: 'Stepping onto the point moves the player to another section / cell.',
  },
  {
    slug: 'story-prop',
    title: 'Story Prop',
    type: 'story_prop',
    glb: '/assets/objects/story/dropship_crash.glb',
    configFields: [
      { name: 'prop_path', type: 'string', note: 'res:// path to the GLB to instantiate' },
      { name: 'prop_scale', type: 'number', default: '1', note: 'uniform scale applied to the prop' },
      { name: 'no_collision', type: 'bool', default: 'false', note: 'if true the prop is decorative only' },
    ],
    spawns: 'An arbitrary scene-decoration mesh placed from the stage config — its `prop_path` selects the model, so the prop has no single canonical GLB. The crashed dropship shown here is one example.',
    state: '—',
    interactions: 'Purely visual / atmospheric. With `no_collision` set it does not block the player; otherwise it contributes collision like a wall.',
    notes: 'Because the model is driven by `prop_path`, there is no generic story-prop GLB — the viewer shows the dropship crash example.',
  },
  {
    slug: 'dialog-trigger',
    title: 'Dialog Trigger',
    type: 'dialog_trigger',
    glb: null,
    configFields: [
      { name: 'trigger_id', type: 'string', note: 'unique id for the trigger volume' },
      { name: 'dialog', type: 'array', note: 'dialog lines fired when the trigger condition is met' },
      { name: 'trigger_condition', type: 'string', default: '"enter"', note: '"enter" | other condition keywords' },
      { name: 'actions', type: 'array', note: 'optional actions run alongside the dialog' },
      { name: 'trigger_size', type: '[x, y, z]', note: 'dimensions of the invisible trigger volume' },
    ],
    spawns: 'An invisible trigger volume placed from the stage config. It has no mesh — the viewer shows a placeholder.',
    state: 'Persisted state is `ready` → fired. A fired trigger MUST NOT re-fire on re-entry.',
    interactions: 'When the player satisfies `trigger_condition` (e.g. entering the volume), the trigger fires its `dialog` and any `actions`.',
  },
  {
    slug: 'field-npc',
    title: 'Field NPC',
    type: 'npc',
    glb: '/assets/npcs/sarisa/pc_a00_000.glb',
    configFields: [
      { name: 'npc_id', type: 'string', note: 'selects which NPC model to spawn' },
      { name: 'npc_name', type: 'string', note: 'display name in dialog' },
      { name: 'dialog', type: 'array', note: 'dialog lines spoken on interact' },
      { name: 'animation', type: 'string', note: 'idle / scripted animation to play' },
    ],
    spawns: 'A placed NPC, model chosen by `npc_id` — so the model varies. Sarisa is shown here as an example.',
    state: '—',
    interactions: 'The player talks to the NPC to play its `dialog`. Animations are driven by the `animation` field.',
    notes: 'The model varies by `npc_id`; the viewer shows one example NPC.',
  },
  {
    slug: 'enemy',
    title: 'Enemy',
    type: 'enemy',
    glb: null,
    configFields: [
      { name: 'enemy_id', type: 'string', note: 'selects the enemy type — the model varies by id' },
      { name: 'wave', type: 'int', note: 'which combat wave the enemy belongs to' },
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
    ],
    spawns: 'A combat target whose model varies by `enemy_id`, so there is no single canonical GLB — the viewer shows a placeholder. See the Enemies page for the roster.',
    state: 'Persisted state is `alive` → `dead`. Killed enemies MUST NOT respawn on re-entry.',
    interactions: 'The player defeats the enemy in combat. Clearing every enemy in a room (`kill_all`) can unlock a normal gate or drop a key.',
  },
  {
    slug: 'quest-item',
    title: 'Quest Item',
    type: 'quest_item',
    glb: null,
    configFields: [
      { name: 'item_id', type: 'string', note: 'the objective count key this pickup increments' },
      { name: 'label', type: 'string', note: 'display text for the HUD / log' },
      { name: 'position', type: '[x, y, z]', note: 'stage-local spawn position' },
    ],
    spawns: 'A collectible (the gold star) whose model varies by item — the viewer shows a placeholder. Placed from the stage config, sometimes gated on `room_clear`.',
    state: 'Persisted state is `available` → collected. A collected item MUST NOT reappear on re-entry.',
    interactions: 'Walking over the item (or closing its pickup dialog) calls `collect_quest_item(item_id)` once, ticking the matching objective count toward its target.',
  },
];

export const cellObjectBySlug: Record<string, CellObjectSpec> = Object.fromEntries(
  cellObjects.map((o) => [o.slug, o]),
);
