/**
 * PreviewMinimap — SVG-based minimap with player tracking dot
 *
 * Loads the pre-generated SVG minimap file for the current stage,
 * rotates it by cell rotation, and overlays a player tracking dot.
 * The world→SVG coordinate mapping uses svgSettings from the stage config.
 */

import { useState, useEffect, useMemo } from 'react';
import { assetUrl } from '../../utils/assets';
import { getStageSubfolder } from '../../stage-editor/constants';
import type { PortalData } from './StageScene';

interface SvgSettings {
  gridSize: number;
  centerX: number;
  centerZ: number;
  svgSize: number;
  padding: number;
}

const DEFAULT_SVG_SETTINGS: SvgSettings = {
  gridSize: 40,
  centerX: 0,
  centerZ: 0,
  svgSize: 400,
  padding: 20,
};

interface PreviewMinimapProps {
  areaFolder: string;
  stageId: string;
  svgSettings: SvgSettings | null;
  cellRotation: number;
  portals: Record<string, PortalData>;
  connections: Record<string, string>;
  /** Player position in model-local space (unrotated) */
  playerX: number;
  playerZ: number;
}

const DISPLAY_SIZE = 200;

export default function PreviewMinimap({
  areaFolder,
  stageId,
  svgSettings,
  cellRotation,
  portals,
  connections,
  playerX,
  playerZ,
}: PreviewMinimapProps) {
  const [svgContent, setSvgContent] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Load SVG file
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setSvgContent(null);

    const subfolder = getStageSubfolder(stageId, areaFolder);
    const svgPath = assetUrl(`assets/stages/${subfolder}/${stageId}/lndmd/${stageId}_minimap.svg`);

    fetch(svgPath)
      .then(resp => {
        if (!resp.ok) throw new Error('SVG not found');
        return resp.text();
      })
      .then(text => {
        if (!cancelled) {
          setSvgContent(text);
          setLoading(false);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setSvgContent(null);
          setLoading(false);
        }
      });

    return () => { cancelled = true; };
  }, [stageId, areaFolder]);

  // Compute world→SVG coordinate mapping
  const settings = svgSettings ?? DEFAULT_SVG_SETTINGS;
  const { gridSize, centerX, centerZ, svgSize, padding } = settings;
  const halfGrid = gridSize / 2;
  const minX = centerX - halfGrid;
  const minZ = centerZ - halfGrid;
  const scale = (svgSize - padding * 2) / gridSize;

  const toSvgX = (wx: number) => (wx - minX) * scale + padding;
  const toSvgY = (wz: number) => (wz - minZ) * scale + padding;

  // Player position in SVG coordinates
  const playerSvgX = toSvgX(playerX);
  const playerSvgY = toSvgY(playerZ);

  // Gate markers in SVG coordinates
  const gateMarkers = useMemo(() => {
    return Object.entries(portals)
      .filter(([dir]) => dir !== 'default' && connections[dir])
      .map(([dir, portal]) => ({
        dir,
        x: toSvgX(portal.gate[0]),
        y: toSvgY(portal.gate[2]),
      }));
  }, [portals, connections, minX, minZ, scale, padding]);

  // CSS rotation for cell rotation (CW degrees)
  const rotDeg = -cellRotation;

  if (loading) {
    return (
      <div style={{
        width: DISPLAY_SIZE, height: DISPLAY_SIZE,
        background: 'rgba(26, 26, 46, 0.85)', borderRadius: 8,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#666', fontSize: 11,
      }}>
        Loading minimap...
      </div>
    );
  }

  if (!svgContent) {
    return (
      <div style={{
        width: DISPLAY_SIZE, height: DISPLAY_SIZE,
        background: 'rgba(26, 26, 46, 0.85)', borderRadius: 8,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#555', fontSize: 10,
      }}>
        No minimap SVG
      </div>
    );
  }

  return (
    <div style={{
      width: DISPLAY_SIZE, height: DISPLAY_SIZE,
      borderRadius: 8, overflow: 'hidden',
      boxShadow: '0 4px 12px rgba(0,0,0,0.5)',
      position: 'relative',
    }}>
      {/* Rotated container for SVG + overlays */}
      <div style={{
        width: DISPLAY_SIZE, height: DISPLAY_SIZE,
        transform: `rotate(${rotDeg}deg)`,
        transformOrigin: 'center center',
      }}>
        {/* SVG background (scaled to fit display size) */}
        <div
          style={{
            width: DISPLAY_SIZE, height: DISPLAY_SIZE,
            position: 'absolute', top: 0, left: 0,
          }}
          dangerouslySetInnerHTML={{
            __html: svgContent.replace(
              /viewBox="[^"]*"/,
              `viewBox="0 0 ${svgSize} ${svgSize}" width="${DISPLAY_SIZE}" height="${DISPLAY_SIZE}"`
            ),
          }}
        />

        {/* Overlay SVG for player dot + gate labels */}
        <svg
          viewBox={`0 0 ${svgSize} ${svgSize}`}
          width={DISPLAY_SIZE}
          height={DISPLAY_SIZE}
          style={{ position: 'absolute', top: 0, left: 0 }}
        >
          {/* Gate direction labels */}
          {gateMarkers.map(({ dir, x, y }) => (
            <text
              key={dir}
              x={x}
              y={y - 10}
              textAnchor="middle"
              fill="#4a9eff"
              fontSize={14}
              fontFamily="monospace"
              fontWeight="bold"
            >
              {dir[0].toUpperCase()}
            </text>
          ))}

          {/* Player dot */}
          <circle
            cx={playerSvgX}
            cy={playerSvgY}
            r={6}
            fill="#00ff00"
            stroke="#000"
            strokeWidth={1.5}
          />
        </svg>
      </div>
    </div>
  );
}
