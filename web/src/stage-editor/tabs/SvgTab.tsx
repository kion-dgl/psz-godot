import { useState, useMemo } from 'react';
import type { UnifiedStageConfig, FloorTriangle, SvgSettings } from '../types';
import { DEFAULT_SVG_SETTINGS } from '../types';
import { rotateDirection } from '../../quest-editor/hooks/useStageConfigs';
import type { Direction } from '../../quest-editor/types';

interface SvgTabProps {
  config: UnifiedStageConfig;
  updateConfig: (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => void;
  floorTriangles: FloorTriangle[];
  mapId: string;
}

// Generate SVG minimap with configurable bounds and optional rotation
function generateSvgMinimap(
  triangles: FloorTriangle[],
  portals: UnifiedStageConfig['portals'],
  options: {
    gridSize: number;
    centerX: number;
    centerZ: number;
    svgSize: number;
    padding: number;
  },
  rotation: number = 0
): { svg: string; gatesInBounds: number } {
  const { gridSize, centerX, centerZ, svgSize, padding } = options;

  if (triangles.length === 0) {
    return {
      svg: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${svgSize} ${svgSize}"><rect width="${svgSize}" height="${svgSize}" fill="#1a1a2e"/><text x="${svgSize / 2}" y="${svgSize / 2}" text-anchor="middle" fill="#666">No floor data</text></svg>`,
      gatesInBounds: 0,
    };
  }

  const halfGrid = gridSize / 2;
  const minX = centerX - halfGrid;
  const maxX = centerX + halfGrid;
  const minZ = centerZ - halfGrid;
  const maxZ = centerZ + halfGrid;

  const width = maxX - minX;
  const height = maxZ - minZ;
  const scale = (svgSize - padding * 2) / Math.max(width, height);

  const toSvgX = (x: number) => (x - minX) * scale + padding;
  const toSvgY = (z: number) => (z - minZ) * scale + padding;

  const cx = svgSize / 2;
  const cy = svgSize / 2;

  const visibleTriangles = triangles.filter((tri) => {
    return tri.vertices.some(
      (v) => v.x >= minX && v.x <= maxX && v.z >= minZ && v.z <= maxZ
    );
  });

  const trianglePaths = visibleTriangles
    .map((tri) => {
      const points = tri.vertices.map(
        (v) => `${toSvgX(v.x).toFixed(1)},${toSvgY(v.z).toFixed(1)}`
      );
      return `M ${points.join(' L ')} Z`;
    })
    .join(' ');

  const edgeMap = new Map<string, number>();
  const edgeVertices = new Map<string, [[number, number], [number, number]]>();

  visibleTriangles.forEach((tri) => {
    const verts = tri.vertices.map((v) => [v.x, v.z] as [number, number]);
    for (let i = 0; i < 3; i++) {
      const v1 = verts[i];
      const v2 = verts[(i + 1) % 3];
      const key =
        v1[0] < v2[0] || (v1[0] === v2[0] && v1[1] < v2[1])
          ? `${v1[0].toFixed(3)},${v1[1].toFixed(3)}-${v2[0].toFixed(3)},${v2[1].toFixed(3)}`
          : `${v2[0].toFixed(3)},${v2[1].toFixed(3)}-${v1[0].toFixed(3)},${v1[1].toFixed(3)}`;
      edgeMap.set(key, (edgeMap.get(key) || 0) + 1);
      edgeVertices.set(key, [v1, v2]);
    }
  });

  const boundaryEdges: string[] = [];
  edgeMap.forEach((count, key) => {
    if (count === 1) {
      const [v1, v2] = edgeVertices.get(key)!;
      boundaryEdges.push(
        `M ${toSvgX(v1[0]).toFixed(1)},${toSvgY(v1[1]).toFixed(1)} L ${toSvgX(v2[0]).toFixed(1)},${toSvgY(v2[1]).toFixed(1)}`
      );
    }
  });

  const gatesInBounds = portals.filter((portal) => {
    const x = portal.position[0];
    const z = portal.position[2];
    return x >= minX && x <= maxX && z >= minZ && z <= maxZ;
  });

  const gateMarkers = gatesInBounds
    .map((portal) => {
      const x = toSvgX(portal.position[0]);
      const y = toSvgY(portal.position[2]);
      const isHorizontal = portal.direction === 'north' || portal.direction === 'south';
      const rectWidth = isHorizontal ? 48 : 8;
      const rectHeight = isHorizontal ? 8 : 48;

      // Rotated grid direction for label
      const gridDir = rotateDirection(portal.direction as Direction, rotation);
      const labelText = gridDir[0].toUpperCase();

      let labelX = x;
      let labelY = y;
      let anchor = 'middle';
      const labelOffset = 16;

      switch (portal.direction) {
        case 'north': labelY = y - labelOffset; break;
        case 'south': labelY = y + labelOffset + 8; break;
        case 'east': labelX = x + labelOffset + 4; anchor = 'start'; break;
        case 'west': labelX = x - labelOffset - 4; anchor = 'end'; break;
      }

      const rect = `<rect x="${(x - rectWidth / 2).toFixed(1)}" y="${(y - rectHeight / 2).toFixed(1)}" width="${rectWidth}" height="${rectHeight}" fill="#ff4444" stroke="white" stroke-width="1" data-gate="true" data-gate-dir="${gridDir}"/>`;
      // Counter-rotate text so labels stay upright in rotated SVGs
      const textRotate = rotation !== 0 ? ` transform="rotate(${-rotation}, ${labelX.toFixed(1)}, ${labelY.toFixed(1)})"` : '';
      const label = `<text x="${labelX.toFixed(1)}" y="${labelY.toFixed(1)}" text-anchor="${anchor}" font-size="10" fill="#ffaaaa" font-family="sans-serif"${textRotate}>${labelText}</text>`;

      return rect + '\n' + label;
    })
    .join('\n');

  // Invisible origin marker at world (0,0) — used by PreviewMinimap to anchor coordinate transform
  const originX = toSvgX(0);
  const originY = toSvgY(0);
  const originMarker = `<circle cx="${originX.toFixed(1)}" cy="${originY.toFixed(1)}" r="0" data-origin="true" fill="none"/>`;

  // Compute offset: toSvgX(x) = (x - minX) * scale + padding = x * scale + (padding - minX * scale)
  const offsetX = padding - minX * scale;
  const offsetY = padding - minZ * scale;

  // Data attributes for embedded transform metadata
  const dataAttrs = `data-rotation="${rotation}" data-scale="${scale.toFixed(6)}" data-offset-x="${offsetX.toFixed(2)}" data-offset-y="${offsetY.toFixed(2)}" data-center-x="${cx.toFixed(1)}" data-center-y="${cy.toFixed(1)}"`;

  // Wrap all visual content in a rotated group when rotation != 0
  const rotateOpen = rotation !== 0 ? `<g transform="rotate(${rotation}, ${cx.toFixed(1)}, ${cy.toFixed(1)})">` : '';
  const rotateClose = rotation !== 0 ? '</g>' : '';

  return {
    svg: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${svgSize} ${svgSize}" ${dataAttrs}>
  <rect width="${svgSize}" height="${svgSize}" fill="#1a1a2e"/>
  ${rotateOpen}
  <path d="${trianglePaths}" fill="#2a2a4e" stroke="none"/>
  <path d="${boundaryEdges.join(' ')}" fill="none" stroke="white" stroke-width="2" stroke-linecap="round"/>
  ${gateMarkers}
  ${originMarker}
  ${rotateClose}
</svg>`,
    gatesInBounds: gatesInBounds.length,
  };
}

export default function SvgTab({ config, updateConfig, floorTriangles, mapId }: SvgTabProps) {
  const [exportStatus, setExportStatus] = useState('');

  const includedTriangles = useMemo(() => {
    return floorTriangles.filter((t) => t.included);
  }, [floorTriangles]);

  const autoBounds = useMemo(() => {
    if (includedTriangles.length === 0) {
      return { centerX: 0, centerZ: 0, gridSize: 40 };
    }

    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    includedTriangles.forEach((tri) => {
      tri.vertices.forEach((v) => {
        minX = Math.min(minX, v.x);
        maxX = Math.max(maxX, v.x);
        minZ = Math.min(minZ, v.z);
        maxZ = Math.max(maxZ, v.z);
      });
    });

    const width = maxX - minX;
    const height = maxZ - minZ;
    const gridSize = Math.ceil(Math.max(width, height) * 1.2);

    return {
      centerX: (minX + maxX) / 2,
      centerZ: (minZ + maxZ) / 2,
      gridSize: Math.max(gridSize, 20),
    };
  }, [includedTriangles]);

  const settings = useMemo((): SvgSettings => {
    if (config.svgSettings) {
      return config.svgSettings;
    }
    return {
      ...DEFAULT_SVG_SETTINGS,
      gridSize: autoBounds.gridSize,
      centerX: autoBounds.centerX,
      centerZ: autoBounds.centerZ,
    };
  }, [config.svgSettings, autoBounds]);

  const updateSetting = <K extends keyof SvgSettings>(key: K, value: SvgSettings[K]) => {
    updateConfig((prev) => ({
      ...prev,
      svgSettings: { ...settings, [key]: value },
    }));
  };

  const handleResetBounds = () => {
    updateConfig((prev) => ({
      ...prev,
      svgSettings: {
        ...settings,
        gridSize: autoBounds.gridSize,
        centerX: autoBounds.centerX,
        centerZ: autoBounds.centerZ,
      },
    }));
  };

  const { svg: svgPreview, gatesInBounds } = useMemo(() => {
    return generateSvgMinimap(includedTriangles, config.portals, settings);
  }, [includedTriangles, config.portals, settings]);

  const exportSvg = () => {
    const blob = new Blob([svgPreview], { type: 'image/svg+xml' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${mapId}_minimap.svg`;
    link.click();
    URL.revokeObjectURL(url);
    setExportStatus(`Exported ${mapId}_minimap.svg`);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', color: 'white' }}>
      <h3 style={{ margin: 0, borderBottom: '1px solid #444', paddingBottom: '8px' }}>SVG Minimap</h3>

      <div style={{ padding: '12px', background: '#1a1a2e', borderRadius: '4px' }}>
        <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#888' }}>View Bounds</h4>
        <div style={{ marginBottom: '12px' }}>
          <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>Grid Size: {settings.gridSize.toFixed(1)}</label>
          <input type="range" min={10} max={200} step={1} value={settings.gridSize} onChange={(e) => updateSetting('gridSize', parseFloat(e.target.value))} style={{ width: '100%' }} />
        </div>
        <div style={{ marginBottom: '12px' }}>
          <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>Center X: {settings.centerX.toFixed(2)}</label>
          <input type="range" min={-100} max={100} step={0.5} value={settings.centerX} onChange={(e) => updateSetting('centerX', parseFloat(e.target.value))} style={{ width: '100%' }} />
        </div>
        <div style={{ marginBottom: '12px' }}>
          <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>Center Z: {settings.centerZ.toFixed(2)}</label>
          <input type="range" min={-100} max={100} step={0.5} value={settings.centerZ} onChange={(e) => updateSetting('centerZ', parseFloat(e.target.value))} style={{ width: '100%' }} />
        </div>
        <button onClick={handleResetBounds} style={{ width: '100%', padding: '8px', background: '#444', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>Reset to Auto Bounds</button>
      </div>

      <div>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>Preview:</label>
        <div style={{ background: '#1a1a2e', borderRadius: '4px', padding: '8px', display: 'flex', justifyContent: 'center', maxHeight: '300px', overflow: 'auto' }} dangerouslySetInnerHTML={{ __html: svgPreview }} />
      </div>

      <div style={{ padding: '12px', background: '#1a1a2e', borderRadius: '4px' }}>
        <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#888' }}>Output Size</h4>
        <div style={{ marginBottom: '12px' }}>
          <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>SVG Size: {settings.svgSize}px</label>
          <input type="range" min={200} max={1024} step={8} value={settings.svgSize} onChange={(e) => updateSetting('svgSize', parseInt(e.target.value))} style={{ width: '100%' }} />
        </div>
        <div>
          <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>Padding: {settings.padding}px</label>
          <input type="range" min={0} max={50} step={2} value={settings.padding} onChange={(e) => updateSetting('padding', parseInt(e.target.value))} style={{ width: '100%' }} />
        </div>
      </div>

      <div style={{ padding: '12px', background: '#1a1a2e', borderRadius: '4px', fontSize: '12px' }}>
        <div>Floor triangles: {includedTriangles.length}</div>
        <div>Gates: {gatesInBounds}/{config.portals.length}
          {config.portals.length > 0 && gatesInBounds === 0 && <span style={{ color: '#f88', marginLeft: 8 }}>(none in bounds!)</span>}
        </div>
        <div>Bounds: X[{(settings.centerX - settings.gridSize / 2).toFixed(1)}, {(settings.centerX + settings.gridSize / 2).toFixed(1)}] Z[{(settings.centerZ - settings.gridSize / 2).toFixed(1)}, {(settings.centerZ + settings.gridSize / 2).toFixed(1)}]</div>
      </div>

      {config.portals.length > 0 && (
        <div style={{ padding: '12px', background: '#1a1a2e', borderRadius: '4px', fontSize: '11px', color: '#888' }}>
          <div style={{ marginBottom: '4px', color: '#aaa' }}>Gate positions:</div>
          {config.portals.map((p) => (
            <div key={p.id}>{p.label}: X={p.position[0].toFixed(1)}, Z={p.position[2].toFixed(1)}</div>
          ))}
        </div>
      )}

      <button onClick={exportSvg} disabled={includedTriangles.length === 0} style={{ padding: '12px', background: includedTriangles.length > 0 ? '#4a9eff' : '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: includedTriangles.length > 0 ? 'pointer' : 'not-allowed', fontWeight: 'bold', fontSize: '14px' }}>
        Export SVG Minimap
      </button>

      {exportStatus && <div style={{ padding: '8px 12px', background: '#1a1a2e', borderRadius: '4px', fontSize: '12px', color: '#8f8' }}>{exportStatus}</div>}

      <div style={{ fontSize: '11px', color: '#666', marginTop: '8px' }}>
        <p style={{ margin: '4px 0' }}>Settings are auto-saved to localStorage</p>
      </div>
    </div>
  );
}
