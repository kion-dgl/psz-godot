import { useId } from "react";

export type InnerArea = {
  points: string;
  /** "paper" = white lined area, "sky" = light blue lined area */
  tone?: "paper" | "sky";
};

type FrameProps = {
  width: number;
  height: number;
  /** Outer chamfered polygon, in local coordinates */
  points: string;
  inner?: InnerArea[];
};

/**
 * Draws the classic chamfered blue window frame:
 * 1. Outer crisp white halo border (glow/stroke).
 * 2. Deep navy outer contour line.
 * 3. Vertical soft blue gradient with fine horizontal scanlines.
 * 4. Inset inner windows (lined white paper or lined sky-blue) with dual white/navy borders.
 */
export default function Frame({ width, height, points, inner = [] }: FrameProps) {
  const id = useId().replace(/:/g, "");
  const grad = `grad-${id}`;
  const scan = `scan-${id}`;
  const paper = `paper-${id}`;
  const sky = `sky-${id}`;

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className="absolute inset-0 overflow-visible pointer-events-none"
      aria-hidden="true"
      shapeRendering="crispEdges"
    >
      <defs>
        {/* Soft vertical blue gradient for the frame surface */}
        <linearGradient id={grad} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#c8dbf4" />
          <stop offset="50%" stopColor="#b6d0ee" />
          <stop offset="100%" stopColor="#9dbde6" />
        </linearGradient>

        {/* Fine scanline texture on the blue frame */}
        <pattern id={scan} width="4" height="4" patternUnits="userSpaceOnUse">
          <rect width="4" height="1" fill="#ffffff" fillOpacity="0.42" />
          <rect y="2" width="4" height="1" fill="#204070" fillOpacity="0.08" />
        </pattern>

        {/* Paper texture for Menu and Description panels (light white with soft blue-grey rules) */}
        <pattern id={paper} width="4" height="4" patternUnits="userSpaceOnUse">
          <rect width="4" height="4" fill="#f8fafd" />
          <rect y="2" width="4" height="1" fill="#dbe5f2" />
        </pattern>

        {/* Sky texture for Stats panel (light pastel blue with white scanlines) */}
        <pattern id={sky} width="4" height="4" patternUnits="userSpaceOnUse">
          <rect width="4" height="4" fill="#cfe0f6" />
          <rect y="2" width="4" height="1" fill="#b9d1ee" />
        </pattern>
      </defs>

      {/* 1. White outer halo (prominent in the original HUD) */}
      <polygon
        points={points}
        fill="none"
        stroke="#ffffff"
        strokeWidth="6"
        strokeLinejoin="miter"
      />

      {/* 2. Main frame fill: gradient + scanlines */}
      <polygon
        points={points}
        fill={`url(#${grad})`}
        stroke="#274676"
        strokeWidth="2.5"
        strokeLinejoin="miter"
      />
      <polygon
        points={points}
        fill={`url(#${scan})`}
        stroke="none"
      />

      {/* 3. Inset inner windows */}
      {inner.map((area, i) => (
        <g key={i}>
          {/* White inner frame border */}
          <polygon
            points={area.points}
            fill={area.tone === "sky" ? `url(#${sky})` : `url(#${paper})`}
            stroke="#ffffff"
            strokeWidth="3.5"
            strokeLinejoin="miter"
          />
          {/* Crisp navy dividing line */}
          <polygon
            points={area.points}
            fill="none"
            stroke="#2e4d7d"
            strokeWidth="1.6"
            strokeLinejoin="miter"
          />
        </g>
      ))}
    </svg>
  );
}
