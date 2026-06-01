// StageSpecExplorer — parent wrapper for the per-area page. Owns the
// "active stage" state (synced to the URL ?stage param) and renders the
// stage picker, the slim editor, and the spec panel.

import { useEffect, useState } from 'react';
import StageWaypointSpec from './StageWaypointSpec';

interface Spec {
  stageId?: string;
  shape?: string;
  description?: string;
  portals?: Record<string, string>;
  objectives?: Record<string, { position: number[]; description?: string }>;
  anchors?: { id: string; position: [number, number, number]; description?: string }[];
  anchorEdges?: [string, string][];
  traversalNotes?: string[];
}

interface Props {
  stages: string[];
  /** Map of stageId → spec (loaded at build time). */
  specs: Record<string, Spec>;
  /** Base path under /cdn for floor GLBs, e.g. "assets/stages/paru_a". */
  floorBase: string;
}

export default function StageSpecExplorer({ stages, specs, floorBase }: Props) {
  const [activeStage, setActiveStage] = useState<string>(stages[0]);

  // On mount: read ?stage from URL.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const url = params.get('stage');
    if (url && stages.includes(url)) setActiveStage(url);
  }, []);

  // When the active stage changes, sync the URL (replace, not push, so the
  // back button still navigates out of the page).
  useEffect(() => {
    const url = new URL(window.location.href);
    url.searchParams.set('stage', activeStage);
    window.history.replaceState({}, '', url);
  }, [activeStage]);

  const spec = specs[activeStage];
  const floorUrl = `/${floorBase}/${activeStage}/lndmd/${activeStage}-floor.glb`;
  const visualUrl = `/${floorBase}/${activeStage}/lndmd/${activeStage}_m.glb`;
  // Deep-link to the Vite editor for waypoint authoring. Use the IP form
  // so the link works from a phone over Tailscale, not just localhost.
  const editorOrigin = typeof window !== 'undefined'
    ? `${window.location.protocol}//${window.location.hostname}:5173`
    : '';
  const editorUrl = `${editorOrigin}/psz-godot/#/stage-editor?stage=${activeStage}`;

  return (
    <div className="explorer-layout">
      <nav className="stage-list">
        {stages.map((id) => {
          const hasSpec = !!specs[id];
          return (
            <button
              key={id}
              className={'stage-btn ' + (id === activeStage ? 'active' : '')}
              onClick={() => setActiveStage(id)}
            >
              <span className="stage-id">{id.slice(5)}</span>
              <span className={'stage-spec ' + (hasSpec ? 'has-spec' : 'no-spec')}>
                {hasSpec ? specs[id].shape ?? 'spec' : '—'}
              </span>
            </button>
          );
        })}
      </nav>

      <main className="viewer">
        <StageWaypointSpec
          key={activeStage}
          stageId={activeStage}
          floorUrl={floorUrl}
          visualUrl={visualUrl}
          editorUrl={editorUrl}
        />
      </main>

      <aside className="spec-panel">
        <SpecPanel stageId={activeStage} spec={spec} />
      </aside>

      <style>{`
        .explorer-layout {
          flex: 1;
          display: grid;
          grid-template-columns: 200px 1fr 360px;
          overflow: hidden;
          min-height: 0;
        }
        .stage-list {
          background: #161b22;
          border-right: 1px solid #30363d;
          overflow-y: auto;
          padding: 8px 0;
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        .stage-btn {
          background: none;
          border: none;
          padding: 8px 14px;
          text-align: left;
          color: #c9d1d9;
          cursor: pointer;
          display: flex;
          justify-content: space-between;
          align-items: center;
          font-size: 13px;
          font-family: ui-monospace, monospace;
          border-left: 3px solid transparent;
        }
        .stage-btn:hover { background: #1f2530; }
        .stage-btn.active {
          background: #22304a;
          border-left-color: #58a6ff;
        }
        .stage-spec {
          font-size: 10px;
          padding: 2px 6px;
          border-radius: 3px;
        }
        .stage-spec.has-spec { background: #14532d; color: #86efac; }
        .stage-spec.no-spec { color: #4b5563; }
        .viewer {
          background: #0a0e1a;
          position: relative;
          display: flex;
          flex-direction: column;
          min-height: 0;
        }
        .spec-panel {
          background: #0e1117;
          border-left: 1px solid #30363d;
          overflow-y: auto;
          padding: 16px;
          font-size: 13px;
          line-height: 1.5;
        }
      `}</style>
    </div>
  );
}

function SpecPanel({ stageId, spec }: { stageId: string; spec: Spec | undefined }) {
  if (!spec) {
    return (
      <>
        <h2 className="panel-h2">{stageId}</h2>
        <p className="empty">No spec yet for this stage.</p>
        <p className="hint">
          Use the editor on the left to place anchors + edges, then copy the JSON from the
          bottom panel into <code>data/stage_specs/{stageId}.json</code>.
        </p>
        <PanelStyle />
      </>
    );
  }
  return (
    <>
      <h2 className="panel-h2">
        {stageId} {spec.shape && <span className="shape-tag">{spec.shape}</span>}
      </h2>
      {spec.description && <p className="desc">{spec.description}</p>}
      {spec.portals && Object.keys(spec.portals).length > 0 && (
        <Section title="Portals">
          {Object.entries(spec.portals).map(([k, v]) => (
            <li key={k}><strong>{k}</strong>: {v}</li>
          ))}
        </Section>
      )}
      {spec.objectives && Object.keys(spec.objectives).length > 0 && (
        <Section title="Objectives">
          {Object.entries(spec.objectives).map(([k, v]) => (
            <li key={k}>
              <strong>{k}</strong> at ({v.position.join(', ')}): {v.description}
            </li>
          ))}
        </Section>
      )}
      {spec.anchors && spec.anchors.length > 0 && (
        <Section title={`Anchors (${spec.anchors.length})`}>
          {spec.anchors.map((a) => (
            <li key={a.id}>
              <strong>{a.id}</strong> at ({a.position.join(', ')}): {a.description}
            </li>
          ))}
        </Section>
      )}
      {spec.anchorEdges && spec.anchorEdges.length > 0 && (
        <Section title={`Anchor edges (${spec.anchorEdges.length})`}>
          {spec.anchorEdges.map((e, i) => (
            <li key={i}>{e[0]} → {e[1]}</li>
          ))}
        </Section>
      )}
      {spec.traversalNotes && spec.traversalNotes.length > 0 && (
        <Section title="Traversal notes">
          {spec.traversalNotes.map((n, i) => <li key={i}>{n}</li>)}
        </Section>
      )}
      <p className="source">spec: <code>data/stage_specs/{stageId}.json</code></p>
      <PanelStyle />
    </>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <>
      <h3 className="panel-h3">{title}</h3>
      <ul className="panel-list">{children}</ul>
    </>
  );
}

function PanelStyle() {
  return (
    <style>{`
      .panel-h2 {
        font-size: 16px;
        font-family: ui-monospace, monospace;
        margin-bottom: 8px;
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .panel-h3 {
        font-size: 12px;
        text-transform: uppercase;
        color: #8b949e;
        margin: 16px 0 6px;
        letter-spacing: 0.05em;
      }
      .shape-tag {
        font-size: 10px;
        padding: 2px 6px;
        border-radius: 3px;
        background: #1f2937;
        color: #9ca3af;
      }
      .panel-list { list-style: none; padding: 0; margin: 0; }
      .panel-list li {
        padding: 4px 0;
        border-bottom: 1px solid #1f2530;
        font-size: 12px;
      }
      .panel-list li:last-child { border-bottom: none; }
      .desc {
        color: #d1d5db;
        font-size: 12px;
        line-height: 1.6;
        padding: 8px 10px;
        background: #161b22;
        border-radius: 4px;
      }
      .empty { color: #6b7280; font-style: italic; }
      .hint { margin-top: 8px; font-size: 11px; color: #6b7280; }
      .source { margin-top: 24px; font-size: 10px; color: #4b5563; }
      code {
        font-family: ui-monospace, monospace;
        background: #161b22;
        padding: 1px 4px;
        border-radius: 2px;
      }
    `}</style>
  );
}
