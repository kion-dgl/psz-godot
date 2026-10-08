import { BrowserRouter } from 'react-router-dom';
import App from './App';
import { siteUrl } from '../../spec/src/utils/site';

// Astro emits every tool URL so refresh and direct entry work on static hosting.
export default function SiteTools() {
  return <BrowserRouter basename={siteUrl('/tools')}><App /></BrowserRouter>;
}
