import Frame from "./Frame";
import type { StatRow } from "../data";
import { cn } from "../utils/cn";

type Props = {
  pages: StatRow[][];
  page: number;
  onPage: (next: number) => void;
};

function ShoulderKey({ label, onClick }: { label: string; onClick?: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={`Page key ${label}`}
      className="inline-flex items-center justify-center pixel-text stage-text select-none cursor-pointer outline-none transition-transform duration-100 active:scale-95 hover:brightness-110"
      style={{
        width: 48,
        height: 38,
        fontSize: 42,
        color: "#ffffff",
        backgroundColor: "#0d0d0d",
        boxShadow: "0 0 0 2px #ffffff, 0 0 0 3.5px #1a2a44, 0 2px 3px rgba(0,0,0,0.3)",
        borderRadius: 3,
      }}
    >
      {label}
    </button>
  );
}

function Arrow({ dir, onClick, label }: { dir: "left" | "right"; onClick: () => void; label: string }) {
  const points = dir === "left" ? "22,2 22,32 4,17" : "4,2 4,32 22,17";
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      className={cn(
        "group inline-flex items-center justify-center cursor-pointer outline-none",
        "transition-transform duration-150 hover:scale-115 active:scale-90",
        dir === "left" ? "hover:-translate-x-[2px]" : "hover:translate-x-[2px]",
      )}
      style={{ width: 30, height: 38 }}
    >
      <svg width="26" height="34" viewBox="0 0 26 34" aria-hidden="true">
        <polygon
          points={points}
          fill="#3bd57d"
          stroke="#0d3521"
          strokeWidth="2.5"
          strokeLinejoin="miter"
          className="transition-[fill] duration-150 group-hover:fill-[#7af3a9]"
        />
      </svg>
    </button>
  );
}

export default function StatsPanel({ pages, page, onPage }: Props) {
  const rows = pages[page];
  const total = pages.length;

  const prev = () => onPage((page - 1 + total) % total);
  const next = () => onPage((page + 1) % total);

  return (
    <section
      aria-label="Character status"
      className="absolute anim-up"
      style={{ left: 630, top: 695, width: 650, height: 380, animationDelay: "240ms" }}
    >
      <Frame
        width={650}
        height={380}
        points="25,0 625,0 650,25 650,355 625,380 345,380 315,347 28,347 0,319 0,25"
        inner={[{ points: "16,66 634,66 634,324 16,324", tone: "sky" }]}
      />

      {/* Page switcher header */}
      <div
        className="absolute flex items-center justify-center gap-3"
        style={{ left: 0, right: 0, top: 16, height: 44 }}
      >
        <Arrow dir="left" label="Previous page" onClick={prev} />
        <ShoulderKey label="L" onClick={prev} />
        <span
          className="pixel-text stage-text select-none tabular-nums"
          style={{
            fontSize: 44,
            color: "#111111",
            letterSpacing: "0.08em",
            width: 96,
            textAlign: "center",
            textShadow: "0 0 2px #fff, 0 0 4px #fff",
          }}
          aria-live="polite"
        >
          {page + 1}/{total}
        </span>
        <ShoulderKey label="R" onClick={next} />
        <Arrow dir="right" label="Next page" onClick={next} />
      </div>

      {/* Stat rows */}
      <dl
        key={page}
        className="absolute m-0 anim-swap"
        style={{ left: 40, top: 72, width: 575 }}
      >
        {rows.map((row) => (
          <div
            key={row.label}
            className="flex items-center transition-colors duration-100 hover:bg-white/35"
            style={{ height: 49 }}
          >
            <dt
              className="pixel-text stage-text select-none"
              style={{
                fontSize: 48,
                color: "#111111",
                minWidth: row.inline ? 115 : undefined,
                letterSpacing: "0.02em",
              }}
            >
              {row.label}
            </dt>
            <dd
              className={cn(
                "pixel-text stage-text select-none m-0",
                row.inline ? "" : "ml-auto text-right",
              )}
              style={{
                fontSize: 48,
                color: "#111111",
                letterSpacing: row.numeric ? "0.26em" : "0.02em",
                marginRight: row.numeric ? "-0.26em" : 0,
              }}
            >
              {row.value}
            </dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
