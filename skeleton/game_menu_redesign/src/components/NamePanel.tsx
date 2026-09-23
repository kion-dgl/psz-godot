import Frame from "./Frame";

type Props = { name: string; hp: number; maxHp: number };

export default function NamePanel({ name, hp, maxHp }: Props) {
  const pct = Math.max(0, Math.min(1, hp / maxHp));

  return (
    <section
      aria-label="Character"
      className="absolute anim-left"
      style={{ left: 32, top: 48, width: 335, height: 114, animationDelay: "0ms" }}
    >
      {/* 
        Silhouette matching the original prototype:
        Chamfered top-left, horizontal top edge, angled step-down on the right,
        and slanted right edge returning to a chamfered bottom edge.
      */}
      <Frame
        width={335}
        height={114}
        points="22,0 215,0 228,14 228,24 332,24 296,112 24,112 0,88 0,22"
        inner={[{ points: "10,34 322,34 290,102 10,102" }]}
      />

      {/* Leader golden star sitting atop the top edge */}
      <svg
        className="absolute drop-shadow-[0_1px_1px_rgba(0,0,0,0.35)]"
        style={{ left: 58, top: 4 }}
        width="22"
        height="22"
        viewBox="0 0 22 22"
        aria-hidden="true"
      >
        <polygon
          points="11,1 13.8,7.8 21,8.3 15.6,12.8 17.4,20 11,16 4.6,20 6.4,12.8 1,8.3 8.2,7.8"
          fill="#ffd738"
          stroke="#423004"
          strokeWidth="1.6"
          strokeLinejoin="round"
        />
      </svg>

      {/* Red orb status badge */}
      <div
        className="absolute rounded-full flex items-center justify-center"
        style={{
          left: 14,
          top: 38,
          width: 42,
          height: 42,
          boxShadow: "0 0 0 2px #ffffff, 0 0 0 3.5px #243c68, 0 2px 4px rgba(0,0,0,0.3)",
          background:
            "radial-gradient(circle at 35% 30%, #ff9898 0%, #ee2c2c 35%, #9b0b0b 85%, #590404 100%)",
        }}
        aria-hidden="true"
      >
        {/* Subtle specular glint */}
        <span
          className="w-2.5 h-2 rounded-full absolute"
          style={{
            top: 6,
            left: 9,
            background: "radial-gradient(circle, rgba(255,255,255,0.85) 0%, rgba(255,255,255,0) 80%)",
          }}
        />
      </div>

      {/* Character Name */}
      <h1
        className="absolute pixel-text stage-text select-none m-0"
        style={{ left: 66, top: 33, fontSize: 48, color: "#121212", letterSpacing: "0.02em" }}
      >
        {name}
      </h1>

      {/* HP Bar */}
      <div
        className="absolute overflow-hidden"
        role="meter"
        aria-label="HP"
        aria-valuemin={0}
        aria-valuemax={maxHp}
        aria-valuenow={hp}
        style={{
          left: 68,
          top: 80,
          width: 195,
          height: 18,
          backgroundColor: "#133525",
          boxShadow: "0 0 0 1.5px #ffffff, 0 0 0 2.5px #243c68",
        }}
      >
        <div
          className="h-full transition-[width] duration-500 ease-out"
          style={{
            width: `${pct * 100}%`,
            background:
              "linear-gradient(180deg, #a4f5c5 0%, #7cf0aa 35%, #3bc87e 36%, #28aa63 100%)",
          }}
        />
      </div>
    </section>
  );
}
