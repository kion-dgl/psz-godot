import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { planQuest } from '../../../scripts/tools/quest_plan';
const directory = resolve(import.meta.dirname, '../../../data/quests');
const load = (id: string) => JSON.parse(readFileSync(resolve(directory, `${id}.json`), 'utf8'));

describe('first-visit quest collection', () => {
  it('removes DOE B item-only returns while keeping key before gate', () => {
    const section = planQuest(load('deep_ore_extraction')).sections[2];
    for (const pos of ['1,1', '0,1']) {
      const visits = section.steps.filter(s => s._pos === pos);
      expect(visits[0].do).toContain('pickup_quest_item');
      expect(visits.filter(s => s.do.includes('pickup_quest_item'))).toHaveLength(1);
    }
    expect(section.steps.length).toBeLessThan(20);
    const key = section.steps.findIndex(s => s.do.includes('pickup_key'));
    const gate = section.steps.findIndex(s => s.do.includes('open_gate'));
    expect(key).toBeLessThan(gate);
  });
  it('keeps every shipped route adjacent, all cells visited and terminal waits last', () => {
    for (const filename of readdirSync(directory).filter(n => n.endsWith('.json') && n !== 'manifest.json')) {
      const quest = load(filename.slice(0, -5));
      const plan = planQuest(quest);
      for (const section of plan.sections) {
        const visited = new Set(section.steps.map(s => s._pos));
        for (const cell of section.cells) expect(visited.has(cell.pos), `${filename}/${cell.pos}`).toBe(true);
        for (let i = 0; i < section.steps.length - 1; i++) {
          const step = section.steps[i];
          const cell = section.cells.find(c => c.pos === step._pos)!;
          expect(cell.connections[step.exit], `${filename}/${step.label}`).toBe(section.steps[i + 1]._pos);
          expect(step.do).not.toContain('wait_quest_complete');
        }
      }
    }
  });
});
