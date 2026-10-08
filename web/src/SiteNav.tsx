import { useEffect, useRef, useState } from 'react';
import { siteUrl } from '../../spec/src/utils/site';

type NavLink = { to: string; label: string };
type NavGroup = { label: string; base?: string; links: NavLink[] };

const NAV_GROUPS: NavGroup[] = [
  {
    label: 'Specs', base: '',
    links: [
      { to: '/overview/', label: 'Overview' },
      { to: '/fidelity/', label: 'Fidelity grades' },
      { to: '/architecture/', label: 'Architecture' },
      { to: '/journey/splash/', label: 'Journey' },
      { to: '/mechanics/', label: 'Mechanics' },
      { to: '/states/', label: 'States' },
      { to: '/hierarchies/', label: 'Hierarchies' },
      { to: '/engineering/', label: 'Engineering' },
      { to: '/autopilot/', label: 'Autopilot' },
      { to: '/asset-distribution/', label: 'Assets' },
    ],
  },
  {
    label: 'Quest',
    links: [{ to: '/quest-editor', label: 'Quest Editor' }],
  },
  {
    label: 'Storybook',
    links: [
      { to: '/storybook', label: 'Elements' },
      { to: '/storybook/enemies', label: 'Enemies' },
      { to: '/storybook/weapons', label: 'Weapons' },
      { to: '/storybook/basic-weapons', label: 'PSO Weapons' },
      { to: '/storybook/player-animations', label: 'Animations' },
      { to: '/storybook/flap-lab', label: 'Flap Lab' },
      { to: '/storybook/lighting-lab', label: 'Lighting Lab' },
    ],
  },
  {
    label: 'Editors',
    links: [
      { to: '/stage-editor', label: 'Stage Editor' },
      { to: '/floor-mesh-editor', label: 'Floor Mesh' },
      { to: '/floor-collider-builder', label: 'Floor Collider' },
      { to: '/city-walk-mock', label: 'City Walk Mock' },
      { to: '/teleporter-mock', label: 'Teleporter' },
      { to: '/svg-check', label: 'SVG Check' },
      { to: '/office-editor', label: 'Office' },
      { to: '/market-editor', label: 'Market' },
      { to: '/city-lab', label: 'City Lab' },
      { to: '/shrine-pillar-lab', label: 'Shrine Pillars' },
      { to: '/underground-editor', label: 'Underground' },
    ],
  },
  {
    label: 'UI',
    links: [
      { to: '/menu-design', label: 'Menus' },
      { to: '/settings', label: 'Settings' },
      { to: '/start-menu', label: 'Start Menu' },
      { to: '/shop-3d', label: '3D Shops' },
      { to: '/title-screen', label: 'Title' },
      { to: '/asset-loader', label: 'Loader' },
      { to: '/controls', label: 'Controls' },
      { to: '/character-creator', label: 'Character' },
      { to: '/character-select', label: 'Char Select' },
      { to: '/palette-editor', label: 'Palette Editor' },
    ],
  },
  {
    label: 'Retarget',
    links: [
      { to: '/retarget', label: 'Retarget' },
      { to: '/retarget-tuner', label: 'Tuner' },
      { to: '/retarget-tuner-vrm', label: 'VRM Tuner' },
      { to: '/vrm-mixamo', label: 'VRM × Mixamo' },
      { to: '/vrma-to-psz', label: 'VRMA → PSZ' },
      { to: '/pso-ik-vrm', label: 'PSO → VRM (IK)' },
    ],
  },
  {
    label: 'Tools',
    links: [
      { to: '/sfx-labeler', label: 'SFX' },
      { to: '/photo-mode', label: 'Photo' },
      { to: '/dodge-debug', label: 'Dodge' },
      { to: '/combo-debug', label: 'Combo' },
      { to: '/combat-room', label: 'Combat Room' },
      { to: '/companion-room', label: 'Companion Room' },
      { to: '/tech-room', label: 'Tech Room' },
      { to: '/photon-room', label: 'Photon Room' },
      { to: '/enemy-room', label: 'Enemy Rooms' },
      { to: '/boss-room', label: 'Boss Rooms' },
      { to: '/texture-anim', label: 'Texture Anim' },
      { to: '/wall-debug', label: 'Wall #534' },
      { to: '/field-generator', label: 'Field Preview' },
      { to: '/field-solver', label: 'Field Solver' },
    ],
  },
];

function NavDropdown({ group }: { group: NavGroup }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const [pathname, setPathname] = useState('');
  useEffect(() => { setPathname(window.location.pathname); }, []);
  const href = (to: string) => siteUrl(`${group.base ?? '/tools'}${to}`).replace(/\/?$/, '/');

  const isActive = group.links.some(
    (l) => pathname === href(l.to) || pathname.startsWith(href(l.to)),
  );

  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    const escape = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', handler);
    document.addEventListener('keydown', escape);
    return () => { document.removeEventListener('mousedown', handler); document.removeEventListener('keydown', escape); };
  }, [open]);

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        style={{
          background: 'none',
          border: 'none',
          color: isActive ? '#fff' : '#888',
          cursor: 'pointer',
          padding: 0,
          fontSize: 13,
          fontFamily: 'inherit',
          display: 'flex',
          alignItems: 'center',
          gap: 4,
        }}
      >
        {group.label}
        <span style={{ fontSize: 9, opacity: 0.7 }}>▾</span>
      </button>
      {open && (
        <div
          style={{
            position: 'absolute',
            top: 'calc(100% + 6px)',
            left: 0,
            background: '#12122a',
            border: '1px solid #2a2a4a',
            borderRadius: 4,
            padding: 4,
            minWidth: 170,
            zIndex: 100,
            display: 'flex',
            flexDirection: 'column',
            gap: 2,
            boxShadow: '0 6px 18px rgba(0,0,0,0.45)',
          }}
        >
          {group.links.map((l) => {
            const active = pathname === href(l.to) || pathname.startsWith(href(l.to));
            return (
              <a
                key={l.to}
                href={href(l.to)}
                onClick={() => setOpen(false)}
                style={{
                  color: active ? '#fff' : '#aaa',
                  textDecoration: 'none',
                  padding: '5px 10px',
                  fontSize: 13,
                  borderRadius: 2,
                  background: active ? '#1f1f3f' : 'transparent',
                }}
              >
                {l.label}
              </a>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function SiteNav() {
  return (
    <nav
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 18,
        flexWrap: 'wrap',
        flexShrink: 0,
        position: 'relative',
        zIndex: 1000,
        padding: '8px 16px',
        background: '#12122a',
        borderBottom: '1px solid #2a2a4a',
        fontSize: 13,
      }}
    >
      <a
        href={siteUrl('/')}
        style={{
          color: '#88aaff',
          textDecoration: 'none',
          fontWeight: 600,
          fontSize: 14,
        }}
      >
        PSZ
      </a>
      <a href={siteUrl('/')} style={{ color: '#88aaff' }}>Downloads</a>
      {NAV_GROUPS.map((g) => (
        <NavDropdown key={g.label} group={g} />
      ))}
    </nav>
  );
}
