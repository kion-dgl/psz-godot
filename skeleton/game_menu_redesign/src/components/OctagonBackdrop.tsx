/**
 * Seamless Octagon & Diamond pattern (Truncated Square Tiling).
 * 
 * In this tiling:
 * - Period is S = 72px.
 * - Corner chamfer is c = 21px.
 * - Straight edge length is S - 2c = 30px.
 * - Diagonal chamfer length is c * sqrt(2) = 29.70px.
 * - All octagons have 8 sides of length ~30px.
 * - All diamonds between 4 octagons have 4 sides of length ~29.7px.
 * - Lines connect seamlessly across tile boundaries with zero seam artifacts.
 */
export const OCTAGON_PATTERN_SVG = `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='72' height='72' viewBox='0 0 72 72'%3E%3Cpath d='M36,15 L57,36 L36,57 L15,36 Z M36,-1 L36,15 M36,57 L36,73 M-1,36 L15,36 M57,36 L73,36' fill='none' stroke='%23ffffff' stroke-width='2.2' stroke-linecap='square' stroke-opacity='0.48' /%3E%3C/svg%3E`;

type OctagonBackdropProps = {
  className?: string;
  style?: React.CSSProperties;
  opacity?: number;
};

export default function OctagonBackdrop({ className = "", style = {}, opacity = 1 }: OctagonBackdropProps) {
  return (
    <div
      aria-hidden="true"
      className={`pointer-events-none ${className}`}
      style={{
        backgroundImage: `url("${OCTAGON_PATTERN_SVG}")`,
        backgroundSize: "72px 72px",
        backgroundRepeat: "repeat",
        opacity,
        ...style,
      }}
    />
  );
}
