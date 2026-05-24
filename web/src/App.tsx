import { Routes, Route, Link, useLocation } from 'react-router-dom';
import { Suspense, lazy, useEffect, useRef, useState } from 'react';
import Landing from './pages/Landing';

const QuestHome = lazy(() => import('./quest-editor/QuestHome'));
const QuestEditor = lazy(() => import('./quest-editor/QuestEditor'));
const StorybookViewer = lazy(() => import('./storybook/StorybookViewer'));
const EnemyGallery = lazy(() => import('./storybook/EnemyGallery'));
const WeaponGallery = lazy(() => import('./storybook/WeaponGallery'));
const PlayerAnimationStorybook = lazy(() => import('./storybook/PlayerAnimationStorybook'));
const StageEditor = lazy(() => import('./stage-editor/UnifiedStageEditor'));
const SvgCheck = lazy(() => import('./svg-check/SvgCheck'));
const OfficeEditor = lazy(() => import('./office-editor/OfficeEditor'));
const MarketEditor = lazy(() => import('./market-editor/MarketEditor'));
const RetargetViewer = lazy(() => import('./retarget/RetargetViewer'));
const RetargetTuner = lazy(() => import('./retarget/RetargetTuner'));
const RetargetTunerVrm = lazy(() => import('./retarget/RetargetTunerVrm'));
const MixamoLoader = lazy(() => import('./retarget/MixamoLoader'));
const BakedVrmaPszViewer = lazy(() => import('./retarget/BakedVrmaPszViewer'));
const PsoIkVrmViewer = lazy(() => import('./retarget/PsoIkVrmViewer'));
const BasicWeaponPreview = lazy(() => import('./storybook/BasicWeaponPreview'));
const MenuDesign = lazy(() => import('./storybook/MenuDesign'));
const SettingsMockup = lazy(() => import('./settings/SettingsMockup'));
const CharacterCreator = lazy(() => import('./character-creator/CharacterCreator'));
const StartMenu = lazy(() => import('./start-menu/StartMenu'));
const ControlsDiagram = lazy(() => import('./controls/ControlsDiagram'));
const SfxLabeler = lazy(() => import('./sfx-labeler/SfxLabeler'));
const PhotoMode = lazy(() => import('./photo-mode/PhotoMode'));
const TitleScreen = lazy(() => import('./title-screen/TitleScreen'));
const DodgeDebug = lazy(() => import('./dodge-debug/DodgeDebug'));
const AssetLoader = lazy(() => import('./asset-loader/AssetLoader'));
const CharacterSelect = lazy(() => import('./character-select/CharacterSelect'));
const UndergroundEditor = lazy(() => import('./underground-editor/UndergroundEditor'));

type NavLink = { to: string; label: string };
type NavGroup = { label: string; links: NavLink[] };

const NAV_GROUPS: NavGroup[] = [
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
    ],
  },
  {
    label: 'Editors',
    links: [
      { to: '/stage-editor', label: 'Stage Editor' },
      { to: '/svg-check', label: 'SVG Check' },
      { to: '/office-editor', label: 'Office' },
      { to: '/market-editor', label: 'Market' },
      { to: '/underground-editor', label: 'Underground' },
    ],
  },
  {
    label: 'UI',
    links: [
      { to: '/menu-design', label: 'Menus' },
      { to: '/settings', label: 'Settings' },
      { to: '/start-menu', label: 'Start Menu' },
      { to: '/title-screen', label: 'Title' },
      { to: '/asset-loader', label: 'Loader' },
      { to: '/controls', label: 'Controls' },
      { to: '/character-creator', label: 'Character' },
      { to: '/character-select', label: 'Char Select' },
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
    ],
  },
];

function NavDropdown({ group }: { group: NavGroup }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const location = useLocation();

  const isActive = group.links.some(
    (l) => location.pathname === l.to || location.pathname.startsWith(l.to + '/'),
  );

  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
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
            const active = location.pathname === l.to || location.pathname.startsWith(l.to + '/');
            return (
              <Link
                key={l.to}
                to={l.to}
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
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}

function NavBar() {
  return (
    <nav
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 18,
        padding: '8px 16px',
        background: '#12122a',
        borderBottom: '1px solid #2a2a4a',
        fontSize: 13,
      }}
    >
      <Link
        to="/"
        style={{
          color: '#88aaff',
          textDecoration: 'none',
          fontWeight: 600,
          fontSize: 14,
        }}
      >
        PSZ
      </Link>
      {NAV_GROUPS.map((g) => (
        <NavDropdown key={g.label} group={g} />
      ))}
    </nav>
  );
}

export default function App() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh' }}>
      <NavBar />
      <div style={{ flex: 1, overflow: 'hidden' }}>
        <Suspense fallback={<div style={{ padding: 32, color: '#888' }}>Loading...</div>}>
          <Routes>
            <Route path="/" element={<Landing />} />
            <Route path="/quest-editor" element={<QuestHome />} />
            <Route path="/quest-editor/edit" element={<QuestEditor />} />
            <Route path="/storybook" element={<StorybookViewer />} />
            <Route path="/storybook/enemies" element={<EnemyGallery />} />
            <Route path="/storybook/weapons" element={<WeaponGallery />} />
            <Route path="/storybook/basic-weapons" element={<BasicWeaponPreview />} />
            <Route path="/storybook/player-animations" element={<PlayerAnimationStorybook />} />
            <Route path="/stage-editor" element={<StageEditor />} />
            <Route path="/svg-check" element={<SvgCheck />} />
            <Route path="/office-editor" element={<OfficeEditor />} />
            <Route path="/market-editor" element={<MarketEditor />} />
            <Route path="/menu-design" element={<MenuDesign />} />
            <Route path="/settings" element={<SettingsMockup />} />
            <Route path="/retarget" element={<RetargetViewer />} />
            <Route path="/retarget-tuner" element={<RetargetTuner />} />
            <Route path="/retarget-tuner-vrm" element={<RetargetTunerVrm />} />
            <Route path="/vrm-mixamo" element={<MixamoLoader />} />
            <Route path="/vrma-to-psz" element={<BakedVrmaPszViewer />} />
            <Route path="/pso-ik-vrm" element={<PsoIkVrmViewer />} />
            <Route path="/character-creator" element={<CharacterCreator />} />
            <Route path="/start-menu" element={<StartMenu />} />
            <Route path="/controls" element={<ControlsDiagram />} />
            <Route path="/sfx-labeler" element={<SfxLabeler />} />
            <Route path="/photo-mode" element={<PhotoMode />} />
            <Route path="/title-screen" element={<TitleScreen />} />
            <Route path="/asset-loader" element={<AssetLoader />} />
            <Route path="/character-select" element={<CharacterSelect />} />
            <Route path="/underground-editor" element={<UndergroundEditor />} />
            <Route path="/dodge-debug" element={<DodgeDebug />} />
          </Routes>
        </Suspense>
      </div>
    </div>
  );
}
