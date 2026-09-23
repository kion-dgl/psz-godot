import { useCallback, useEffect, useRef, useState } from "react";
import NamePanel from "./components/NamePanel";
import MenuPanel from "./components/MenuPanel";
import DescriptionPanel from "./components/DescriptionPanel";
import StatsPanel from "./components/StatsPanel";
import StageBackdrop from "./components/StageBackdrop";
import { MENU_ITEMS, STAT_PAGES } from "./data";

const STAGE_W = 1920;
const STAGE_H = 1080;

function useStageScale() {
  const [scale, setScale] = useState(1);
  useEffect(() => {
    const update = () =>
      setScale(Math.min(window.innerWidth / STAGE_W, window.innerHeight / STAGE_H));
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);
  return scale;
}

export default function App() {
  const scale = useStageScale();
  const [selected, setSelected] = useState(0);
  const [page, setPage] = useState(0);
  const [flash, setFlash] = useState<string | null>(null);
  const flashTimer = useRef<number | undefined>(undefined);

  const activate = useCallback((i: number) => {
    const item = MENU_ITEMS[i];
    setFlash(item.disabled ? "Cannot be used here." : `Opening ${item.label}...`);
    window.clearTimeout(flashTimer.current);
    flashTimer.current = window.setTimeout(() => setFlash(null), 1200);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      switch (e.key) {
        case "ArrowDown":
        case "s":
        case "S":
          e.preventDefault();
          setSelected((s) => (s + 1) % MENU_ITEMS.length);
          break;
        case "ArrowUp":
        case "w":
        case "W":
          e.preventDefault();
          setSelected((s) => (s - 1 + MENU_ITEMS.length) % MENU_ITEMS.length);
          break;
        case "ArrowLeft":
        case "q":
        case "Q":
          e.preventDefault();
          setPage((p) => (p - 1 + STAT_PAGES.length) % STAT_PAGES.length);
          break;
        case "ArrowRight":
        case "e":
        case "E":
          e.preventDefault();
          setPage((p) => (p + 1) % STAT_PAGES.length);
          break;
        case "Enter":
        case " ":
          e.preventDefault();
          setSelected((s) => {
            activate(s);
            return s;
          });
          break;
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [activate]);

  const description = flash ?? MENU_ITEMS[selected].description;

  return (
    <div className="octagon-pattern fixed inset-0 flex items-center justify-center bg-[#b8cde8]">
      {/* 
        1920x1080 Stage:
        Maintains pixel-perfect coordinates, scale, and layout of the prototype,
        scaling uniformly to fill any desktop display or aspect ratio.
      */}
      <main
        className="relative overflow-hidden bg-white shadow-[0_20px_50px_rgba(30,50,80,0.35),0_0_0_1px_rgba(47,76,124,0.3)]"
        style={{
          width: STAGE_W,
          height: STAGE_H,
          transform: `scale(${scale})`,
          transformOrigin: "center center",
          flexShrink: 0,
        }}
      >
        {/* Authentic Multi-layer Octagon Background */}
        <StageBackdrop />

        {/* HUD Panels */}
        <NamePanel name="Flauros" hp={100} maxHp={100} />
        <MenuPanel
          items={MENU_ITEMS}
          selected={selected}
          onSelect={setSelected}
          onActivate={activate}
        />
        <DescriptionPanel text={description} />
        <StatsPanel pages={STAT_PAGES} page={page} onPage={setPage} />

        {/* Sci-fi HUD Footer Controls Guide */}
        <footer
          className="absolute flex items-center gap-6 pixel-text stage-text select-none anim-up"
          style={{
            right: 42,
            bottom: 24,
            fontSize: 28,
            color: "#274676",
            opacity: 0.82,
            letterSpacing: "0.04em",
            animationDelay: "400ms",
          }}
          aria-label="Controls guide"
        >
          <span className="flex items-center gap-1.5">
            <kbd className="px-1.5 py-0.5 bg-white/70 border border-[#274676]/40 rounded text-xs">↑↓ / W S</kbd> Select
          </span>
          <span className="flex items-center gap-1.5">
            <kbd className="px-1.5 py-0.5 bg-white/70 border border-[#274676]/40 rounded text-xs">←→ / Q E</kbd> Page
          </span>
          <span className="flex items-center gap-1.5">
            <kbd className="px-1.5 py-0.5 bg-white/70 border border-[#274676]/40 rounded text-xs">ENTER</kbd> Confirm
          </span>
        </footer>
      </main>
    </div>
  );
}
