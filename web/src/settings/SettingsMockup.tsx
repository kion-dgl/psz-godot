import { useState, useCallback } from 'react';
import { assetUrl } from '../utils/assets';

// ── Types ────────────────────────────────────────────────────────────────────

type ControlScheme = 'keyboard_mouse' | 'keyboard_only' | 'gamepad_xinput' | 'gamepad_switch';

interface ActionSlot {
  id: string;
  label: string;
  icon?: string; // For display in palette
}

interface PalettePage {
  slots: [ActionSlot, ActionSlot, ActionSlot]; // Always 3 slots
}

interface ControlSettings {
  scheme: ControlScheme;
  pages: PalettePage[];
  activePage: number;
}

// ── Constants ────────────────────────────────────────────────────────────────

const kb = (file: string) => assetUrl(`/assets/kenney_input-prompts/Keyboard & Mouse/Default/${file}`);
const xbox = (file: string) => assetUrl(`/assets/kenney_input-prompts/Xbox Series/Default/${file}`);
const sw = (file: string) => assetUrl(`/assets/kenney_input-prompts/Nintendo Switch/Default/${file}`);

/** All available actions that can be assigned to palette slots */
const ALL_ACTIONS: ActionSlot[] = [
  { id: 'attack', label: 'Attack' },
  { id: 'dodge', label: 'Dodge' },
  { id: 'foie', label: 'Foie' },
  { id: 'barta', label: 'Barta' },
  { id: 'zonde', label: 'Zonde' },
  { id: 'resta', label: 'Resta' },
  { id: 'mate', label: 'Mate' },
  { id: 'atomizer', label: 'Atomizer' },
  { id: 'telepipe', label: 'Telepipe' },
];

const DEFAULT_PAGES: PalettePage[] = [
  { slots: [ALL_ACTIONS[0], ALL_ACTIONS[2], ALL_ACTIONS[6]] }, // Attack, Foie, Mate
  { slots: [ALL_ACTIONS[0], ALL_ACTIONS[3], ALL_ACTIONS[5]] }, // Attack, Barta, Resta
  { slots: [ALL_ACTIONS[1], ALL_ACTIONS[4], ALL_ACTIONS[7]] }, // Dodge, Zonde, Atomizer
];

interface Binding {
  label: string;
  images: string[];
  fallbackText?: string;
}

type BindingKey = 'move' | 'camera' | 'cameraLock' | 'interact' | 'cancel' | 'quickMenu' | 'action1' | 'action2' | 'action3' | 'paletteSwap' | 'pause' | 'start';

/** Binding display per scheme */
const BINDINGS: Record<ControlScheme, Partial<Record<BindingKey, Binding>>> = {
  keyboard_mouse: {
    move: { label: 'Move', images: [kb('keyboard_w.png'), kb('keyboard_a.png'), kb('keyboard_s.png'), kb('keyboard_d.png')] },
    camera: { label: 'Camera', images: [kb('mouse_move.png')] },
    cameraLock: { label: 'Camera Lock', images: [kb('keyboard_tab.png')] },
    interact: { label: 'Interact', images: [kb('keyboard_e.png')] },
    quickMenu: { label: 'Quick Menu', images: [kb('keyboard_q.png')] },
    action1: { label: 'Action 1', images: [kb('mouse_left.png')] },
    action2: { label: 'Action 2', images: [kb('mouse_right.png')] },
    action3: { label: 'Action 3', images: [kb('mouse_scroll.png')] },
    paletteSwap: { label: 'Swap Palette', images: [kb('keyboard_shift.png')] },
    pause: { label: 'Pause', images: [kb('keyboard_escape.png')] },
    start: { label: 'Start', images: [kb('keyboard_enter.png')] },
  },
  keyboard_only: {
    move: { label: 'Move', images: [kb('keyboard_w.png'), kb('keyboard_a.png'), kb('keyboard_s.png'), kb('keyboard_d.png')] },
    camera: { label: 'Camera', images: [kb('keyboard_arrow_left.png'), kb('keyboard_arrow_right.png')] },
    cameraLock: { label: 'Camera Lock', images: [kb('keyboard_tab.png')] },
    interact: { label: 'Interact', images: [kb('keyboard_e.png')] },
    quickMenu: { label: 'Quick Menu', images: [kb('keyboard_i.png')] },
    action1: { label: 'Action 1', images: [kb('keyboard_j.png')] },
    action2: { label: 'Action 2', images: [kb('keyboard_k.png')] },
    action3: { label: 'Action 3', images: [kb('keyboard_l.png')] },
    paletteSwap: { label: 'Swap Palette', images: [kb('keyboard_shift.png')] },
    pause: { label: 'Pause', images: [kb('keyboard_escape.png')] },
    start: { label: 'Start', images: [kb('keyboard_enter.png')] },
  },
  gamepad_xinput: {
    move: { label: 'Move', images: [xbox('xbox_dpad.png'), xbox('xbox_stick_l.png')] },
    camera: { label: 'Camera', images: [xbox('xbox_stick_r.png')] },
    cameraLock: { label: 'Camera Lock', images: [xbox('xbox_lb.png')] },
    interact: { label: 'Interact / Accept', images: [xbox('xbox_button_color_a.png')] },
    cancel: { label: 'Cancel / Back', images: [xbox('xbox_button_color_b.png')] },
    quickMenu: { label: 'Quick Menu', images: [xbox('xbox_button_color_y.png')] },
    action1: { label: 'Action 1', images: [xbox('xbox_button_color_x.png')] },
    action2: { label: 'Action 2', images: [xbox('xbox_button_color_a.png')] },
    action3: { label: 'Action 3', images: [xbox('xbox_button_color_b.png')] },
    paletteSwap: { label: 'Swap Palette', images: [xbox('xbox_rb.png')] },
    pause: { label: 'Pause/Start', images: [xbox('xbox_button_start.png')] },
    start: { label: 'Start', images: [xbox('xbox_button_start.png')] },
  },
  gamepad_switch: {
    move: { label: 'Move', images: [sw('switch_dpad.png'), sw('switch_stick_l.png')] },
    camera: { label: 'Camera', images: [sw('switch_stick_r.png')] },
    cameraLock: { label: 'Camera Lock', images: [sw('switch_button_l.png')] },
    interact: { label: 'Interact / Accept', images: [sw('switch_button_a.png')] },
    cancel: { label: 'Cancel / Back', images: [sw('switch_button_b.png')] },
    quickMenu: { label: 'Quick Menu', images: [sw('switch_button_x.png')] },
    action1: { label: 'Action 1', images: [sw('switch_button_y.png')] },
    action2: { label: 'Action 2', images: [sw('switch_button_b.png')] },
    action3: { label: 'Action 3', images: [sw('switch_button_a.png')] },
    paletteSwap: { label: 'Swap Palette', images: [sw('switch_button_r.png')] },
    pause: { label: 'Pause/Start', images: [sw('switch_button_plus.png')] },
    start: { label: 'Start', images: [sw('switch_button_plus.png')] },
  },
};

const SCHEME_LABELS: Record<ControlScheme, string> = {
  keyboard_mouse: 'Keyboard + Mouse',
  keyboard_only: 'Keyboard Only',
  gamepad_xinput: 'Gamepad (Xbox)',
  gamepad_switch: 'Gamepad (Switch)',
};

// ── Styles ───────────────────────────────────────────────────────────────────

const styles = {
  container: {
    display: 'flex',
    height: '100%',
    background: '#1a1a2e',
    color: '#fff',
    overflow: 'auto',
  } as const,
  sidebar: {
    width: 220,
    minWidth: 220,
    background: '#151525',
    borderRight: '1px solid #2a2a4a',
    padding: 16,
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
  } as const,
  main: {
    flex: 1,
    padding: 24,
    overflow: 'auto',
    display: 'flex',
    flexDirection: 'column',
    gap: 24,
  } as const,
  section: {
    background: '#151525',
    border: '1px solid #2a2a4a',
    borderRadius: 8,
    padding: 20,
  } as const,
  sectionTitle: {
    fontSize: 14,
    fontWeight: 600,
    color: '#88aaff',
    marginBottom: 16,
    textTransform: 'uppercase',
    letterSpacing: 1,
  } as const,
  schemeButton: (active: boolean) => ({
    padding: '10px 16px',
    background: active ? '#2a2a6a' : '#1a1a2e',
    border: active ? '2px solid #88aaff' : '1px solid #333',
    borderRadius: 6,
    color: active ? '#fff' : '#888',
    cursor: 'pointer',
    fontSize: 13,
    textAlign: 'left',
    transition: 'all 0.15s',
  } as const),
  bindingRow: {
    display: 'flex',
    alignItems: 'center',
    padding: '8px 0',
    borderBottom: '1px solid #2a2a3a',
    gap: 12,
  } as const,
  bindingLabel: {
    width: 120,
    fontSize: 13,
    color: '#aaa',
    flexShrink: 0,
  } as const,
  bindingImages: {
    display: 'flex',
    gap: 4,
    alignItems: 'center',
  } as const,
  promptImg: {
    width: 36,
    height: 36,
    imageRendering: 'pixelated',
  } as const,
  paletteContainer: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 8,
  } as const,
  paletteRow: {
    display: 'flex',
    gap: 6,
    alignItems: 'flex-end',
  } as const,
  paletteSlot: (selected: boolean) => ({
    width: 80,
    padding: '8px 4px',
    background: selected ? '#3a3a6a' : '#1a1a2e',
    border: selected ? '2px solid #88aaff' : '1px solid #333',
    borderRadius: 8,
    textAlign: 'center',
    cursor: 'pointer',
    transition: 'all 0.15s',
  } as const),
  slotKey: {
    fontSize: 10,
    color: '#666',
    marginBottom: 4,
  } as const,
  slotLabel: {
    fontSize: 12,
    color: '#fff',
    fontWeight: 500,
  } as const,
  swapPill: {
    padding: '4px 16px',
    background: '#1a1a2e',
    border: '1px solid #333',
    borderRadius: 12,
    fontSize: 11,
    color: '#888',
    display: 'flex',
    alignItems: 'center',
    gap: 6,
  } as const,
  pageIndicator: {
    display: 'flex',
    gap: 6,
    justifyContent: 'center',
  } as const,
  pageDot: (active: boolean) => ({
    width: 8,
    height: 8,
    borderRadius: '50%',
    background: active ? '#88aaff' : '#333',
    border: active ? '1px solid #aaccff' : '1px solid #444',
    cursor: 'pointer',
    transition: 'all 0.15s',
  } as const),
  editSlotSelect: {
    padding: '6px 8px',
    background: '#2a2a4a',
    border: '1px solid #444',
    borderRadius: 4,
    color: '#fff',
    fontSize: 12,
    width: '100%',
  } as const,
};

// ── Components ───────────────────────────────────────────────────────────────

function BindingRow({ label, images, fallbackText }: { label: string; images: string[]; fallbackText?: string }) {
  return (
    <div style={styles.bindingRow}>
      <div style={styles.bindingLabel}>{label}</div>
      <div style={styles.bindingImages}>
        {images.length > 0
          ? images.map((src, i) => (
              <img key={i} src={src} alt="" style={styles.promptImg} />
            ))
          : fallbackText && (
              <span style={{
                padding: '4px 10px',
                background: '#2a2a4a',
                border: '1px solid #444',
                borderRadius: 4,
                fontSize: 12,
                color: '#aaa',
              }}>
                {fallbackText}
              </span>
            )
        }
      </div>
    </div>
  );
}

function PalettePreview({
  settings,
  onPageChange,
  onSlotSelect,
  selectedSlot,
}: {
  settings: ControlSettings;
  onPageChange: (page: number) => void;
  onSlotSelect: (slot: number | null) => void;
  selectedSlot: number | null;
}) {
  const page = settings.pages[settings.activePage];
  const bindings = BINDINGS[settings.scheme];
  const slotBindings = [bindings.action1!, bindings.action2!, bindings.action3!];
  const swapBinding = bindings.paletteSwap!;

  return (
    <div style={styles.paletteContainer as React.CSSProperties}>
      {/* Swap button */}
      <div style={styles.swapPill}>
        <img src={swapBinding.images[0]} alt="" style={{ width: 24, height: 24 }} />
        <span>Swap</span>
      </div>

      {/* 3 action slots */}
      <div style={styles.paletteRow}>
        {page.slots.map((slot, i) => (
          <div
            key={i}
            style={{
              ...styles.paletteSlot(selectedSlot === i),
              // J and L raised, K lower (diamond-ish)
              marginBottom: i === 1 ? 0 : 12,
            }}
            onClick={() => onSlotSelect(selectedSlot === i ? null : i)}
          >
            <div style={styles.slotKey}>
              {slotBindings[i].images[0]
                ? <img src={slotBindings[i].images[0]} alt="" style={{ width: 20, height: 20 }} />
                : <span style={{ fontSize: 9, color: '#888' }}>{slotBindings[i].fallbackText}</span>
              }
            </div>
            <div style={styles.slotLabel}>{slot.label}</div>
          </div>
        ))}
      </div>

      {/* Page dots */}
      <div style={styles.pageIndicator}>
        {settings.pages.map((_, i) => (
          <div
            key={i}
            style={styles.pageDot(i === settings.activePage)}
            onClick={() => onPageChange(i)}
          />
        ))}
      </div>
    </div>
  );
}

function SlotEditor({
  slot,
  slotIndex,
  onChange,
}: {
  slot: ActionSlot;
  slotIndex: number;
  onChange: (action: ActionSlot) => void;
}) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <span style={{ fontSize: 12, color: '#888', width: 50 }}>Slot {slotIndex + 1}:</span>
      <select
        style={styles.editSlotSelect}
        value={slot.id}
        onChange={e => {
          const action = ALL_ACTIONS.find(a => a.id === e.target.value);
          if (action) onChange(action);
        }}
      >
        {ALL_ACTIONS.map(a => (
          <option key={a.id} value={a.id}>{a.label}</option>
        ))}
      </select>
    </div>
  );
}

// ── Main Component ───────────────────────────────────────────────────────────

export default function SettingsMockup() {
  const [settings, setSettings] = useState<ControlSettings>({
    scheme: 'keyboard_mouse',
    pages: DEFAULT_PAGES,
    activePage: 0,
  });
  const [selectedSlot, setSelectedSlot] = useState<number | null>(null);

  const setScheme = useCallback((scheme: ControlScheme) => {
    setSettings(prev => ({ ...prev, scheme }));
  }, []);

  const setActivePage = useCallback((page: number) => {
    setSettings(prev => ({ ...prev, activePage: page }));
    setSelectedSlot(null);
  }, []);

  const updateSlot = useCallback((slotIndex: number, action: ActionSlot) => {
    setSettings(prev => {
      const newPages = prev.pages.map((p, pi) => {
        if (pi !== prev.activePage) return p;
        const newSlots = [...p.slots] as [ActionSlot, ActionSlot, ActionSlot];
        newSlots[slotIndex] = action;
        return { ...p, slots: newSlots };
      });
      return { ...prev, pages: newPages };
    });
  }, []);

  const addPage = useCallback(() => {
    setSettings(prev => ({
      ...prev,
      pages: [...prev.pages, { slots: [ALL_ACTIONS[0], ALL_ACTIONS[0], ALL_ACTIONS[0]] }],
      activePage: prev.pages.length,
    }));
    setSelectedSlot(null);
  }, []);

  const removePage = useCallback(() => {
    setSettings(prev => {
      if (prev.pages.length <= 1) return prev;
      const newPages = prev.pages.filter((_, i) => i !== prev.activePage);
      return {
        ...prev,
        pages: newPages,
        activePage: Math.min(prev.activePage, newPages.length - 1),
      };
    });
    setSelectedSlot(null);
  }, []);

  const bindings = BINDINGS[settings.scheme];
  const currentPage = settings.pages[settings.activePage];

  return (
    <div style={styles.container}>
      {/* Sidebar: control scheme selector */}
      <div style={styles.sidebar as React.CSSProperties}>
        <div style={{ fontSize: 14, fontWeight: 600, color: '#88aaff', marginBottom: 8 }}>
          Control Scheme
        </div>
        {(Object.keys(SCHEME_LABELS) as ControlScheme[]).map(scheme => (
          <button
            key={scheme}
            style={styles.schemeButton(settings.scheme === scheme)}
            onClick={() => setScheme(scheme)}
          >
            {SCHEME_LABELS[scheme]}
          </button>
        ))}

        <div style={{ marginTop: 'auto', fontSize: 11, color: '#555', lineHeight: 1.5 }}>
          Designed for minimal Android controllers: D-pad, ABXY, Start, L, R.
          No analog sticks required.
        </div>
      </div>

      {/* Main content */}
      <div style={styles.main as React.CSSProperties}>
        {/* Bindings overview */}
        <div style={styles.section}>
          <div style={styles.sectionTitle as React.CSSProperties}>
            Controls — {SCHEME_LABELS[settings.scheme]}
          </div>
          {Object.entries(bindings).map(([key, binding]) => {
            // Hide separate Start row for gamepad (Start = Pause)
            if (key === 'start' && settings.scheme.startsWith('gamepad')) return null;
            return (
              <BindingRow
                key={key}
                label={binding.label}
                images={binding.images}
                fallbackText={binding.fallbackText}
              />
            );
          })}
        </div>

        {/* Action palette editor */}
        <div style={styles.section}>
          <div style={styles.sectionTitle as React.CSSProperties}>
            Action Palette
          </div>
          <div style={{ display: 'flex', gap: 32, alignItems: 'flex-start' }}>
            {/* Live palette preview */}
            <PalettePreview
              settings={settings}
              onPageChange={setActivePage}
              onSlotSelect={setSelectedSlot}
              selectedSlot={selectedSlot}
            />

            {/* Page editor */}
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 12 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 13, color: '#aaa' }}>
                  Page {settings.activePage + 1} / {settings.pages.length}
                </span>
                <button
                  onClick={addPage}
                  style={{
                    padding: '4px 10px',
                    background: '#2a2a4a',
                    border: '1px solid #444',
                    borderRadius: 4,
                    color: '#88aaff',
                    cursor: 'pointer',
                    fontSize: 11,
                  }}
                >
                  + Page
                </button>
                {settings.pages.length > 1 && (
                  <button
                    onClick={removePage}
                    style={{
                      padding: '4px 10px',
                      background: '#2a2a4a',
                      border: '1px solid #444',
                      borderRadius: 4,
                      color: '#ff6666',
                      cursor: 'pointer',
                      fontSize: 11,
                    }}
                  >
                    - Page
                  </button>
                )}
              </div>

              {/* Slot assignments */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {currentPage.slots.map((slot, i) => (
                  <SlotEditor
                    key={i}
                    slot={slot}
                    slotIndex={i}
                    onChange={action => updateSlot(i, action)}
                  />
                ))}
              </div>

              <div style={{ fontSize: 11, color: '#555', marginTop: 8, lineHeight: 1.6 }}>
                Each page has 3 action slots. Press <strong style={{ color: '#888' }}>R</strong> (or <strong style={{ color: '#888' }}>I</strong> on keyboard) to cycle pages during gameplay.
                <br />
                Attack is typically slot 1. Techniques, items, and dodge can fill any slot.
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
