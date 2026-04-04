import { useState } from 'react';

/**
 * Controls state diagram — visual reference for keyboard + controller
 * mappings across all game states.
 */

type GameState = 'title' | 'charSelect' | 'charCreate' | 'city' | 'cityMenu' | 'cityNpc' | 'field' | 'fieldMenu' | 'fieldNpc';

const STATES: { id: GameState; label: string; color: string }[] = [
  { id: 'title', label: 'Title Menu', color: '#4a5568' },
  { id: 'charSelect', label: 'Character Select', color: '#4a5568' },
  { id: 'charCreate', label: 'Character Create', color: '#4a5568' },
  { id: 'city', label: 'City', color: '#2b6cb0' },
  { id: 'cityMenu', label: 'City + Menu', color: '#2c7a7b' },
  { id: 'cityNpc', label: 'City NPC/Shop', color: '#6b46c1' },
  { id: 'field', label: 'Field', color: '#c05621' },
  { id: 'fieldMenu', label: 'Field + Menu', color: '#2c7a7b' },
  { id: 'fieldNpc', label: 'Field NPC/Dialog', color: '#6b46c1' },
];

interface Mapping {
  action: string;
  states: Partial<Record<GameState, string>>;
}

const KEYBOARD: Mapping[] = [
  { action: 'W/A/S/D', states: { city: 'Move', cityMenu: 'Move', field: 'Move', fieldMenu: 'Move' } },
  { action: 'Arrow Up/Down', states: { title: 'Navigate', charSelect: 'Navigate', charCreate: 'Navigate', cityMenu: 'Menu nav', cityNpc: 'Navigate', fieldMenu: 'Menu nav', fieldNpc: 'Navigate' } },
  { action: 'Arrow Left/Right', states: { charSelect: 'Navigate', charCreate: 'Navigate', city: 'Camera', cityMenu: 'Page flip', field: 'Camera', fieldMenu: 'Page flip' } },
  { action: 'Enter', states: { title: 'Start', charSelect: 'Select', charCreate: 'Confirm', city: 'Interact', cityMenu: 'Confirm', cityNpc: 'Confirm', field: 'Interact', fieldMenu: 'Confirm', fieldNpc: 'Advance' } },
  { action: 'Esc', states: { charSelect: 'Back', charCreate: 'Back', city: 'Open menu', cityMenu: 'Back/Close', cityNpc: 'Close', field: 'Open menu', fieldMenu: 'Back/Close', fieldNpc: 'Close' } },
  { action: 'J / K / L', states: { field: 'Palette 1/2/3' } },
  { action: 'Shift', states: { field: 'Swap page' } },
  { action: 'E', states: { city: 'Interact', field: 'Interact' } },
  { action: 'I', states: { field: 'Quick weapon' } },
  { action: 'Delete', states: { charSelect: 'Delete char' } },
];

const CONTROLLER: Mapping[] = [
  { action: 'Left Stick', states: { city: 'Move', cityMenu: 'Move', field: 'Move', fieldMenu: 'Move' } },
  { action: 'D-pad Up/Down', states: { title: 'Navigate', charSelect: 'Navigate', charCreate: 'Navigate', cityMenu: 'Menu nav', cityNpc: 'Navigate', fieldMenu: 'Menu nav', fieldNpc: 'Navigate' } },
  { action: 'D-pad Left/Right', states: { charSelect: 'Navigate', charCreate: 'Navigate' } },
  { action: 'R-Stick Left/Right', states: { city: 'Camera', field: 'Camera' } },
  { action: 'R-Stick Up/Down', states: { cityMenu: 'Menu scroll', fieldMenu: 'Menu scroll' } },
  { action: 'A (Accept)', states: { title: 'Start', charSelect: 'Select', charCreate: 'Confirm', city: 'Interact', cityMenu: 'Confirm', cityNpc: 'Confirm', field: 'Interact', fieldMenu: 'Confirm', fieldNpc: 'Advance' } },
  { action: 'B (Cancel)', states: { charSelect: 'Back', charCreate: 'Back', cityMenu: 'Back', cityNpc: 'Close', field: 'Palette 3', fieldMenu: 'Back', fieldNpc: 'Close' } },
  { action: 'X', states: { field: 'Palette 1' } },
  { action: 'Y', states: { field: 'Palette 2' } },
  { action: 'Start', states: { title: 'Start', city: 'Open menu', cityMenu: 'Close menu', field: 'Open menu', fieldMenu: 'Close menu' } },
  { action: 'LB', states: { city: 'Palette swap', cityMenu: 'Page left', field: 'Palette swap', fieldMenu: 'Page left' } },
  { action: 'RB', states: { cityMenu: 'Page right', field: 'Quest log', fieldMenu: 'Page right' } },
];

function MappingTable({ title, mappings }: { title: string; mappings: Mapping[] }) {
  const [hovered, setHovered] = useState<string | null>(null);

  return (
    <div style={{ marginBottom: 32 }}>
      <h2 style={{ margin: '0 0 12px', color: '#e0e0e0', fontSize: 18 }}>{title}</h2>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: 13, fontFamily: 'monospace' }}>
          <thead>
            <tr>
              <th style={{ ...th, width: 140, textAlign: 'left' }}>Input</th>
              {STATES.map(s => (
                <th key={s.id} style={{ ...th, background: s.color, color: '#fff', minWidth: 90 }}>
                  {s.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {mappings.map(m => (
              <tr
                key={m.action}
                onMouseEnter={() => setHovered(m.action)}
                onMouseLeave={() => setHovered(null)}
                style={{ background: hovered === m.action ? 'rgba(255,255,255,0.05)' : 'transparent' }}
              >
                <td style={{ ...td, fontWeight: 700, color: '#88aaff' }}>{m.action}</td>
                {STATES.map(s => {
                  const val = m.states[s.id];
                  return (
                    <td key={s.id} style={{
                      ...td,
                      color: val ? '#e0e0e0' : '#333',
                      background: val ? cellColor(val) : 'transparent',
                      fontWeight: val ? 600 : 400,
                      textAlign: 'center',
                    }}>
                      {val || '--'}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function cellColor(action: string): string {
  if (action.includes('Move')) return 'rgba(40, 120, 60, 0.3)';
  if (action.includes('Navigate') || action.includes('Menu') || action.includes('scroll')) return 'rgba(40, 80, 160, 0.3)';
  if (action.includes('Camera')) return 'rgba(160, 120, 40, 0.3)';
  if (action.includes('Page') || action.includes('flip')) return 'rgba(100, 40, 160, 0.3)';
  if (action.includes('Palette') || action.includes('Swap') || action.includes('Quest')) return 'rgba(160, 80, 40, 0.3)';
  if (action.includes('Open') || action.includes('Close') || action.includes('Back')) return 'rgba(160, 40, 40, 0.3)';
  if (action.includes('Confirm') || action.includes('Select') || action.includes('Start') || action.includes('Interact') || action.includes('Advance')) return 'rgba(40, 160, 120, 0.3)';
  return 'rgba(80, 80, 80, 0.2)';
}

const th: React.CSSProperties = { padding: '6px 8px', borderBottom: '2px solid #333', fontSize: 11, textTransform: 'uppercase', letterSpacing: 0.5 };
const td: React.CSSProperties = { padding: '5px 8px', borderBottom: '1px solid #222', fontSize: 12 };

// State transition diagram
function StateFlow() {
  const transitions = [
    { from: 'Title', to: 'Char Select', trigger: 'Start/A' },
    { from: 'Char Select', to: 'Char Create', trigger: 'New Game' },
    { from: 'Char Select', to: 'City', trigger: 'Select char' },
    { from: 'Char Create', to: 'City', trigger: 'Create' },
    { from: 'City', to: 'City+Menu', trigger: 'Esc/Start' },
    { from: 'City+Menu', to: 'City', trigger: 'Esc/Start/Close' },
    { from: 'City', to: 'City NPC', trigger: 'Interact' },
    { from: 'City NPC', to: 'City', trigger: 'Esc/B/Close' },
    { from: 'City', to: 'Field', trigger: 'Warp/Quest' },
    { from: 'Field', to: 'Field+Menu', trigger: 'Esc/Start' },
    { from: 'Field+Menu', to: 'Field', trigger: 'Esc/Start/Close' },
    { from: 'Field', to: 'Field NPC', trigger: 'Dialog trigger' },
    { from: 'Field NPC', to: 'Field', trigger: 'Esc/Advance' },
    { from: 'Field', to: 'City', trigger: 'Area warp/Telepipe' },
    { from: 'City+Menu', to: 'Title', trigger: 'Return to Title' },
    { from: 'Field+Menu', to: 'Title', trigger: 'Return to Title' },
  ];

  return (
    <div style={{ marginBottom: 32 }}>
      <h2 style={{ margin: '0 0 12px', color: '#e0e0e0', fontSize: 18 }}>State Transitions</h2>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {transitions.map((t, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 6, padding: '4px 10px',
            background: '#1a1a2e', borderRadius: 6, border: '1px solid #2a2a4a', fontSize: 12, fontFamily: 'monospace',
          }}>
            <span style={{ color: '#88aaff', fontWeight: 700 }}>{t.from}</span>
            <span style={{ color: '#666' }}>→</span>
            <span style={{ color: '#88ff88', fontWeight: 700 }}>{t.to}</span>
            <span style={{ color: '#888', fontSize: 10 }}>({t.trigger})</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// Issues checklist
function Issues() {
  const issues = [
    { text: 'Controller: Start doesn\'t close start menu', done: false },
    { text: 'Controller: Left stick scrolls menu (should only move player)', done: false },
    { text: 'Controller: D-pad no hold-to-repeat', done: false },
    { text: 'Controller: R-stick should scroll menus when menu open', done: false },
    { text: 'Controller: LB/RB should flip pages when menu open', done: false },
    { text: 'Keyboard: Arrow L/R controls camera when menu open (should flip pages)', done: false },
    { text: 'Keyboard: Running with WASD interrupts arrow key scrolling', done: false },
    { text: 'Snake enemy still stuck when player blocks path', done: false },
    { text: 'Player can talk to NPC while start menu is open', done: false },
    { text: 'Quick weapon menu can open on top of start menu', done: false },
  ];

  return (
    <div>
      <h2 style={{ margin: '0 0 12px', color: '#e0e0e0', fontSize: 18 }}>Issues to Fix</h2>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {issues.map((issue, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 8, padding: '4px 10px',
            background: '#1a1a2e', borderRadius: 4, border: '1px solid #2a2a4a', fontSize: 13,
          }}>
            <span style={{ color: issue.done ? '#44cc44' : '#cc4444' }}>{issue.done ? '✓' : '○'}</span>
            <span style={{ color: '#ccc' }}>{issue.text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function ControlsDiagram() {
  return (
    <div style={{ padding: 24, maxWidth: 1400, margin: '0 auto', color: '#ccc', height: '100%', overflowY: 'auto' }}>
      <h1 style={{ margin: '0 0 8px', color: '#e0e0e0', fontSize: 24 }}>Controls State Diagram</h1>
      <p style={{ margin: '0 0 24px', color: '#888', fontSize: 13 }}>
        Input mapping for keyboard and controller across all game states.
        Color coding: <span style={{ color: '#4a9' }}>movement</span>, <span style={{ color: '#48a' }}>menu/nav</span>, <span style={{ color: '#a84' }}>camera</span>, <span style={{ color: '#84a' }}>pages</span>, <span style={{ color: '#a44' }}>open/close</span>, <span style={{ color: '#4a8' }}>confirm/interact</span>
      </p>

      <MappingTable title="Keyboard" mappings={KEYBOARD} />
      <MappingTable title="Controller (Switch / XInput)" mappings={CONTROLLER} />
      <Issues />
      <StateFlow />
    </div>
  );
}
