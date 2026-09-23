import Frame from "./Frame";
import type { MenuItem } from "../data";
import { cn } from "../utils/cn";

type Props = {
  items: MenuItem[];
  selected: number;
  onSelect: (index: number) => void;
  onActivate: (index: number) => void;
};

const ROW_H = 50;

export default function MenuPanel({ items, selected, onSelect, onActivate }: Props) {
  return (
    <nav
      aria-label="Main menu"
      className="absolute anim-left"
      style={{ left: 32, top: 172, width: 215, height: 546, animationDelay: "80ms" }}
    >
      <Frame
        width={215}
        height={546}
        points="6,0 209,0 215,6 215,516 187,546 28,546 0,518 0,6"
        inner={[{ points: "12,10 203,10 203,508 12,508" }]}
      />

      <ul className="absolute list-none m-0 p-0" style={{ left: 14, top: 12, width: 187 }} role="menu">
        {items.map((item, i) => {
          const active = i === selected;
          return (
            <li key={item.label} role="none" style={{ height: ROW_H }} className="relative">
              <button
                type="button"
                role="menuitem"
                aria-disabled={item.disabled || undefined}
                aria-current={active ? "true" : undefined}
                onMouseEnter={() => onSelect(i)}
                onFocus={() => onSelect(i)}
                onClick={() => onActivate(i)}
                className={cn(
                  "absolute inset-x-[3px] top-[2px] bottom-[2px] flex items-center justify-center",
                  "pixel-text stage-text cursor-pointer select-none outline-none",
                  "transition-colors duration-100",
                  active && "cursor-pulse",
                  item.disabled ? "text-[#a4a4a4] cursor-not-allowed" : "text-[#121212]",
                )}
                style={{
                  fontSize: 48,
                  letterSpacing: "0.02em",
                  background: active
                    ? "linear-gradient(180deg, #ffc94a 0%, #f7a224 16%, #ee8a12 100%)"
                    : undefined,
                  boxShadow: active
                    ? "inset 0 1.5px 0 #ffeaa8, inset 0 -1.5px 0 #b35900, 0 1px 2px rgba(0,0,0,0.2)"
                    : undefined,
                }}
              >
                <span>{item.label}</span>
              </button>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
