export interface FaceMark {
  meshName: string;
  faceIndex: number;
  v0: [number, number, number];
  v1: [number, number, number];
  v2: [number, number, number];
}

export type ActionEntry =
  | { kind: 'mesh'; name: string }
  | { kind: 'face'; mark: FaceMark };

export type Mode = 'mesh' | 'face' | 'place';

export type TransformMode = 'translate' | 'rotate' | 'scale';

/** Cart placement state. Stored as plain euler XYZ + uniform-axis arrays
 *  so it round-trips cleanly through localStorage and is easy to feed
 *  back into a three.js Object3D's transform on next mount. */
export interface CartTransform {
  pos: [number, number, number];
  /** Euler XYZ rotation, radians. */
  rot: [number, number, number];
  scale: [number, number, number];
}

export const DEFAULT_CART_TRANSFORM: CartTransform = {
  // Anchor near the WeaponShopNPC position from city_market_controller.gd
  // so the cart starts visible and roughly where the original geometry is.
  pos: [-6.78, 0, 21.81],
  rot: [0, 0.7835, 0],
  scale: [1, 1, 1],
};

export function faceKey(m: FaceMark): string {
  const r = (v: [number, number, number]) =>
    `${v[0].toFixed(3)},${v[1].toFixed(3)},${v[2].toFixed(3)}`;
  return `${r(m.v0)}|${r(m.v1)}|${r(m.v2)}`;
}
