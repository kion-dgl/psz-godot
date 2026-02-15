import { Routes, Route, Link, useLocation } from 'react-router-dom';
import { Suspense, lazy } from 'react';
import Landing from './pages/Landing';

const QuestEditor = lazy(() => import('./quest-editor/QuestEditor'));
const StorybookViewer = lazy(() => import('./storybook/StorybookViewer'));
const EnemyGallery = lazy(() => import('./storybook/EnemyGallery'));
const WeaponGallery = lazy(() => import('./storybook/WeaponGallery'));
const PlayerAnimationStorybook = lazy(() => import('./storybook/PlayerAnimationStorybook'));

function NavBar() {
  const location = useLocation();
  const isActive = (path: string) => location.pathname === path;

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
      <Link to="/storybook/player-animations" style={{
        color: isActive('/storybook/player-animations') ? '#fff' : '#888',
        textDecoration: 'none',
      }}>
        Animations
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
            <Route path="/quest-editor" element={<QuestEditor />} />
            <Route path="/storybook" element={<StorybookViewer />} />
            <Route path="/storybook/enemies" element={<EnemyGallery />} />
            <Route path="/storybook/weapons" element={<WeaponGallery />} />
            <Route path="/storybook/player-animations" element={<PlayerAnimationStorybook />} />
          </Routes>
        </Suspense>
      </div>
    </div>
  );
}
