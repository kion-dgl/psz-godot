import { useState, useCallback } from 'react';

/**
 * Controls config tool — visual diagram + editable presets + JSON export.
 * Presets: Modern (current), PSO Classic (PSOBB keyboard layout)
 */

type GameState = 'title' | 'charSelect' | 'charCreate' | 'city' | 'cityMenu' | 'cityNpc' | 'field' | 'fieldMenu' | 'fieldNpc';

const STATES: { id: GameState; label: string; color: string }[] = [
  { id: 'title', label: 'Title', color: '#4a5568' },
  { id: 'charSelect', label: 'Char Select', color: '#4a5568' },
  { id: 'charCreate', label: 'Char Create', color: '#4a5568' },
  { id: 'city', label: 'City', color: '#2b6cb0' },
  { id: 'cityMenu', label: 'City+Menu', color: '#2c7a7b' },
  { id: 'cityNpc', label: 'City NPC', color: '#6b46c1' },
  { id: 'field', label: 'Field', color: '#c05621' },
  { id: 'fieldMenu', label: 'Field+Menu', color: '#2c7a7b' },
  { id: 'fieldNpc', label: 'Field NPC', color: '#6b46c1' },
];

interface Mapping {
  action: string;
  godotAction?: string; // The Godot InputMap action name
  states: Partial<Record<GameState, string>>;
}

// ── Presets ─────────────────────────────────────────────────────────────────────

const MODERN_KEYBOARD: Mapping[] = [
  { action: 'W/A/S/D', godotAction: 'move_*', states: { city: 'Move', cityMenu: 'Move', field: 'Move', fieldMenu: 'Move' } },
  { action: 'Arrow Up/Down', godotAction: 'ui_up/down', states: { title: 'Navigate', charSelect: 'Navigate', charCreate: 'Navigate', cityMenu: 'Menu nav', cityNpc: 'Navigate', fieldMenu: 'Menu nav', fieldNpc: 'Navigate' } },
  { action: 'Arrow Left/Right', godotAction: 'camera_left/right', states: { charSelect: 'Navigate', charCreate: 'Navigate', city: 'Camera', cityMenu: 'Page flip', field: 'Camera', fieldMenu: 'Page flip' } },
  { action: 'Enter', godotAction: 'ui_accept', states: { title: 'Start', charSelect: 'Select', charCreate: 'Confirm', city: 'Interact', cityMenu: 'Confirm', cityNpc: 'Confirm', field: 'Interact', fieldMenu: 'Confirm', fieldNpc: 'Advance' } },
  { action: 'Esc', godotAction: 'pause', states: { charSelect: 'Back', charCreate: 'Back', city: 'Open menu', cityMenu: 'Back/Close', cityNpc: 'Close', field: 'Open menu', fieldMenu: 'Back/Close', fieldNpc: 'Close' } },
  { action: 'J / K / L', godotAction: 'action_1/2/3', states: { field: 'Palette 1/2/3' } },
  { action: 'Shift', godotAction: 'palette_swap', states: { field: 'Swap page' } },
  { action: 'E', godotAction: 'interact', states: { city: 'Interact', field: 'Interact' } },
  { action: 'I', godotAction: 'quick_weapon', states: { field: 'Quick weapon' } },
  { action: 'Delete', states: { charSelect: 'Delete char' } },
];

const PSO_CLASSIC_KEYBOARD: Mapping[] = [
  { action: 'W/A/S/D', godotAction: 'move_*', states: { city: 'Move', cityMenu: 'Move', field: 'Move', fieldMenu: 'Move' } },
  { action: 'Arrow Left', godotAction: 'action_1', states: { field: 'Palette Left', fieldMenu: 'Page flip' } },
  { action: 'Arrow Down', godotAction: 'action_2', states: { field: 'Palette Middle' } },
  { action: 'Arrow Right', godotAction: 'action_3', states: { field: 'Palette Right', fieldMenu: 'Page flip' } },
  { action: 'Arrow Up', states: { field: 'Center camera' } },
  { action: 'Home', godotAction: 'pause', states: { city: 'Open menu', cityMenu: 'Close menu', field: 'Open menu', fieldMenu: 'Close menu' } },
  { action: 'Esc', godotAction: 'ui_cancel', states: { charSelect: 'Back', charCreate: 'Back', cityMenu: 'Back', cityNpc: 'Close', fieldMenu: 'Back', fieldNpc: 'Close' } },
  { action: 'Enter', godotAction: 'ui_accept', states: { title: 'Start', charSelect: 'Select', charCreate: 'Confirm', city: 'Interact', cityMenu: 'Confirm', cityNpc: 'Confirm', field: 'Interact', fieldMenu: 'Confirm', fieldNpc: 'Advance' } },
  { action: 'Backspace', godotAction: 'ui_cancel', states: { cityMenu: 'Cancel', fieldMenu: 'Cancel', cityNpc: 'Close', fieldNpc: 'Close' } },
  { action: 'Ctrl', godotAction: 'palette_swap', states: { field: 'Swap palette' } },
  { action: 'End', states: { field: 'Palette top' } },
  { action: 'Tab', states: { cityMenu: 'Cycle info', fieldMenu: 'Cycle info' } },
  { action: 'F2', states: { cityMenu: 'Equipment', fieldMenu: 'Equipment' } },
  { action: 'F3', states: { cityMenu: 'Technique', fieldMenu: 'Technique' } },
  { action: 'F4', states: { cityMenu: 'Mag', fieldMenu: 'Mag' } },
  { action: 'E', godotAction: 'interact', states: { city: 'Interact', field: 'Interact' } },
];

const CONTROLLER: Mapping[] = [
  { action: 'Left Stick', godotAction: 'move_*', states: { city: 'Move', cityMenu: 'Move', field: 'Move', fieldMenu: 'Move' } },
  { action: 'D-pad Up/Down', godotAction: 'ui_up/down', states: { title: 'Navigate', charSelect: 'Navigate', charCreate: 'Navigate', cityMenu: 'Menu nav', cityNpc: 'Navigate', fieldMenu: 'Menu nav', fieldNpc: 'Navigate' } },
  { action: 'D-pad Left/Right', godotAction: 'ui_left/right', states: { charSelect: 'Navigate', charCreate: 'Navigate' } },
  { action: 'R-Stick Left/Right', states: { city: 'Camera', field: 'Camera' } },
  { action: 'R-Stick Up/Down', states: { cityMenu: 'Menu scroll', fieldMenu: 'Menu scroll' } },
  { action: 'A (Accept)', godotAction: 'ui_accept', states: { title: 'Start', charSelect: 'Select', charCreate: 'Confirm', city: 'Interact', cityMenu: 'Confirm', cityNpc: 'Confirm', field: 'Interact', fieldMenu: 'Confirm', fieldNpc: 'Advance' } },
  { action: 'B (Cancel)', godotAction: 'ui_cancel/action_3', states: { charSelect: 'Back', charCreate: 'Back', cityMenu: 'Back', cityNpc: 'Close', field: 'Palette 3', fieldMenu: 'Back', fieldNpc: 'Close' } },
  { action: 'X', godotAction: 'action_1', states: { field: 'Palette 1' } },
  { action: 'Y', godotAction: 'action_2', states: { field: 'Palette 2' } },
  { action: 'Start', godotAction: 'pause', states: { title: 'Start', city: 'Open menu', cityMenu: 'Close menu', field: 'Open menu', fieldMenu: 'Close menu' } },
  { action: 'LB', godotAction: 'palette_swap', states: { city: 'Palette swap', cityMenu: 'Page left', field: 'Palette swap', fieldMenu: 'Page left' } },
  { action: 'RB', godotAction: 'quest_log', states: { cityMenu: 'Page right', field: 'Quest log', fieldMenu: 'Page right' } },
];

// ── JSON config types ──────────────────────────────────────────────────────────

interface InputConfig {
  preset: string;
  version: number;
  keyboard: Record<string, string>;
  controller: Record<string, string>;
}

function generateConfig(preset: string): InputConfig {
  if (preset === 'pso-classic') {
    return {
      preset: 'pso-classic',
      version: 1,
      keyboard: {
        move_forward: 'W', move_backward: 'S', move_left: 'A', move_right: 'D',
        palette_1: 'ArrowLeft', palette_2: 'ArrowDown', palette_3: 'ArrowRight',
        camera_center: 'ArrowUp',
        menu_toggle: 'Home', cancel: 'Escape', accept: 'Enter',
        interact: 'E', palette_swap: 'ControlLeft',
        f2_equipment: 'F2', f3_technique: 'F3', f4_mag: 'F4',
        tab_cycle: 'Tab', backspace_cancel: 'Backspace',
      },
      controller: { note: 'Controller layout is the same for both presets' },
    };
  }
  return {
    preset: 'modern',
    version: 1,
    keyboard: {
      move_forward: 'W', move_backward: 'S', move_left: 'A', move_right: 'D',
      camera_left: 'ArrowLeft', camera_right: 'ArrowRight',
      menu_toggle: 'Escape', cancel: 'Escape', accept: 'Enter',
      interact: 'E', palette_1: 'J', palette_2: 'K', palette_3: 'L',
      palette_swap: 'ShiftLeft', quick_weapon: 'I',
    },
    controller: { note: 'Controller layout is the same for both presets' },
  };
}

function downloadJson(config: InputConfig) {
  const blob = new Blob([JSON.stringify(config, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `input_config_${config.preset}.json`;
  a.click();
  URL.revokeObjectURL(url);
}

// ── Components ─────────────────────────────────────────────────────────────────

function cellColor(action: string): string {
  if (action.includes('Move')) return 'rgba(40, 120, 60, 0.3)';
  if (action.includes('Navigate') || action.includes('Menu') || action.includes('scroll')) return 'rgba(40, 80, 160, 0.3)';
  if (action.includes('Camera') || action.includes('Center')) return 'rgba(160, 120, 40, 0.3)';
  if (action.includes('Page') || action.includes('flip') || action.includes('Cycle')) return 'rgba(100, 40, 160, 0.3)';
  if (action.includes('Palette') || action.includes('Swap') || action.includes('Quest') || action.includes('weapon')) return 'rgba(160, 80, 40, 0.3)';
  if (action.includes('Open') || action.includes('Close') || action.includes('Back') || action.includes('Cancel')) return 'rgba(160, 40, 40, 0.3)';
  if (action.includes('Confirm') || action.includes('Select') || action.includes('Start') || action.includes('Interact') || action.includes('Advance')) return 'rgba(40, 160, 120, 0.3)';
  if (action.includes('Equipment') || action.includes('Technique') || action.includes('Mag')) return 'rgba(80, 120, 160, 0.3)';
  return 'rgba(80, 80, 80, 0.2)';
}

const th: React.CSSProperties = { padding: '6px 8px', borderBottom: '2px solid #333', fontSize: 11, textTransform: 'uppercase', letterSpacing: 0.5 };
const td: React.CSSProperties = { padding: '5px 8px', borderBottom: '1px solid #222', fontSize: 12 };

function MappingTable({ title, mappings, highlight }: { title: string; mappings: Mapping[]; highlight?: string }) {
  const [hovered, setHovered] = useState<string | null>(null);

  return (
    <div style={{ marginBottom: 24 }}>
      <h3 style={{ margin: '0 0 8px', color: '#e0e0e0', fontSize: 16 }}>{title}</h3>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: 13, fontFamily: 'monospace' }}>
          <thead>
            <tr>
              <th style={{ ...th, width: 130, textAlign: 'left' }}>Input</th>
              <th style={{ ...th, width: 100, textAlign: 'left', color: '#666' }}>Godot Action</th>
              {STATES.map(s => (
                <th key={s.id} style={{ ...th, background: s.color, color: '#fff', minWidth: 80 }}>{s.label}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {mappings.map(m => {
              const isHighlighted = highlight && m.action.includes(highlight);
              return (
                <tr key={m.action}
                  onMouseEnter={() => setHovered(m.action)}
                  onMouseLeave={() => setHovered(null)}
                  style={{ background: isHighlighted ? 'rgba(255,200,50,0.1)' : hovered === m.action ? 'rgba(255,255,255,0.05)' : 'transparent' }}
                >
                  <td style={{ ...td, fontWeight: 700, color: '#88aaff' }}>{m.action}</td>
                  <td style={{ ...td, color: '#555', fontSize: 10 }}>{m.godotAction || '--'}</td>
                  {STATES.map(s => {
                    const val = m.states[s.id];
                    return (
                      <td key={s.id} style={{
                        ...td, color: val ? '#e0e0e0' : '#333',
                        background: val ? cellColor(val) : 'transparent',
                        fontWeight: val ? 600 : 400, textAlign: 'center',
                      }}>{val || '--'}</td>
                    );
                  })}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Issues() {
  const issues = [
    { text: 'Controller: Start doesn\'t close start menu', done: true },
    { text: 'Controller: Left stick scrolls menu (should only move player)', done: true },
    { text: 'Controller: D-pad no hold-to-repeat', done: false },
    { text: 'Controller: R-stick should scroll menus when menu open', done: true },
    { text: 'Controller: LB/RB should flip pages when menu open', done: true },
    { text: 'Keyboard: Arrow L/R controls camera when menu open (should flip pages)', done: true },
    { text: 'Keyboard: Running with WASD interrupts arrow key scrolling', done: true },
    { text: 'Player can talk to NPC while start menu is open', done: true },
    { text: 'Quick weapon menu can open on top of start menu', done: true },
    { text: 'Snake enemy still stuck when player blocks path', done: false },
  ];

  return (
    <div style={{ marginBottom: 24 }}>
      <h3 style={{ margin: '0 0 8px', color: '#e0e0e0', fontSize: 16 }}>Issues Checklist</h3>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        {issues.map((issue, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 8, padding: '3px 10px',
            background: '#1a1a2e', borderRadius: 4, border: '1px solid #2a2a4a', fontSize: 12,
          }}>
            <span style={{ color: issue.done ? '#44cc44' : '#cc4444', fontSize: 14 }}>{issue.done ? '✓' : '○'}</span>
            <span style={{ color: issue.done ? '#888' : '#ccc', textDecoration: issue.done ? 'line-through' : 'none' }}>{issue.text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function StateFlow() {
  const transitions = [
    { from: 'Title', to: 'Char Select', trigger: 'Start/A' },
    { from: 'Char Select', to: 'Char Create', trigger: 'New Game' },
    { from: 'Char Select', to: 'City', trigger: 'Select char' },
    { from: 'City', to: 'City+Menu', trigger: 'Esc/Start' },
    { from: 'City+Menu', to: 'City', trigger: 'Esc/Start/Close' },
    { from: 'City', to: 'City NPC', trigger: 'Interact' },
    { from: 'City NPC', to: 'City', trigger: 'Esc/B' },
    { from: 'City', to: 'Field', trigger: 'Warp' },
    { from: 'Field', to: 'Field+Menu', trigger: 'Esc/Start' },
    { from: 'Field+Menu', to: 'Field', trigger: 'Esc/Start/Close' },
    { from: 'Field', to: 'Field NPC', trigger: 'Dialog' },
    { from: 'Field', to: 'City', trigger: 'Telepipe/Warp' },
    { from: 'City+Menu', to: 'Title', trigger: 'Return to Title' },
    { from: 'Field+Menu', to: 'Title', trigger: 'Return to Title' },
  ];

  return (
    <div style={{ marginBottom: 24 }}>
      <h3 style={{ margin: '0 0 8px', color: '#e0e0e0', fontSize: 16 }}>State Transitions</h3>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
        {transitions.map((t, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 5, padding: '3px 8px',
            background: '#1a1a2e', borderRadius: 5, border: '1px solid #2a2a4a', fontSize: 11, fontFamily: 'monospace',
          }}>
            <span style={{ color: '#88aaff', fontWeight: 700 }}>{t.from}</span>
            <span style={{ color: '#555' }}>→</span>
            <span style={{ color: '#88ff88', fontWeight: 700 }}>{t.to}</span>
            <span style={{ color: '#666', fontSize: 10 }}>({t.trigger})</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Main ────────────────────────────────────────────────────────────────────────

export default function ControlsDiagram() {
  const [preset, setPreset] = useState<'modern' | 'pso-classic'>('modern');
  const kbMappings = preset === 'modern' ? MODERN_KEYBOARD : PSO_CLASSIC_KEYBOARD;

  const handleExport = useCallback(() => {
    const config = generateConfig(preset);
    downloadJson(config);
  }, [preset]);

  const handleImport = useCallback(() => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json';
    input.onchange = (e) => {
      const file = (e.target as HTMLInputElement).files?.[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const config = JSON.parse(reader.result as string) as InputConfig;
          if (config.preset === 'pso-classic') setPreset('pso-classic');
          else setPreset('modern');
          alert(`Loaded preset: ${config.preset}\n\nTo use in-game, place this file at:\nuser://input_config.json`);
        } catch { alert('Invalid JSON file'); }
      };
      reader.readAsText(file);
    };
    input.click();
  }, []);

  return (
    <div style={{ padding: 20, maxWidth: 1400, margin: '0 auto', color: '#ccc', height: '100%', overflowY: 'auto' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 16, flexWrap: 'wrap' }}>
        <h1 style={{ margin: 0, color: '#e0e0e0', fontSize: 22 }}>Controls Config</h1>
        <div style={{ display: 'flex', gap: 6 }}>
          {(['modern', 'pso-classic'] as const).map(p => (
            <button key={p} onClick={() => setPreset(p)} style={{
              padding: '5px 14px', borderRadius: 4, cursor: 'pointer', fontSize: 12, fontWeight: 700,
              background: preset === p ? '#e08820' : '#2a2a4a', color: preset === p ? '#fff' : '#888',
              border: preset === p ? '2px solid #c07010' : '1px solid #3a3a5a',
            }}>{p === 'modern' ? 'Modern' : 'PSO Classic'}</button>
          ))}
        </div>
        <button onClick={handleExport} style={{
          padding: '5px 14px', borderRadius: 4, cursor: 'pointer', fontSize: 12,
          background: '#2b6cb0', color: '#fff', border: '1px solid #3b7cc0',
        }}>Export JSON</button>
        <button onClick={handleImport} style={{
          padding: '5px 14px', borderRadius: 4, cursor: 'pointer', fontSize: 12,
          background: '#2a2a4a', color: '#888', border: '1px solid #3a3a5a',
        }}>Import JSON</button>
      </div>

      <p style={{ margin: '0 0 16px', color: '#666', fontSize: 12 }}>
        Color coding: <span style={{ color: '#4a9' }}>movement</span> <span style={{ color: '#48a' }}>menu/nav</span> <span style={{ color: '#a84' }}>camera</span> <span style={{ color: '#84a' }}>pages</span> <span style={{ color: '#a64' }}>palette</span> <span style={{ color: '#a44' }}>open/close</span> <span style={{ color: '#4a8' }}>confirm</span>
        {preset === 'pso-classic' && <span style={{ color: '#ca8', marginLeft: 12 }}>Showing PSO Classic layout — arrow keys map to action palette</span>}
      </p>

      <MappingTable title={`Keyboard — ${preset === 'modern' ? 'Modern' : 'PSO Classic'}`} mappings={kbMappings} />
      <MappingTable title="Controller (Switch / XInput)" mappings={CONTROLLER} />
      <Issues />
      <StateFlow />

      {/* JSON preview */}
      <div style={{ marginTop: 16 }}>
        <h3 style={{ margin: '0 0 8px', color: '#e0e0e0', fontSize: 16 }}>Config JSON Preview</h3>
        <pre style={{
          background: '#0a0a1a', border: '1px solid #2a2a4a', borderRadius: 6,
          padding: 12, fontSize: 11, color: '#88aaff', overflowX: 'auto', maxHeight: 300,
        }}>
          {JSON.stringify(generateConfig(preset), null, 2)}
        </pre>
      </div>
    </div>
  );
}
