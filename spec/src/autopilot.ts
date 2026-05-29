// Single source of truth for the autopilot playthrough.
//
// The autopilot (scripts/autoloads/autopilot.gd, driven by
// scripts/tools/autoplay/sanity_check.sh) walks the game as an ordered series
// of steps. Each step maps to a user-journey screen. `status: 'done'` means the
// autopilot already drives + asserts that step; 'todo' means it's planned.
//
// Flip a status here and the nav, the /autopilot flow diagram, and the per-page
// "Autopilot" note on each journey page all update together.

export type StepStatus = 'done' | 'todo';

export interface AutopilotStep {
  n: number;
  label: string;
  href: string;
  persona: string;
  status: StepStatus;
  /** What the autopilot asserts at this step (shown in the per-page note). */
  note: string;
}

export const AUTOPILOT_STEPS: AutopilotStep[] = [
  {
    n: 1, label: 'Splash Screen', href: '/journey/splash', persona: 'new user', status: 'done',
    note: 'Asserts the engine boots and bootstrap.tscn starts (the [bootstrap] banner).',
  },
  {
    n: 2, label: 'Download Content', href: '/journey/download', persona: 'new user', status: 'done',
    note: 'Asserts the asset pack mounts before continuing (cache-hit or local copy; the harness uses the local dist pack so it stays offline).',
  },
  {
    n: 3, label: 'Controls Setup', href: '/journey/controls', persona: 'new user', status: 'done',
    note: 'First-run only: asserts the controller-config screen appears, then injects a keypress to pick the keyboard scheme.',
  },
  {
    n: 4, label: 'Title Screen', href: '/journey/title', persona: 'new user', status: 'done',
    note: 'Autopilot presses Start (ui_accept) to leave the title for character select.',
  },
  {
    n: 5, label: 'Character Select', href: '/journey/character-select', persona: 'new user', status: 'done',
    note: 'Autopilot accepts on the default slot to begin a new character.',
  },
  {
    n: 6, label: 'Create Character', href: '/journey/create-character', persona: 'new user', status: 'done',
    note: 'Autopilot reaches the create wizard (CLASS_SELECT → APPEARANCE → NAME_ENTRY → CONFIRM). Appearance/customize is a step inside this wizard, not a separate screen. Completing it through name entry into the city is the next step.',
  },
  {
    n: 7, label: 'City', href: '/journey/city/counter', persona: 'new user', status: 'todo',
    note: 'Planned: finish character creation (past name entry) and spawn into the city hub, then walk to the quest counter / teleporter.',
  },
];

/** Find the autopilot step that owns a given page path (trailing slash tolerant). */
export function stepForPath(pathname: string): AutopilotStep | undefined {
  const p = pathname.replace(/\/$/, '');
  return AUTOPILOT_STEPS.find((s) => s.href.replace(/\/$/, '') === p);
}
