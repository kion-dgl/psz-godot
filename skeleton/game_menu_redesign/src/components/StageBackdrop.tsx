import { OCTAGON_PATTERN_SVG } from "./OctagonBackdrop";

/**
 * StageBackdrop renders the exact multi-layer atmospheric background from the game prototype:
 * 1. Base clean white stage.
 * 2. Left vertical sci-fi column (x: 0..265px) with unified seamless octagon tiling.
 * 3. Bottom atmospheric band with the same unified octagon tiling (in-phase with the left column).
 * 4. Soft fade-out of the octagons toward the bottom-right corner, revealing the soft blue wash.
 * 5. Crisp white vertical boundary at x = 265px.
 */
export default function StageBackdrop() {
  return (
    <div className="absolute inset-0 pointer-events-none select-none overflow-hidden" aria-hidden="true">
      {/* Base white surface */}
      <div className="absolute inset-0 bg-white" />

      {/* Bottom atmospheric soft blue wash */}
      <div
        className="absolute left-0 right-0 bottom-0"
        style={{
          top: 620,
          background:
            "linear-gradient(180deg, rgba(255,255,255,0) 0%, #d8e5f5 25%, #c8ddf3 65%, #bdd5f0 100%)",
        }}
      />

      {/* Bottom-right soft periwinkle atmospheric glow */}
      <div
        className="absolute right-0 bottom-0 pointer-events-none"
        style={{
          width: 900,
          height: 500,
          background:
            "radial-gradient(ellipse at 85% 90%, rgba(195, 218, 246, 0.7) 0%, rgba(210, 228, 248, 0.35) 45%, rgba(255,255,255,0) 75%)",
        }}
      />

      {/* 
        Unified Seamless Octagon Pattern Layer:
        Uses a single full-stage coordinate space so that every octagon in the left column
        and every octagon in the bottom band align to the exact same (0,0) grid.
      */}
      <div
        className="absolute inset-0"
        style={{
          backgroundImage: `url("${OCTAGON_PATTERN_SVG}")`,
          backgroundSize: "72px 72px",
          backgroundPosition: "0 0",
          backgroundRepeat: "repeat",
          /* 
            Mask: Shows fully on the left strip (x: 0..265) full height,
            and across the bottom band (y: 640..1080) fading out toward x = 1350.
          */
          maskImage: `
            linear-gradient(to right, #000 0px, #000 265px, transparent 265px),
            linear-gradient(to bottom, transparent 640px, #000 700px),
            linear-gradient(to right, #000 70%, transparent 92%)
          `,
          maskComposite: "add, intersect",
          WebkitMaskComposite: "source-over, source-in",
        }}
      />

      {/* Fallback explicit mask layers for maximum cross-browser fidelity */}
      {/* 1. Left strip octagons on blue */}
      <div
        className="absolute left-0 top-0 bottom-0"
        style={{
          width: 265,
          backgroundColor: "#c5d9f0",
          backgroundImage: `url("${OCTAGON_PATTERN_SVG}")`,
          backgroundSize: "72px 72px",
          backgroundPosition: "0 0",
          backgroundRepeat: "repeat",
        }}
      >
        {/* Soft top-down atmospheric lighting */}
        <div
          className="absolute inset-0"
          style={{
            background:
              "linear-gradient(180deg, rgba(255,255,255,0.65) 0%, rgba(255,255,255,0.2) 20%, rgba(255,255,255,0) 55%)",
          }}
        />
        {/* Crisp boundary line between left column and white space */}
        <div
          className="absolute top-0 bottom-0 right-0 w-[2px]"
          style={{
            background:
              "linear-gradient(180deg, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0.8) 60%, rgba(255,255,255,0.4) 100%)",
            boxShadow: "1px 0 3px rgba(47,76,124,0.08)",
          }}
        />
      </div>

      {/* 2. Bottom band octagons on blue (x: 265..1920, y: 640..1080) perfectly in-phase */}
      <div
        className="absolute left-[265px] right-0 bottom-0"
        style={{
          top: 640,
          backgroundImage: `url("${OCTAGON_PATTERN_SVG}")`,
          backgroundSize: "72px 72px",
          /* background-position: -265px -640px preserves the exact stage (0,0) alignment! */
          backgroundPosition: "-265px -640px",
          backgroundRepeat: "repeat",
          maskImage: "linear-gradient(to right, #000 0%, #000 55%, transparent 92%), linear-gradient(to bottom, transparent 0%, #000 50px, #000 100%)",
          maskComposite: "intersect",
          WebkitMaskImage: "linear-gradient(to right, #000 0%, #000 55%, rgba(0,0,0,0) 90%)",
        }}
      />
    </div>
  );
}
