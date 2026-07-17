// Shared portal/gate rotation math. Single source of truth for
// DIRECTION_ROTATIONS + getPortalRotation (previously duplicated in
// stage-editor/types.ts and quest-editor/utils/quest-io.ts).

// Rotation values for each direction (radians, Y-axis rotation)
// Outward vector = [-sin(r), -cos(r)]: north→-Z, south→+Z, east→+X, west→-X
export const DIRECTION_ROTATIONS: Record<string, number> = {
  north: 0,
  south: Math.PI,
  east: -Math.PI / 2,
  west: Math.PI / 2,
};

// Get effective rotation for a portal (base direction + optional offset)
export function getPortalRotation(portal: { direction: string; rotationOffset?: number }): number {
  return (DIRECTION_ROTATIONS[portal.direction] ?? 0) + ((portal.rotationOffset || 0) * Math.PI) / 180;
}
