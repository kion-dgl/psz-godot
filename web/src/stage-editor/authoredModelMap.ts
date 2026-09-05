/**
 * Which storybook model renders an authored record, decided from pure data so
 * the overlay can know WHETHER a kind has a model without loading any GLBs.
 *
 * Sources of truth:
 *   - `m`, the source model the importer recorded (fences and switches carry
 *     one; containers and most traps do not).
 *   - The area key, for the per-field box/wall art in OBJECT_CATALOG — every
 *     field re-skins `oNN_cont`/`oNN_wall`, and the catalog carries one entry
 *     per field under `box-<dir>` / `wall-<dir>`.
 *
 * Kinds with NO model here stay as the coloured markers, deliberately: the
 * five elemental trap families (burn/capture/heal/heat/light/ice) are authored
 * as gameplay types with no identified model in the corpus — psz-re's dump
 * records no model for them (see import_re_objects.py) — and guessing one
 * would mislead the parity-checking this tab exists for.
 */

export type AuthoredModel =
  /** Hand-written storybook element (../elements), true scale. */
  | { component: 'element'; name: 'box' | 'rare-box' | 'wall' | 'needle-trap' }
  /** The fence family, variant chosen by the authored model name. */
  | { component: 'fence'; variant: 'default' | 'short' | 'diagonal' | 'four' }
  /** The switch family: step, remote, and the second step-switch mesh. */
  | { component: 'switch'; variant: 'step' | 'step-s' | 'remote' }
  /** A data-driven OBJECT_CATALOG entry, rendered via CatalogObject. */
  | { component: 'catalog'; entryId: string };

/** Stage-editor area key → catalog id of that field's container art. */
const FIELD_BOX: Record<string, string> = {
  wetlands: 'box-wetlands',
  snowfield: 'box-snowfield',
  makara: 'box-makara',
  paru: 'box-paru',
  arca: 'box-arca',
  shrine: 'box-shrine',
  tower: 'box-tower',
};

/** Same for walls; the tower ships none (sealed rooms), so it falls through
 * to the hand-written Valley wall rather than a wrong-field mesh. */
const FIELD_WALL: Record<string, string> = {
  wetlands: 'wall-wetlands',
  snowfield: 'wall-snowfield',
  makara: 'wall-makara',
  paru: 'wall-paru',
  arca: 'wall-arca',
  shrine: 'wall-shrine',
};

/**
 * The model for one authored record, or null when the kind renders as a
 * marker. `area` is the stage-editor area key (getAreaFromMapId).
 */
export function authoredModelFor(
  kind: string,
  m?: string | null,
  area?: string,
): AuthoredModel | null {
  switch (kind) {
    case 'box':
      // Valley (and city/unknown) use the hand-written element; the other
      // fields' distinct meshes live in the catalog.
      return area && FIELD_BOX[area]
        ? { component: 'catalog', entryId: FIELD_BOX[area] }
        : { component: 'element', name: 'box' };
    case 'wall':
      return area && FIELD_WALL[area]
        ? { component: 'catalog', entryId: FIELD_WALL[area] }
        : { component: 'element', name: 'wall' };
    case 'rare_box':
      return { component: 'element', name: 'rare-box' };
    case 'fence':
      switch (m) {
        case 'o0c_shfence':
          return { component: 'fence', variant: 'short' };
        case 'o0c_dgfance':
          return { component: 'fence', variant: 'diagonal' };
        case 'o0c_fence4':
          return { component: 'fence', variant: 'four' };
        default:
          return { component: 'fence', variant: 'default' };
      }
    case 'step_switch':
      switch (m) {
        case 'o0c_remswitch':
          return { component: 'switch', variant: 'remote' };
        case 'o0c_switchs':
          return { component: 'switch', variant: 'step-s' };
        default:
          return { component: 'switch', variant: 'step' };
      }
    case 'needler_trap':
      return { component: 'element', name: 'needle-trap' };
    case 'gun_trap':
      // Two turret meshes exist; the authored record does not say which, so
      // type 1 stands in for both.
      return { component: 'catalog', entryId: 'gun-trap-1' };
    case 'poison_trap':
      return { component: 'catalog', entryId: 'poison-trap' };
    default:
      return null;
  }
}
