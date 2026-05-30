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
    n: 7, label: 'City', href: '/journey/city/office', persona: 'new user', status: 'done',
    note: 'Autopilot completes creation (names the character “humar”) and spawns into the city Office. Skips the intro dialog, teleports to the Office exit, then walks the Counter → Office (briefing) → Counter → Warp arc as described in the next steps.',
  },
  {
    n: 8, label: 'Accept Quest', href: '/journey/city/counter', persona: 'new user', status: 'done',
    note: 'Autopilot teleports onto the Guild Counter NPC, presses interact to open the guild_counter overlay, then 3× ui_accept to select Search and Rescue → difficulty → confirm. SessionManager.has_accepted_quest() flips true.',
  },
  {
    n: 9, label: 'Quest Briefing', href: '/journey/city/office', persona: 'new user', status: 'done',
    note: 'After accepting, autopilot teleports back to the Office trigger — the briefing dialog auto-fires. ui_accept spam advances the 7-page briefing; exits when SessionManager.get_accepted_quest().briefing_shown flips true.',
  },
  {
    n: 10, label: 'Start Quest', href: '/journey/city/teleport', persona: 'new user', status: 'done',
    note: 'Autopilot teleports to the central WarpTeleporter pad, presses interact to open the warp_teleporter UI, then ui_accept to start the quest. Scene changes to valley_field — sanity check is green.',
  },
];

/** Find the autopilot step that owns a given page path (trailing slash tolerant). */
export function stepForPath(pathname: string): AutopilotStep | undefined {
  const p = pathname.replace(/\/$/, '');
  return AUTOPILOT_STEPS.find((s) => s.href.replace(/\/$/, '') === p);
}
