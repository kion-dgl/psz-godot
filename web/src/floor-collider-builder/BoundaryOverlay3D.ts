import * as THREE from 'three';
import {
  type CityBoundaryConfig,
  type ReferencePin,
  computeSolidEdgeSpans,
} from './boundaryModel';

export interface SelectedVertex {
  target: 'perimeter' | string; // cutout id
  index: number;
}

export function rebuildBoundaryOverlay(
  overlay: THREE.Group,
  handleMeshes: THREE.Object3D[],
  cfg: CityBoundaryConfig,
  pins: readonly ReferencePin[],
  selected: SelectedVertex | null,
  activeLoop: 'perimeter' | string,
): void {
  while (overlay.children.length) {
    const child = overlay.children.pop()!;
    child.traverse((obj) => {
      if (obj instanceof THREE.Mesh || obj instanceof THREE.Line) {
        obj.geometry.dispose();
        const m = obj.material;
        if (Array.isArray(m)) m.forEach((x) => x.dispose());
        else if (m) m.dispose();
      }
    });
  }
  handleMeshes.length = 0;

  const floorY = cfg.floorY;
  const wallBottom = cfg.wallBottomY ?? floorY;
  const wallTop = wallBottom + cfg.wallHeight;

  // 1. Walkable floor fill (when buildFloor is true)
  if (cfg.buildFloor && cfg.perimeter.length >= 3) {
    const shape = new THREE.Shape();
    cfg.perimeter.forEach(([x, z], idx) => {
      if (idx === 0) shape.moveTo(x, z);
      else shape.lineTo(x, z);
    });
    shape.closePath();
    for (const c of cfg.cutouts) {
      if ((c.subtractFloor ?? true) && c.points.length >= 3) {
        const hole = new THREE.Path();
        c.points.forEach(([x, z], idx) => {
          if (idx === 0) hole.moveTo(x, z);
          else hole.lineTo(x, z);
        });
        hole.closePath();
        shape.holes.push(hole);
      }
    }
    const floorGeom = new THREE.ShapeGeometry(shape);
    floorGeom.rotateX(Math.PI / 2);
    floorGeom.translate(0, floorY + 0.04, 0);
    const floorMesh = new THREE.Mesh(
      floorGeom,
      new THREE.MeshBasicMaterial({
        color: 0x22e06a,
        transparent: true,
        opacity: 0.22,
        side: THREE.DoubleSide,
        depthWrite: false,
      }),
    );
    overlay.add(floorMesh);
  }

  // 2. Extruded perimeter walls (translucent cyan) + portal indicators (amber)
  if (cfg.perimeter.length >= 3) {
    const wallPositions: number[] = [];
    const linePts: THREE.Vector3[] = [];
    for (let i = 0; i < cfg.perimeter.length; i++) {
      const a = cfg.perimeter[i];
      const b = cfg.perimeter[(i + 1) % cfg.perimeter.length];
      linePts.push(new THREE.Vector3(a[0], floorY + 0.08, a[1]));
      for (const [t0, t1] of computeSolidEdgeSpans(i, cfg.openings)) {
        const x0 = a[0] + (b[0] - a[0]) * t0;
        const z0 = a[1] + (b[1] - a[1]) * t0;
        const x1 = a[0] + (b[0] - a[0]) * t1;
        const z1 = a[1] + (b[1] - a[1]) * t1;
        wallPositions.push(
          x0, wallBottom, z0,
          x1, wallBottom, z1,
          x1, wallTop, z1,
          x0, wallBottom, z0,
          x1, wallTop, z1,
          x0, wallTop, z0,
        );
      }
    }
    linePts.push(new THREE.Vector3(cfg.perimeter[0][0], floorY + 0.08, cfg.perimeter[0][1]));

    if (wallPositions.length) {
      const wg = new THREE.BufferGeometry();
      wg.setAttribute('position', new THREE.Float32BufferAttribute(wallPositions, 3));
      wg.computeVertexNormals();
      overlay.add(
        new THREE.Mesh(
          wg,
          new THREE.MeshBasicMaterial({
            color: 0x38bdf8,
            transparent: true,
            opacity: 0.28,
            side: THREE.DoubleSide,
            depthWrite: false,
          }),
        ),
      );
    }

    const perimLineGeom = new THREE.BufferGeometry().setFromPoints(linePts);
    overlay.add(
      new THREE.Line(
        perimLineGeom,
        new THREE.LineBasicMaterial({ color: activeLoop === 'perimeter' ? 0x38bdf8 : 0x64748b }),
      ),
    );

    // Portal / opening markers along edges
    for (const op of cfg.openings) {
      if (op.edge < 0 || op.edge >= cfg.perimeter.length) continue;
      const a = cfg.perimeter[op.edge];
      const b = cfg.perimeter[(op.edge + 1) % cfg.perimeter.length];
      const x0 = a[0] + (b[0] - a[0]) * op.tStart;
      const z0 = a[1] + (b[1] - a[1]) * op.tStart;
      const x1 = a[0] + (b[0] - a[0]) * op.tEnd;
      const z1 = a[1] + (b[1] - a[1]) * op.tEnd;
      const opGeom = new THREE.BufferGeometry().setFromPoints([
        new THREE.Vector3(x0, floorY + 0.25, z0),
        new THREE.Vector3(x1, floorY + 0.25, z1),
        new THREE.Vector3(x1, floorY + 2.2, z1),
        new THREE.Vector3(x0, floorY + 2.2, z0),
        new THREE.Vector3(x0, floorY + 0.25, z0),
      ]);
      overlay.add(
        new THREE.Line(
          opGeom,
          new THREE.LineBasicMaterial({ color: op.portalOnly ? 0xfbbf24 : 0x4ade80 }),
        ),
      );
    }
  }

  // 3. Cutout obstacle walls (translucent coral/red)
  for (const cutout of cfg.cutouts) {
    if (cutout.points.length < 3) continue;
    const cb = cutout.wallBottomY ?? floorY;
    const ct = cb + (cutout.wallHeight ?? cfg.wallHeight);
    const cVerts: number[] = [];
    const cLine: THREE.Vector3[] = [];
    for (let i = 0; i < cutout.points.length; i++) {
      const a = cutout.points[i];
      const b = cutout.points[(i + 1) % cutout.points.length];
      cLine.push(new THREE.Vector3(a[0], cb + 0.08, a[1]));
      cVerts.push(
        a[0], cb, a[1],
        b[0], cb, b[1],
        b[0], ct, b[1],
        a[0], cb, a[1],
        b[0], ct, b[1],
        a[0], ct, a[1],
      );
    }
    cLine.push(new THREE.Vector3(cutout.points[0][0], cb + 0.08, cutout.points[0][1]));
    const cg = new THREE.BufferGeometry();
    cg.setAttribute('position', new THREE.Float32BufferAttribute(cVerts, 3));
    cg.computeVertexNormals();
    overlay.add(
      new THREE.Mesh(
        cg,
        new THREE.MeshBasicMaterial({
          color: 0xf87171,
          transparent: true,
          opacity: 0.36,
          side: THREE.DoubleSide,
          depthWrite: false,
        }),
      ),
    );
    overlay.add(
      new THREE.Line(
        new THREE.BufferGeometry().setFromPoints(cLine),
        new THREE.LineBasicMaterial({ color: activeLoop === cutout.id ? 0xfca5a5 : 0xef4444 }),
      ),
    );
  }

  // 4. Interactive vertex & midpoint handles
  const addLoopHandles = (
    target: 'perimeter' | string,
    pts: [number, number][],
    yBase: number,
    baseColor: number,
  ) => {
    for (let i = 0; i < pts.length; i++) {
      const [x, z] = pts[i];
      const isSel = selected?.target === target && selected.index === i;
      const vSphere = new THREE.Mesh(
        new THREE.SphereGeometry(isSel ? 0.38 : 0.26, 12, 12),
        new THREE.MeshBasicMaterial({ color: isSel ? 0xfacc15 : baseColor }),
      );
      vSphere.position.set(x, yBase + 0.25, z);
      vSphere.userData = { handleKind: 'vertex', target, index: i, yPlane: yBase };
      overlay.add(vSphere);
      handleMeshes.push(vSphere);

      const next = pts[(i + 1) % pts.length];
      const midSphere = new THREE.Mesh(
        new THREE.SphereGeometry(0.16, 10, 10),
        new THREE.MeshBasicMaterial({ color: 0x94a3b8, transparent: true, opacity: 0.8 }),
      );
      midSphere.position.set((x + next[0]) * 0.5, yBase + 0.22, (z + next[1]) * 0.5);
      midSphere.userData = { handleKind: 'midpoint', target, edgeIndex: i, yPlane: yBase };
      overlay.add(midSphere);
      handleMeshes.push(midSphere);
    }
  };

  addLoopHandles('perimeter', cfg.perimeter, floorY, 0x38bdf8);
  for (const cutout of cfg.cutouts) {
    addLoopHandles(cutout.id, cutout.points, cutout.wallBottomY ?? floorY, 0xf87171);
  }

  // 5. Reference spawn / NPC / trigger pins (capsule radius = 0.4m ring + vertical pin)
  const pinColors: Record<ReferencePin['kind'], number> = {
    spawn: 0x22c55e,
    npc: 0xf59e0b,
    trigger: 0xa855f7,
  };
  for (const pin of pins) {
    const col = pinColors[pin.kind];
    const pole = new THREE.Mesh(
      new THREE.CylinderGeometry(0.08, 0.08, 1.8, 8),
      new THREE.MeshBasicMaterial({ color: col }),
    );
    pole.position.set(pin.pos[0], pin.pos[1] + 0.9, pin.pos[2]);
    overlay.add(pole);

    const ring = new THREE.Mesh(
      new THREE.RingGeometry(0.36, 0.44, 20),
      new THREE.MeshBasicMaterial({ color: col, side: THREE.DoubleSide }),
    );
    ring.rotation.x = -Math.PI / 2;
    ring.position.set(pin.pos[0], pin.pos[1] + 0.06, pin.pos[2]);
    overlay.add(ring);
  }
}
