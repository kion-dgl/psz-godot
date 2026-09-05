import { useEffect, useMemo } from 'react';
import { useGLTF } from '@react-three/drei';
import { Box, RareBox, Wall, NeedleTrap, Fence, Fence4, StepSwitch, RemoteSwitch } from '../elements';
import { OBJECT_CATALOG } from '../elements/objectCatalog';
import { CatalogObject } from '../elements/CatalogObject';
import { applyObjectTextures, detachSkinnedBind } from '../elements/materials';
import { assetUrl } from '../utils/assets';
import type { AuthoredModel } from './authoredModelMap';

/**
 * Renders one authored record as the storybook model for its kind, at the
 * record's position and facing, true scale. Statically imported by the
 * Authored overlay — React.lazy() never resolves inside the R3F canvas
 * reconciler, so the dynamic-import version left every model stuck on its
 * marker fallback; each GLB still suspends per-object behind a Suspense
 * boundary in the overlay. The mapping itself lives in authoredModelMap.ts
 * (pure data) so the overlay knows which records have a model without any
 * of the rendering concerns.
 *
 * The catalog entries resolve through assetUrl(), which points at the R2 CDN
 * in dev — the same dependency the stage GLBs already carry.
 */

/** o0c_switchs: the second step-switch mesh, with no storybook element of its
 * own — loaded raw with the shared mirrored-repeat texture convention. */
function SwitchSModel() {
  const url = assetUrl('/assets/objects/valley/o0c_switchs.glb');
  const { scene } = useGLTF(url);
  const cloned = useMemo(() => scene.clone(), [scene]);
  useEffect(() => {
    detachSkinnedBind(cloned);
    applyObjectTextures(cloned);
  }, [cloned]);
  return <primitive object={cloned} />;
}

const ELEMENTS = {
  box: Box,
  'rare-box': RareBox,
  wall: Wall,
  'needle-trap': NeedleTrap,
} as const;

export default function AuthoredObjectModel({ model }: { model: AuthoredModel }) {
  switch (model.component) {
    case 'element': {
      const Component = ELEMENTS[model.name];
      return <Component />;
    }
    case 'fence':
      return model.variant === 'four' ? <Fence4 /> : <Fence variant={model.variant} />;
    case 'switch':
      switch (model.variant) {
        case 'remote':
          return <RemoteSwitch />;
        case 'step-s':
          return <SwitchSModel />;
        default:
          return <StepSwitch />;
      }
    case 'catalog': {
      const entry = OBJECT_CATALOG.find((e) => e.id === model.entryId);
      return entry ? <CatalogObject entry={entry} /> : null;
    }
  }
}
