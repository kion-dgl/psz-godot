import { Routes, Route, Link, useLocation } from 'react-router-dom';
import { Suspense, lazy } from 'react';
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
const RetargetViewer = lazy(() => import('./retarget/RetargetViewer'));
const RetargetTuner = lazy(() => import('./retarget/RetargetTuner'));
const BasicWeaponPreview = lazy(() => import('./storybook/BasicWeaponPreview'));
const MenuDesign = lazy(() => import('./storybook/MenuDesign'));
const SettingsMockup = lazy(() => import('./settings/SettingsMockup'));
const CharacterCreator = lazy(() => import('./character-creator/CharacterCreator'));
const StartMenu = lazy(() => import('./start-menu/StartMenu'));
const ControlsDiagram = lazy(() => import('./controls/ControlsDiagram'));
const SfxLabeler = lazy(() => import('./sfx-labeler/SfxLabeler'));

function NavBar() {
  const location = useLocation();
  const isActive = (path: string) => location.pathname === path || location.pathname.startsWith(path + '/');

  return (
    <nav style={{
      display: 'flex',
      alignItems: 'center',
      gap: 16,
      padding: '8px 16px',
      background: '#12122a',
      borderBottom: '1px solid #2a2a4a',
      fontSize: 13,
    }}>
      <Link to="/" style={{
        color: '#88aaff',
        textDecoration: 'none',
        fontWeight: 600,
        fontSize: 14,
      }}>
        PSZ
      </Link>
      <Link to="/quest-editor" style={{
        color: isActive('/quest-editor') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Quest Editor
      </Link>
      <Link to="/storybook" style={{
        color: isActive('/storybook') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Elements
      </Link>
      <Link to="/storybook/enemies" style={{
        color: isActive('/storybook/enemies') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Enemies
      </Link>
      <Link to="/storybook/weapons" style={{
        color: isActive('/storybook/weapons') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Weapons
      </Link>
      <Link to="/storybook/basic-weapons" style={{
        color: isActive('/storybook/basic-weapons') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        PSO Weapons
      </Link>
      <Link to="/storybook/player-animations" style={{
        color: isActive('/storybook/player-animations') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Animations
      </Link>
      <Link to="/stage-editor" style={{
        color: isActive('/stage-editor') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Stage Editor
      </Link>
      <Link to="/svg-check" style={{
        color: isActive('/svg-check') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        SVG Check
      </Link>
      <Link to="/office-editor" style={{
        color: isActive('/office-editor') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Office
      </Link>
      <Link to="/menu-design" style={{
        color: isActive('/menu-design') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Menus
      </Link>
      <Link to="/settings" style={{
        color: isActive('/settings') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Settings
      </Link>
      <Link to="/retarget" style={{
        color: isActive('/retarget') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Retarget
      </Link>
      <Link to="/retarget-tuner" style={{
        color: isActive('/retarget-tuner') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Tuner
      </Link>
      <Link to="/character-creator" style={{
        color: isActive('/character-creator') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Character
      </Link>
      <Link to="/start-menu" style={{
        color: isActive('/start-menu') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Start Menu
      </Link>
      <Link to="/controls" style={{
        color: isActive('/controls') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Controls
      </Link>
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
            <Route path="/menu-design" element={<MenuDesign />} />
            <Route path="/settings" element={<SettingsMockup />} />
            <Route path="/retarget" element={<RetargetViewer />} />
            <Route path="/retarget-tuner" element={<RetargetTuner />} />
            <Route path="/character-creator" element={<CharacterCreator />} />
            <Route path="/start-menu" element={<StartMenu />} />
            <Route path="/controls" element={<ControlsDiagram />} />
            <Route path="/sfx-labeler" element={<SfxLabeler />} />
          </Routes>
        </Suspense>
      </div>
    </div>
  );
}
