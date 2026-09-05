import { describe, it, expect } from 'vitest';
import { authoredModelFor } from '../stage-editor/authoredModelMap';

describe('authoredModelFor', () => {
  it('containers and walls use the per-field catalog art outside the valley', () => {
    expect(authoredModelFor('box', null, 'snowfield')).toEqual({
      component: 'catalog',
      entryId: 'box-snowfield',
    });
    expect(authoredModelFor('wall', null, 'shrine')).toEqual({
      component: 'catalog',
      entryId: 'wall-shrine',
    });
  });

  it('valley (and unknown areas) fall back to the hand-written elements', () => {
    expect(authoredModelFor('box', null, 'valley')).toEqual({ component: 'element', name: 'box' });
    expect(authoredModelFor('wall', null, undefined)).toEqual({ component: 'element', name: 'wall' });
    // The tower ships no wall of its own (sealed rooms) — element, not a
    // wrong-field mesh.
    expect(authoredModelFor('wall', null, 'tower')).toEqual({ component: 'element', name: 'wall' });
    expect(authoredModelFor('box', null, 'tower')).toEqual({
      component: 'catalog',
      entryId: 'box-tower',
    });
  });

  it('fences pick their variant from the authored model name', () => {
    expect(authoredModelFor('fence', 'o0c_fence')).toEqual({
      component: 'fence',
      variant: 'default',
    });
    expect(authoredModelFor('fence', 'o0c_shfence')).toEqual({ component: 'fence', variant: 'short' });
    expect(authoredModelFor('fence', 'o0c_dgfance')).toEqual({
      component: 'fence',
      variant: 'diagonal',
    });
    expect(authoredModelFor('fence', 'o0c_fence4')).toEqual({ component: 'fence', variant: 'four' });
    // No recorded model: the common fence.
    expect(authoredModelFor('fence', null)).toEqual({ component: 'fence', variant: 'default' });
  });

  it('switches pick their variant from the authored model name', () => {
    expect(authoredModelFor('step_switch', 'o0c_switchf')).toEqual({
      component: 'switch',
      variant: 'step',
    });
    expect(authoredModelFor('step_switch', 'o0c_switchs')).toEqual({
      component: 'switch',
      variant: 'step-s',
    });
    expect(authoredModelFor('step_switch', 'o0c_remswitch')).toEqual({
      component: 'switch',
      variant: 'remote',
    });
  });

  it('the named traps map to their models; the elemental families stay markers', () => {
    expect(authoredModelFor('needler_trap')).toEqual({ component: 'element', name: 'needle-trap' });
    expect(authoredModelFor('gun_trap')).toEqual({ component: 'catalog', entryId: 'gun-trap-1' });
    expect(authoredModelFor('poison_trap', 'o0c_poisonm')).toEqual({
      component: 'catalog',
      entryId: 'poison-trap',
    });
    // No identified model — deliberately markers, not a guess.
    for (const k of ['burn_trap', 'capture_trap', 'heal_trap', 'heat_trap', 'light_trap', 'ice_trap']) {
      expect(authoredModelFor(k), k).toBeNull();
    }
  });
});
