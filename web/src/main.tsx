import { createRoot } from 'react-dom/client';
import { HashRouter } from 'react-router-dom';
import App from './App';

// StrictMode removed — double-mount destroys WebGL contexts in Three.js pages
createRoot(document.getElementById('root')!).render(
  <HashRouter>
    <App />
  </HashRouter>
);
