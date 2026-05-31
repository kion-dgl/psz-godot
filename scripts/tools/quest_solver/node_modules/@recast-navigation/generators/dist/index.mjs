import { vec3, recastConfigDefaults, RecastBuildContext, VerticesArray, TrianglesArray, createRcConfig, calcGridSize, allocHeightfield, createHeightfield, TriangleAreasArray, markWalkableTriangles, rasterizeTriangles, filterLowHangingWalkableObstacles, filterLedgeSpans, filterWalkableLowHeightSpans, allocCompactHeightfield, buildCompactHeightfield, freeHeightfield, erodeWalkableArea, buildDistanceField, buildRegions, allocContourSet, buildContours, Recast, allocPolyMesh, buildPolyMesh, allocPolyMeshDetail, buildPolyMeshDetail, freeCompactHeightfield, freeContourSet, NavMeshCreateParams, createNavMeshData, Raw, NavMesh, freePolyMesh, freePolyMeshDetail, TileCacheMeshProcess, TileCache, DetourTileCacheParams, NavMeshParams, RecastChunkyTriMesh, statusFailed, cloneRcConfig, ChunkIdsArray, allocHeightfieldLayerSet, buildHeightfieldLayers, TileCacheData, Detour, getHeightfieldLayerHeights, getHeightfieldLayerAreas, getHeightfieldLayerCons, buildTileCacheLayer, freeHeightfieldLayerSet, statusToReadableString } from '@recast-navigation/core';

const getBoundingBox = (positions, indices) => {
  const bbMin = {
    x: Infinity,
    y: Infinity,
    z: Infinity
  };
  const bbMax = {
    x: -Infinity,
    y: -Infinity,
    z: -Infinity
  };
  for (let i = 0; i < indices.length; i++) {
    const ind = indices[i];
    const x = positions[ind * 3];
    const y = positions[ind * 3 + 1];
    const z = positions[ind * 3 + 2];
    bbMin.x = Math.min(bbMin.x, x);
    bbMin.y = Math.min(bbMin.y, y);
    bbMin.z = Math.min(bbMin.z, z);
    bbMax.x = Math.max(bbMax.x, x);
    bbMax.y = Math.max(bbMax.y, y);
    bbMax.z = Math.max(bbMax.z, z);
  }
  return {
    bbMin: vec3.toArray(bbMin),
    bbMax: vec3.toArray(bbMax)
  };
};
const dtIlog2 = v => {
  let r = 0;
  let shift = 0;
  r = Number(v > 0xffff) << 4;
  v >>= r;
  shift = Number(v > 0xff) << 3;
  v >>= shift;
  r |= shift;
  shift = Number(v > 0xf) << 2;
  v >>= shift;
  r |= shift;
  shift = Number(v > 0x3) << 1;
  v >>= shift;
  r |= shift;
  r |= v >> 1;
  return r;
};
const dtNextPow2 = v => {
  v--;
  v |= v >> 1;
  v |= v >> 2;
  v |= v >> 4;
  v |= v >> 8;
  v |= v >> 16;
  v++;
  return v;
};

const soloNavMeshGeneratorConfigDefaults = {
  ...recastConfigDefaults,
  buildBvTree: true
};
/**
 * Builds Solo NavMesh data from the given positions and indices.
 * @param positions a flat array of positions
 * @param indices a flat array of indices
 * @param navMeshGeneratorConfig optional configuration for the NavMesh generator
 * @param keepIntermediates if true intermediates will be returned
 */
const generateSoloNavMeshData = (positions, indices, navMeshGeneratorConfig = {}, keepIntermediates = false) => {
  const buildContext = new RecastBuildContext();
  const intermediates = {
    type: 'solo',
    buildContext
  };
  const cleanup = () => {
    if (keepIntermediates) return;
    if (intermediates.heightfield) {
      freeHeightfield(intermediates.heightfield);
      intermediates.heightfield = undefined;
    }
    if (intermediates.compactHeightfield) {
      freeCompactHeightfield(intermediates.compactHeightfield);
      intermediates.compactHeightfield = undefined;
    }
    if (intermediates.contourSet) {
      freeContourSet(intermediates.contourSet);
      intermediates.contourSet = undefined;
    }
    if (intermediates.polyMesh) {
      freePolyMesh(intermediates.polyMesh);
      intermediates.polyMesh = undefined;
    }
    if (intermediates.polyMeshDetail) {
      freePolyMeshDetail(intermediates.polyMeshDetail);
      intermediates.polyMeshDetail = undefined;
    }
  };
  const fail = error => {
    cleanup();
    return {
      navMeshData: undefined,
      success: false,
      intermediates,
      error
    };
  };
  /* input geometry */
  const vertices = positions;
  const numVertices = indices.length;
  const verticesArray = new VerticesArray();
  verticesArray.copy(vertices);
  const triangles = indices;
  const numTriangles = indices.length / 3;
  const trianglesArray = new TrianglesArray();
  trianglesArray.copy(triangles);
  let bbMin;
  let bbMax;
  if (navMeshGeneratorConfig.bounds) {
    bbMin = navMeshGeneratorConfig.bounds[0];
    bbMax = navMeshGeneratorConfig.bounds[1];
  } else {
    const boundingBox = getBoundingBox(positions, indices);
    bbMin = boundingBox.bbMin;
    bbMax = boundingBox.bbMax;
  }
  //
  // Step 1. Initialize build config.
  //
  const config = {
    ...soloNavMeshGeneratorConfigDefaults,
    ...navMeshGeneratorConfig
  };
  const rcConfig = createRcConfig(config);
  rcConfig.minRegionArea = rcConfig.minRegionArea * rcConfig.minRegionArea; // Note: area = size*size
  rcConfig.mergeRegionArea = rcConfig.mergeRegionArea * rcConfig.mergeRegionArea; // Note: area = size*size
  rcConfig.detailSampleDist = rcConfig.detailSampleDist < 0.9 ? 0 : rcConfig.cs * rcConfig.detailSampleDist;
  rcConfig.detailSampleMaxError = rcConfig.ch * rcConfig.detailSampleMaxError;
  const gridSize = calcGridSize(bbMin, bbMax, rcConfig.cs);
  rcConfig.width = gridSize.width;
  rcConfig.height = gridSize.height;
  //
  // Step 2. Rasterize input polygon soup.
  //
  // Allocate voxel heightfield where we rasterize our input data to.
  const heightfield = allocHeightfield();
  intermediates.heightfield = heightfield;
  if (!createHeightfield(buildContext, heightfield, rcConfig.width, rcConfig.height, bbMin, bbMax, rcConfig.cs, rcConfig.ch)) {
    return fail('Could not create heightfield');
  }
  // Find triangles which are walkable based on their slope and rasterize them.
  // If your input data is multiple meshes, you can transform them here, calculate
  // the are type for each of the meshes and rasterize them.
  const triangleAreasArray = new TriangleAreasArray();
  triangleAreasArray.resize(numTriangles);
  markWalkableTriangles(buildContext, rcConfig.walkableSlopeAngle, verticesArray, numVertices, trianglesArray, numTriangles, triangleAreasArray);
  if (!rasterizeTriangles(buildContext, verticesArray, numVertices, trianglesArray, triangleAreasArray, numTriangles, heightfield, rcConfig.walkableClimb)) {
    return fail('Could not rasterize triangles');
  }
  triangleAreasArray.destroy();
  verticesArray.destroy();
  trianglesArray.destroy();
  //
  // Step 3. Filter walkables surfaces.
  //
  // Once all geoemtry is rasterized, we do initial pass of filtering to
  // remove unwanted overhangs caused by the conservative rasterization
  // as well as filter spans where the character cannot possibly stand.
  filterLowHangingWalkableObstacles(buildContext, rcConfig.walkableClimb, heightfield);
  filterLedgeSpans(buildContext, rcConfig.walkableHeight, rcConfig.walkableClimb, heightfield);
  filterWalkableLowHeightSpans(buildContext, rcConfig.walkableHeight, heightfield);
  //
  // Step 4. Partition walkable surface to simple regions.
  //
  // Compact the heightfield so that it is faster to handle from now on.
  // This will result more cache coherent data as well as the neighbours
  // between walkable cells will be calculated.
  const compactHeightfield = allocCompactHeightfield();
  intermediates.compactHeightfield = compactHeightfield;
  if (!buildCompactHeightfield(buildContext, rcConfig.walkableHeight, rcConfig.walkableClimb, heightfield, compactHeightfield)) {
    return fail('Failed to build compact data');
  }
  if (!keepIntermediates) {
    freeHeightfield(heightfield);
    intermediates.heightfield = undefined;
  }
  // Erode the walkable area by agent radius.
  if (!erodeWalkableArea(buildContext, rcConfig.walkableRadius, compactHeightfield)) {
    return fail('Failed to erode walkable area');
  }
  // (Optional) Mark areas
  // markConvexPolyArea(...)
  // Prepare for region partitioning, by calculating Distance field along the walkable surface.
  if (!buildDistanceField(buildContext, compactHeightfield)) {
    return fail('Failed to build distance field');
  }
  // Partition the walkable surface into simple regions without holes.
  if (!buildRegions(buildContext, compactHeightfield, rcConfig.borderSize, rcConfig.minRegionArea, rcConfig.mergeRegionArea)) {
    return fail('Failed to build regions');
  }
  //
  // Step 5. Trace and simplify region contours.
  //
  const contourSet = allocContourSet();
  intermediates.contourSet = contourSet;
  if (!buildContours(buildContext, compactHeightfield, rcConfig.maxSimplificationError, rcConfig.maxEdgeLen, contourSet, Recast.RC_CONTOUR_TESS_WALL_EDGES)) {
    return fail('Failed to create contours');
  }
  //
  // Step 6. Build polygons mesh from contours.
  //
  const polyMesh = allocPolyMesh();
  intermediates.polyMesh = polyMesh;
  if (!buildPolyMesh(buildContext, contourSet, rcConfig.maxVertsPerPoly, polyMesh)) {
    return fail('Failed to triangulate contours');
  }
  //
  // Step 7. Create detail mesh which allows to access approximate height on each polygon.
  //
  const polyMeshDetail = allocPolyMeshDetail();
  intermediates.polyMeshDetail = polyMeshDetail;
  if (!buildPolyMeshDetail(buildContext, polyMesh, compactHeightfield, rcConfig.detailSampleDist, rcConfig.detailSampleMaxError, polyMeshDetail)) {
    return fail('Failed to build detail mesh');
  }
  if (!keepIntermediates) {
    freeCompactHeightfield(compactHeightfield);
    intermediates.compactHeightfield = undefined;
    freeContourSet(contourSet);
    intermediates.contourSet = undefined;
  }
  //
  // Step 8. Create Detour data from Recast poly mesh.
  //
  for (let i = 0; i < polyMesh.npolys(); i++) {
    if (polyMesh.areas(i) === Recast.RC_WALKABLE_AREA) {
      polyMesh.setAreas(i, 0);
    }
    if (polyMesh.areas(i) === 0) {
      polyMesh.setFlags(i, 1);
    }
  }
  const navMeshCreateParams = new NavMeshCreateParams();
  navMeshCreateParams.setPolyMeshCreateParams(polyMesh);
  navMeshCreateParams.setPolyMeshDetailCreateParams(polyMeshDetail);
  navMeshCreateParams.setWalkableHeight(rcConfig.walkableHeight * rcConfig.ch);
  navMeshCreateParams.setWalkableRadius(rcConfig.walkableRadius * rcConfig.cs);
  navMeshCreateParams.setWalkableClimb(rcConfig.walkableClimb * rcConfig.ch);
  navMeshCreateParams.setCellSize(rcConfig.cs);
  navMeshCreateParams.setCellHeight(rcConfig.ch);
  navMeshCreateParams.setBuildBvTree(config.buildBvTree);
  if (navMeshGeneratorConfig.offMeshConnections) {
    navMeshCreateParams.setOffMeshConnections(navMeshGeneratorConfig.offMeshConnections);
  }
  const createNavMeshDataResult = createNavMeshData(navMeshCreateParams);
  if (!createNavMeshDataResult.success) {
    return fail('Failed to create Detour navmesh data');
  }
  cleanup();
  return {
    navMeshData: createNavMeshDataResult.navMeshData,
    success: true,
    intermediates
  };
};
/**
 * Builds a Solo NavMesh from the given positions and indices.
 * @param positions a flat array of positions
 * @param indices a flat array of indices
 * @param navMeshGeneratorConfig optional configuration for the NavMesh generator
 * @param keepIntermediates if true intermediates will be returned
 */
const generateSoloNavMesh = (positions, indices, navMeshGeneratorConfig = {}, keepIntermediates = false) => {
  if (!Raw.Module) {
    throw new Error('"init" must be called before using any recast-navigation-js APIs. See: https://github.com/isaac-mason/recast-navigation-js?tab=readme-ov-file#initialization');
  }
  const createNavMeshDataResult = generateSoloNavMeshData(positions, indices, navMeshGeneratorConfig, keepIntermediates);
  if (!createNavMeshDataResult.success) {
    return {
      navMesh: undefined,
      success: false,
      intermediates: createNavMeshDataResult.intermediates,
      error: createNavMeshDataResult.error
    };
  }
  const {
    navMeshData
  } = createNavMeshDataResult;
  const navMesh = new NavMesh();
  if (!navMesh.initSolo(navMeshData)) {
    navMeshData.destroy();
    return {
      navMesh: undefined,
      success: false,
      intermediates: createNavMeshDataResult.intermediates,
      error: 'Failed to initialize solo NavMesh'
    };
  }
  return {
    success: true,
    navMesh,
    intermediates: createNavMeshDataResult.intermediates
  };
};

const tileCacheGeneratorConfigDefaults = {
  ...recastConfigDefaults,
  tileSize: 32,
  expectedLayersPerTile: 4,
  maxObstacles: 128
};
const createDefaultTileCacheMeshProcess = () => new TileCacheMeshProcess((navMeshCreateParams, polyAreas, polyFlags) => {
  for (let i = 0; i < navMeshCreateParams.polyCount(); ++i) {
    polyAreas.set(i, 0);
    polyFlags.set(i, 1);
  }
});
/**
 * Builds a TileCache and NavMesh from the given positions and indices.
 * TileCache assumes small tiles (around 32-64 squared) and does some tricks to make the update fast.
 * @param positions a flat array of positions
 * @param indices a flat array of indices
 * @param navMeshConfig optional configuration for the NavMesh
 * @param keepIntermediates if true intermediates will be returned
 */
const generateTileCache = (positions, indices, navMeshGeneratorConfig = {}, keepIntermediates = false) => {
  if (!Raw.Module) {
    throw new Error('"init" must be called before using any recast-navigation-js APIs. See: https://github.com/isaac-mason/recast-navigation-js?tab=readme-ov-file#initialization');
  }
  const buildContext = new RecastBuildContext();
  const intermediates = {
    type: 'tilecache',
    buildContext,
    chunkyTriMesh: undefined,
    tileIntermediates: []
  };
  const tileCache = new TileCache();
  const navMesh = new NavMesh();
  /* input geometry */
  const vertices = positions;
  const numVertices = indices.length;
  const verticesArray = new VerticesArray();
  verticesArray.copy(vertices);
  const triangles = indices;
  const numTriangles = indices.length / 3;
  const trianglesArray = new TrianglesArray();
  trianglesArray.copy(triangles);
  let bbMin;
  let bbMax;
  if (navMeshGeneratorConfig.bounds) {
    bbMin = navMeshGeneratorConfig.bounds[0];
    bbMax = navMeshGeneratorConfig.bounds[1];
  } else {
    const boundingBox = getBoundingBox(positions, indices);
    bbMin = boundingBox.bbMin;
    bbMax = boundingBox.bbMax;
  }
  const {
    expectedLayersPerTile,
    maxObstacles,
    ...recastConfig
  } = {
    ...tileCacheGeneratorConfigDefaults,
    ...navMeshGeneratorConfig
  };
  const cleanup = () => {
    verticesArray.destroy();
    trianglesArray.destroy();
    if (!keepIntermediates) {
      for (let i = 0; i < intermediates.tileIntermediates.length; i++) {
        const tileIntermediate = intermediates.tileIntermediates[i];
        if (tileIntermediate.heightfield) {
          freeHeightfield(tileIntermediate.heightfield);
          tileIntermediate.heightfield = undefined;
        }
        if (tileIntermediate.compactHeightfield) {
          freeCompactHeightfield(tileIntermediate.compactHeightfield);
          tileIntermediate.compactHeightfield = undefined;
        }
        if (tileIntermediate.heightfieldLayerSet) {
          freeHeightfieldLayerSet(tileIntermediate.heightfieldLayerSet);
          tileIntermediate.heightfieldLayerSet = undefined;
        }
      }
    }
  };
  const fail = error => {
    cleanup();
    tileCache.destroy();
    navMesh.destroy();
    return {
      success: false,
      navMesh: undefined,
      tileCache: undefined,
      intermediates,
      error
    };
  };
  //
  // Step 1. Initialize build config.
  //
  const config = createRcConfig(recastConfig);
  const gridSize = calcGridSize(bbMin, bbMax, config.cs);
  config.width = gridSize.width;
  config.height = gridSize.height;
  config.minRegionArea = config.minRegionArea * config.minRegionArea; // Note: area = size*size
  config.mergeRegionArea = config.mergeRegionArea * config.mergeRegionArea; // Note: area = size*size
  config.detailSampleDist = config.detailSampleDist < 0.9 ? 0 : config.cs * config.detailSampleDist;
  config.detailSampleMaxError = config.ch * config.detailSampleMaxError;
  const tileSize = Math.floor(config.tileSize);
  const tileWidth = Math.floor((config.width + tileSize - 1) / tileSize);
  const tileHeight = Math.floor((config.height + tileSize - 1) / tileSize);
  // Generation params
  config.borderSize = config.walkableRadius + 3; // Reserve enough padding.
  config.width = config.tileSize + config.borderSize * 2;
  config.height = config.tileSize + config.borderSize * 2;
  // Tile cache params
  const tileCacheParams = DetourTileCacheParams.create({
    orig: bbMin,
    cs: config.cs,
    ch: config.ch,
    width: config.tileSize,
    height: config.tileSize,
    walkableHeight: config.walkableHeight * config.ch,
    walkableRadius: config.walkableRadius * config.cs,
    walkableClimb: config.walkableClimb * config.ch,
    maxSimplificationError: config.maxSimplificationError,
    maxTiles: tileWidth * tileHeight * expectedLayersPerTile,
    maxObstacles
  });
  const allocator = new Raw.RecastLinearAllocator(32000);
  const compressor = new Raw.RecastFastLZCompressor();
  const tileCacheMeshProcess = navMeshGeneratorConfig.tileCacheMeshProcess ?? createDefaultTileCacheMeshProcess();
  if (!tileCache.init(tileCacheParams, allocator, compressor, tileCacheMeshProcess)) {
    return fail('Failed to initialize tile cache');
  }
  const orig = vec3.fromArray(bbMin);
  // Max tiles and max polys affect how the tile IDs are caculated.
  // There are 22 bits available for identifying a tile and a polygon.
  let tileBits = Math.min(Math.floor(dtIlog2(dtNextPow2(tileWidth * tileHeight * expectedLayersPerTile))), 14);
  if (tileBits > 14) {
    tileBits = 14;
  }
  const polyBits = 22 - tileBits;
  const maxTiles = 1 << tileBits;
  const maxPolysPerTile = 1 << polyBits;
  const navMeshParams = NavMeshParams.create({
    orig,
    tileWidth: config.tileSize * config.cs,
    tileHeight: config.tileSize * config.cs,
    maxTiles,
    maxPolys: maxPolysPerTile
  });
  if (!navMesh.initTiled(navMeshParams)) {
    return fail('Failed to initialize tiled navmesh');
  }
  const chunkyTriMesh = new RecastChunkyTriMesh();
  intermediates.chunkyTriMesh = chunkyTriMesh;
  if (!chunkyTriMesh.init(verticesArray, trianglesArray, numTriangles, 256)) {
    return fail('Failed to build chunky triangle mesh');
  }
  const rasterizeTileLayers = (tileX, tileY) => {
    // Tile intermediates
    const tileIntermediates = {
      tileX,
      tileY
    };
    // Tile bounds
    const tcs = config.tileSize * config.cs;
    const tileConfig = cloneRcConfig(config);
    const tileBoundsMin = [bbMin[0] + tileX * tcs, bbMin[1], bbMin[2] + tileY * tcs];
    const tileBoundsMax = [bbMin[0] + (tileX + 1) * tcs, bbMax[1], bbMin[2] + (tileY + 1) * tcs];
    tileBoundsMin[0] -= tileConfig.borderSize * tileConfig.cs;
    tileBoundsMin[2] -= tileConfig.borderSize * tileConfig.cs;
    tileBoundsMax[0] += tileConfig.borderSize * tileConfig.cs;
    tileBoundsMax[2] += tileConfig.borderSize * tileConfig.cs;
    tileConfig.set_bmin(0, tileBoundsMin[0]);
    tileConfig.set_bmin(1, tileBoundsMin[1]);
    tileConfig.set_bmin(2, tileBoundsMin[2]);
    tileConfig.set_bmax(0, tileBoundsMax[0]);
    tileConfig.set_bmax(1, tileBoundsMax[1]);
    tileConfig.set_bmax(2, tileBoundsMax[2]);
    // Allocate voxel heightfield where we rasterize our input data to.
    const heightfield = allocHeightfield();
    tileIntermediates.heightfield = heightfield;
    if (!createHeightfield(buildContext, heightfield, tileConfig.width, tileConfig.height, tileBoundsMin, tileBoundsMax, tileConfig.cs, tileConfig.ch)) {
      return {
        n: 0
      };
    }
    const tbmin = [tileBoundsMin[0], tileBoundsMin[2]];
    const tbmax = [tileBoundsMax[0], tileBoundsMax[2]];
    // TODO: Make grow when returning too many items.
    const maxChunkIds = 512;
    const chunkIdsArray = new ChunkIdsArray();
    chunkIdsArray.resize(maxChunkIds);
    const nChunksOverlapping = chunkyTriMesh.getChunksOverlappingRect(tbmin, tbmax, chunkIdsArray, maxChunkIds);
    if (nChunksOverlapping === 0) {
      return {
        n: 0
      };
    }
    for (let i = 0; i < nChunksOverlapping; ++i) {
      const nodeId = chunkIdsArray.get(i);
      const node = chunkyTriMesh.nodes(nodeId);
      const nNodeTris = node.n;
      const nodeTrianglesArray = chunkyTriMesh.getNodeTris(nodeId);
      const triangleAreasArray = new TriangleAreasArray();
      triangleAreasArray.resize(nNodeTris);
      // Find triangles which are walkable based on their slope and rasterize them.
      // If your input data is multiple meshes, you can transform them here, calculate
      // the are type for each of the meshes and rasterize them.
      markWalkableTriangles(buildContext, tileConfig.walkableSlopeAngle, verticesArray, numVertices, nodeTrianglesArray, nNodeTris, triangleAreasArray);
      const success = rasterizeTriangles(buildContext, verticesArray, numVertices, nodeTrianglesArray, triangleAreasArray, nNodeTris, heightfield, tileConfig.walkableClimb);
      triangleAreasArray.destroy();
      if (!success) {
        return {
          n: 0
        };
      }
    }
    // Once all geometry is rasterized, we do initial pass of filtering to
    // remove unwanted overhangs caused by the conservative rasterization
    // as well as filter spans where the character cannot possibly stand.
    filterLowHangingWalkableObstacles(buildContext, config.walkableClimb, heightfield);
    filterLedgeSpans(buildContext, config.walkableHeight, config.walkableClimb, heightfield);
    filterWalkableLowHeightSpans(buildContext, config.walkableHeight, heightfield);
    const compactHeightfield = allocCompactHeightfield();
    if (!buildCompactHeightfield(buildContext, config.walkableHeight, config.walkableClimb, heightfield, compactHeightfield)) {
      return {
        n: 0
      };
    }
    if (!keepIntermediates) {
      freeHeightfield(tileIntermediates.heightfield);
      tileIntermediates.heightfield = undefined;
    }
    // Erode the walkable area by agent radius
    if (!erodeWalkableArea(buildContext, config.walkableRadius, compactHeightfield)) {
      return {
        n: 0
      };
    }
    const heightfieldLayerSet = allocHeightfieldLayerSet();
    if (!buildHeightfieldLayers(buildContext, compactHeightfield, config.borderSize, config.walkableHeight, heightfieldLayerSet)) {
      return {
        n: 0
      };
    }
    if (!keepIntermediates) {
      freeCompactHeightfield(compactHeightfield);
      tileIntermediates.compactHeightfield = undefined;
    }
    const tiles = [];
    for (let i = 0; i < heightfieldLayerSet.nlayers(); i++) {
      const tile = new TileCacheData();
      const heightfieldLayer = heightfieldLayerSet.layers(i);
      // Store header
      const header = new Raw.dtTileCacheLayerHeader();
      header.magic = Detour.DT_TILECACHE_MAGIC;
      header.version = Detour.DT_TILECACHE_VERSION;
      // Tile layer location in the navmesh
      header.tx = tileX;
      header.ty = tileY;
      header.tlayer = i;
      const heightfieldLayerBin = heightfieldLayer.bmin();
      const heightfieldLayerBmax = heightfieldLayer.bmax();
      header.set_bmin(0, heightfieldLayerBin.x);
      header.set_bmin(1, heightfieldLayerBin.y);
      header.set_bmin(2, heightfieldLayerBin.z);
      header.set_bmax(0, heightfieldLayerBmax.x);
      header.set_bmax(1, heightfieldLayerBmax.y);
      header.set_bmax(2, heightfieldLayerBmax.z);
      // Tile info
      header.width = heightfieldLayer.width();
      header.height = heightfieldLayer.height();
      header.minx = heightfieldLayer.minx();
      header.maxx = heightfieldLayer.maxx();
      header.miny = heightfieldLayer.miny();
      header.maxy = heightfieldLayer.maxy();
      header.hmin = heightfieldLayer.hmin();
      header.hmax = heightfieldLayer.hmax();
      const heights = getHeightfieldLayerHeights(heightfieldLayer);
      const areas = getHeightfieldLayerAreas(heightfieldLayer);
      const cons = getHeightfieldLayerCons(heightfieldLayer);
      const status = buildTileCacheLayer(compressor, header, heights, areas, cons, tile);
      if (statusFailed(status)) {
        return {
          n: 0
        };
      }
      tiles.push(tile);
    }
    if (!keepIntermediates) {
      freeHeightfieldLayerSet(heightfieldLayerSet);
      tileIntermediates.heightfieldLayerSet = undefined;
    }
    intermediates.tileIntermediates.push(tileIntermediates);
    return {
      n: tiles.length,
      tiles
    };
  };
  // Preprocess tiles
  for (let y = 0; y < tileHeight; ++y) {
    for (let x = 0; x < tileWidth; ++x) {
      const {
        n,
        tiles: newTiles
      } = rasterizeTileLayers(x, y);
      if (n > 0 && newTiles) {
        for (let i = 0; i < n; i++) {
          const tileCacheData = newTiles[i];
          const addResult = tileCache.addTile(tileCacheData);
          if (statusFailed(addResult.status)) {
            buildContext.log(Recast.RC_LOG_WARNING, `Failed to add tile to tile cache - tx: ${x}, ty: ${y}`);
          }
        }
      }
    }
  }
  // Build initial meshes
  for (let y = 0; y < tileHeight; y++) {
    for (let x = 0; x < tileWidth; x++) {
      const dtStatus = tileCache.buildNavMeshTilesAt(x, y, navMesh);
      if (statusFailed(dtStatus)) {
        return fail(`Failed to build nav mesh tiles at ${x}, ${y}`);
      }
    }
  }
  cleanup();
  return {
    success: true,
    tileCache,
    navMesh,
    intermediates
  };
};

const buildTiledNavMeshRcConfig = ({
  recastConfig,
  navMeshBounds: [navMeshBoundsMin, navMeshBoundsMax]
}) => {
  //
  // Initialize build config.
  //
  const config = createRcConfig(recastConfig);
  /* grid size */
  const gridSize = calcGridSize(navMeshBoundsMin, navMeshBoundsMax, config.cs);
  config.width = gridSize.width;
  config.height = gridSize.height;
  config.minRegionArea = config.minRegionArea * config.minRegionArea; // Note: area = size*size
  config.mergeRegionArea = config.mergeRegionArea * config.mergeRegionArea; // Note: area = size*size
  config.tileSize = Math.floor(config.tileSize);
  config.borderSize = config.walkableRadius + 3; // Reserve enough padding.
  config.width = config.tileSize + config.borderSize * 2;
  config.height = config.tileSize + config.borderSize * 2;
  config.detailSampleDist = config.detailSampleDist < 0.9 ? 0 : config.cs * config.detailSampleDist;
  config.detailSampleMaxError = config.ch * config.detailSampleMaxError;
  // tile size
  const tileSize = Math.floor(config.tileSize);
  const tileWidth = Math.floor((gridSize.width + tileSize - 1) / tileSize);
  const tileHeight = Math.floor((gridSize.height + tileSize - 1) / tileSize);
  const tcs = config.tileSize * config.cs;
  /* Create dtNavMeshParams, initialise nav mesh for tiled use */
  const orig = vec3.fromArray(navMeshBoundsMin);
  // Max tiles and max polys affect how the tile IDs are caculated.
  // There are 22 bits available for identifying a tile and a polygon.
  let tileBits = Math.min(Math.floor(dtIlog2(dtNextPow2(tileWidth * tileHeight))), 14);
  if (tileBits > 14) tileBits = 14;
  const polyBits = 22 - tileBits;
  const maxTiles = 1 << tileBits;
  const maxPolysPerTile = 1 << polyBits;
  return {
    config,
    gridSize,
    tileSize,
    tileWidth,
    tileHeight,
    tcs,
    orig,
    maxTiles,
    maxPolysPerTile
  };
};
const tiledNavMeshGeneratorConfigDefaults = {
  ...recastConfigDefaults,
  chunkyTriMeshTrisPerChunk: 256,
  buildBvTree: true
};
const generateTileNavMeshData = (positions, indices, rcConfig, chunkyTriMesh, tile, options = {}, keepIntermediates = false, buildContext = new RecastBuildContext()) => {
  const tileIntermediate = {
    x: tile.x,
    y: tile.y
  };
  const cleanup = () => {
    if (keepIntermediates) return;
    if (tileIntermediate.compactHeightfield) {
      freeCompactHeightfield(tileIntermediate.compactHeightfield);
      tileIntermediate.compactHeightfield = undefined;
    }
    if (tileIntermediate.heightfield) {
      freeHeightfield(tileIntermediate.heightfield);
      tileIntermediate.heightfield = undefined;
    }
    if (tileIntermediate.contourSet) {
      freeContourSet(tileIntermediate.contourSet);
      tileIntermediate.contourSet = undefined;
    }
    if (tileIntermediate.polyMesh) {
      freePolyMesh(tileIntermediate.polyMesh);
      tileIntermediate.polyMesh = undefined;
    }
    if (tileIntermediate.polyMeshDetail) {
      freePolyMeshDetail(tileIntermediate.polyMeshDetail);
      tileIntermediate.polyMeshDetail = undefined;
    }
  };
  const failTileMesh = error => {
    buildContext.log(Recast.RC_LOG_ERROR, error);
    cleanup();
    return {
      success: false,
      error,
      intermediates: tileIntermediate
    };
  };
  const tileConfig = cloneRcConfig(rcConfig);
  // Expand the heightfield bounding box by border size to find the extents of geometry we need to build this tile.
  //
  // This is done in order to make sure that the navmesh tiles connect correctly at the borders,
  // and the obstacles close to the border work correctly with the dilation process.
  // No polygons (or contours) will be created on the border area.
  //
  // IMPORTANT!
  //
  //   :''''''''':
  //   : +-----+ :
  //   : |     | :
  //   : |     |<--- tile to build
  //   : |     | :
  //   : +-----+ :<-- geometry needed
  //   :.........:
  //
  // You should use this bounding box to query your input geometry.
  //
  // For example if you build a navmesh for terrain, and want the navmesh tiles to match the terrain tile size
  // you will need to pass in data from neighbour terrain tiles too! In a simple case, just pass in all the 8 neighbours,
  // or use the bounding box below to only pass in a sliver of each of the 8 neighbours.
  const expandedTileBoundsMin = [...tile.bmin];
  const expandedTileBoundsMax = [...tile.bmax];
  expandedTileBoundsMin[0] -= tileConfig.borderSize * tileConfig.cs;
  expandedTileBoundsMin[2] -= tileConfig.borderSize * tileConfig.cs;
  expandedTileBoundsMax[0] += tileConfig.borderSize * tileConfig.cs;
  expandedTileBoundsMax[2] += tileConfig.borderSize * tileConfig.cs;
  tileConfig.set_bmin(0, expandedTileBoundsMin[0]);
  tileConfig.set_bmin(1, expandedTileBoundsMin[1]);
  tileConfig.set_bmin(2, expandedTileBoundsMin[2]);
  tileConfig.set_bmax(0, expandedTileBoundsMax[0]);
  tileConfig.set_bmax(1, expandedTileBoundsMax[1]);
  tileConfig.set_bmax(2, expandedTileBoundsMax[2]);
  // Reset build timer
  buildContext.resetTimers();
  // Start the build process
  buildContext.startTimer(Recast.RC_TIMER_TOTAL);
  buildContext.log(Recast.RC_LOG_PROGRESS, `Building tile at x: ${tile.x}, y: ${tile.y}`);
  buildContext.log(Recast.RC_LOG_PROGRESS, ` - ${tileConfig.width} x ${tileConfig.height} cells`);
  buildContext.log(Recast.RC_LOG_PROGRESS, ` - ${positions.size / 3 / 1000}K verts, ${indices.size / 3 / 1000}K tris`);
  // Allocate voxel heightfield where we rasterize our input data to.
  const heightfield = allocHeightfield();
  tileIntermediate.heightfield = heightfield;
  if (!createHeightfield(buildContext, heightfield, tileConfig.width, tileConfig.height, expandedTileBoundsMin, expandedTileBoundsMax, tileConfig.cs, tileConfig.ch)) {
    return failTileMesh('Could not create heightfield');
  }
  // Allocate array that can hold triangle flags.
  // If you have multiple meshes you need to process, allocate
  // and array which can hold the max number of triangles you need to process.
  const triAreas = new TriangleAreasArray();
  triAreas.resize(chunkyTriMesh.maxTrisPerChunk());
  const tbmin = [expandedTileBoundsMin[0], expandedTileBoundsMin[2]];
  const tbmax = [expandedTileBoundsMax[0], expandedTileBoundsMax[2]];
  // TODO: Make grow when returning too many items.
  const maxChunkIds = 512;
  const chunkIdsArray = new ChunkIdsArray();
  chunkIdsArray.resize(maxChunkIds);
  const nChunksOverlapping = chunkyTriMesh.getChunksOverlappingRect(tbmin, tbmax, chunkIdsArray, maxChunkIds);
  if (nChunksOverlapping === 0) {
    return {
      success: true,
      intermediates: tileIntermediate
    };
  }
  for (let i = 0; i < nChunksOverlapping; ++i) {
    const nodeId = chunkIdsArray.get(i);
    const node = chunkyTriMesh.nodes(nodeId);
    const nNodeTris = node.n;
    const nodeTrianglesArray = chunkyTriMesh.getNodeTris(nodeId);
    const triangleAreasArray = new TriangleAreasArray();
    triangleAreasArray.resize(nNodeTris);
    // Find triangles which are walkable based on their slope and rasterize them.
    // If your input data is multiple meshes, you can transform them here, calculate
    // the are type for each of the meshes and rasterize them.
    markWalkableTriangles(buildContext, tileConfig.walkableSlopeAngle, positions, indices.size, nodeTrianglesArray, nNodeTris, triangleAreasArray);
    const success = rasterizeTriangles(buildContext, positions, indices.size, nodeTrianglesArray, triangleAreasArray, nNodeTris, heightfield, tileConfig.walkableClimb);
    triangleAreasArray.destroy();
    if (!success) {
      return failTileMesh('Could not rasterize triangles');
    }
  }
  // Once all geometry is rasterized, we do initial pass of filtering to
  // remove unwanted overhangs caused by the conservative rasterization
  // as well as filter spans where the character cannot possibly stand.
  filterLowHangingWalkableObstacles(buildContext, tileConfig.walkableClimb, heightfield);
  filterLedgeSpans(buildContext, tileConfig.walkableHeight, tileConfig.walkableClimb, heightfield);
  filterWalkableLowHeightSpans(buildContext, tileConfig.walkableHeight, heightfield);
  // Compact the heightfield so that it is faster to handle from now on.
  // This will result more cache coherent data as well as the neighbours
  // between walkable cells will be calculated.
  const compactHeightfield = allocCompactHeightfield();
  tileIntermediate.compactHeightfield = compactHeightfield;
  if (!buildCompactHeightfield(buildContext, tileConfig.walkableHeight, tileConfig.walkableClimb, heightfield, compactHeightfield)) {
    return failTileMesh('Could not build compact heightfield');
  }
  if (!keepIntermediates) {
    freeHeightfield(tileIntermediate.heightfield);
    tileIntermediate.heightfield = undefined;
  }
  // Erode the walkable area by agent radius
  if (!erodeWalkableArea(buildContext, tileConfig.walkableRadius, compactHeightfield)) {
    return failTileMesh('Could not erode walkable area');
  }
  // (Optional) Mark areas
  // markConvexPolyArea(...)
  // Prepare for region partitioning, by calculating Distance field along the walkable surface.
  if (!buildDistanceField(buildContext, compactHeightfield)) {
    return failTileMesh('Failed to build distance field');
  }
  // Partition the walkable surface into simple regions without holes.
  if (!buildRegions(buildContext, compactHeightfield, tileConfig.borderSize, tileConfig.minRegionArea, tileConfig.mergeRegionArea)) {
    return failTileMesh('Failed to build regions');
  }
  //
  // Trace and simplify region contours.
  //
  const contourSet = allocContourSet();
  tileIntermediate.contourSet = contourSet;
  if (!buildContours(buildContext, compactHeightfield, tileConfig.maxSimplificationError, tileConfig.maxEdgeLen, contourSet, Recast.RC_CONTOUR_TESS_WALL_EDGES)) {
    return failTileMesh('Failed to create contours');
  }
  //
  // Build polygons mesh from contours.
  //
  const polyMesh = allocPolyMesh();
  tileIntermediate.polyMesh = polyMesh;
  if (!buildPolyMesh(buildContext, contourSet, tileConfig.maxVertsPerPoly, polyMesh)) {
    return failTileMesh('Failed to triangulate contours');
  }
  //
  // Create detail mesh which allows to access approximate height on each polygon.
  //
  const polyMeshDetail = allocPolyMeshDetail();
  tileIntermediate.polyMeshDetail = polyMeshDetail;
  if (!buildPolyMeshDetail(buildContext, polyMesh, compactHeightfield, tileConfig.detailSampleDist, tileConfig.detailSampleMaxError, polyMeshDetail)) {
    return failTileMesh('Failed to build detail mesh');
  }
  if (!keepIntermediates) {
    freeCompactHeightfield(compactHeightfield);
    tileIntermediate.compactHeightfield = undefined;
    freeContourSet(contourSet);
    tileIntermediate.contourSet = undefined;
  }
  // Update poly flags from areas.
  for (let i = 0; i < polyMesh.npolys(); i++) {
    if (polyMesh.areas(i) === Recast.RC_WALKABLE_AREA) {
      polyMesh.setAreas(i, 0);
    }
    if (polyMesh.areas(i) === 0) {
      polyMesh.setFlags(i, 1);
    }
  }
  const navMeshCreateParams = new NavMeshCreateParams();
  navMeshCreateParams.setPolyMeshCreateParams(polyMesh);
  navMeshCreateParams.setPolyMeshDetailCreateParams(polyMeshDetail);
  navMeshCreateParams.setWalkableHeight(tileConfig.walkableHeight * tileConfig.ch);
  navMeshCreateParams.setWalkableRadius(tileConfig.walkableRadius * tileConfig.cs);
  navMeshCreateParams.setWalkableClimb(tileConfig.walkableClimb * tileConfig.ch);
  navMeshCreateParams.setCellSize(tileConfig.cs);
  navMeshCreateParams.setCellHeight(tileConfig.ch);
  navMeshCreateParams.setBuildBvTree(options.buildBvTree ?? tiledNavMeshGeneratorConfigDefaults.buildBvTree);
  if (options.offMeshConnections) {
    navMeshCreateParams.setOffMeshConnections(options.offMeshConnections);
  }
  navMeshCreateParams.setTileX(tile.x);
  navMeshCreateParams.setTileY(tile.y);
  const createNavMeshDataResult = createNavMeshData(navMeshCreateParams);
  if (!createNavMeshDataResult.success) {
    return failTileMesh('Failed to create Detour navmesh data');
  }
  buildContext.log(Recast.RC_LOG_PROGRESS, `>> Polymesh: ${polyMesh.nverts()} vertices  ${polyMesh.npolys()} polygons`);
  return {
    success: true,
    data: createNavMeshDataResult.navMeshData,
    intermediates: tileIntermediate
  };
};
/**
 * Builds a Tiled NavMesh
 * @param positions a flat array of positions
 * @param indices a flat array of indices
 * @param navMeshGeneratorConfig optional configuration for the NavMesh generator
 * @param keepIntermediates if true intermediates will be returned
 */
const generateTiledNavMesh = (positions, indices, navMeshGeneratorConfig = {}, keepIntermediates = false) => {
  if (!Raw.Module) {
    throw new Error('"init" must be called before using any recast-navigation-js APIs. See: https://github.com/isaac-mason/recast-navigation-js?tab=readme-ov-file#initialization');
  }
  const buildContext = new RecastBuildContext();
  const intermediates = {
    type: 'tiled',
    buildContext,
    chunkyTriMesh: undefined,
    tileIntermediates: []
  };
  const navMesh = new NavMesh();
  /* input geometry */
  const vertices = positions;
  const verticesArray = new VerticesArray();
  verticesArray.copy(vertices);
  const triangles = indices;
  const numTriangles = indices.length / 3;
  const trianglesArray = new TrianglesArray();
  trianglesArray.copy(triangles);
  const cleanup = () => {
    verticesArray.destroy();
    trianglesArray.destroy();
    if (keepIntermediates) return;
    if (intermediates.chunkyTriMesh) {
      intermediates.chunkyTriMesh = undefined;
    }
  };
  const fail = error => {
    cleanup();
    navMesh.destroy();
    return {
      success: false,
      navMesh: undefined,
      intermediates,
      error
    };
  };
  //
  // Initialize build config.
  //
  const generatorConfig = {
    ...tiledNavMeshGeneratorConfigDefaults,
    ...navMeshGeneratorConfig
  };
  let bbMin;
  let bbMax;
  if (navMeshGeneratorConfig.bounds) {
    bbMin = navMeshGeneratorConfig.bounds[0];
    bbMax = navMeshGeneratorConfig.bounds[1];
  } else {
    const boundingBox = getBoundingBox(positions, indices);
    bbMin = boundingBox.bbMin;
    bbMax = boundingBox.bbMax;
  }
  const {
    config: rcConfig,
    tileWidth,
    tileHeight,
    tcs,
    orig,
    maxTiles,
    maxPolysPerTile
  } = buildTiledNavMeshRcConfig({
    recastConfig: generatorConfig,
    navMeshBounds: [bbMin, bbMax]
  });
  const navMeshParams = NavMeshParams.create({
    orig,
    tileWidth: generatorConfig.tileSize * generatorConfig.cs,
    tileHeight: generatorConfig.tileSize * generatorConfig.cs,
    maxTiles,
    maxPolys: maxPolysPerTile
  });
  if (!navMesh.initTiled(navMeshParams)) {
    return fail('Could not init nav mesh for tiled use');
  }
  /* create chunky tri mesh */
  const chunkyTriMesh = new RecastChunkyTriMesh();
  intermediates.chunkyTriMesh = chunkyTriMesh;
  if (!chunkyTriMesh.init(verticesArray, trianglesArray, numTriangles, generatorConfig.chunkyTriMeshTrisPerChunk)) {
    return fail('Failed to build chunky triangle mesh');
  }
  buildContext.startTimer(Recast.RC_TIMER_TEMP);
  const lastBuiltTileBmin = [0, 0, 0];
  const lastBuiltTileBmax = [0, 0, 0];
  for (let y = 0; y < tileHeight; y++) {
    for (let x = 0; x < tileWidth; x++) {
      lastBuiltTileBmin[0] = bbMin[0] + x * tcs;
      lastBuiltTileBmin[1] = bbMin[1];
      lastBuiltTileBmin[2] = bbMin[2] + y * tcs;
      lastBuiltTileBmax[0] = bbMin[0] + (x + 1) * tcs;
      lastBuiltTileBmax[1] = bbMax[1];
      lastBuiltTileBmax[2] = bbMin[2] + (y + 1) * tcs;
      const tile = {
        x,
        y,
        bmin: lastBuiltTileBmin,
        bmax: lastBuiltTileBmax
      };
      const generatorOptions = {
        offMeshConnections: generatorConfig.offMeshConnections,
        buildBvTree: generatorConfig.buildBvTree
      };
      const result = generateTileNavMeshData(verticesArray, trianglesArray, rcConfig, chunkyTriMesh, tile, generatorOptions, keepIntermediates, buildContext);
      intermediates.tileIntermediates.push(result.intermediates);
      if (result.success && result.data) {
        navMesh.removeTile(navMesh.getTileRefAt(x, y, 0));
        const addTileResult = navMesh.addTile(result.data, Detour.DT_TILE_FREE_DATA, 0);
        if (statusFailed(addTileResult.status)) {
          buildContext.log(Recast.RC_LOG_WARNING, `Failed to add tile to nav mesh tx: ${x}, ty: ${y}, status: ${statusToReadableString(addTileResult.status)} (${addTileResult.status})`);
          result.data.destroy();
        }
      }
    }
  }
  buildContext.stopTimer(Recast.RC_TIMER_TEMP);
  if (!keepIntermediates) {
    cleanup();
  }
  return {
    success: true,
    navMesh,
    intermediates
  };
};

const mergePositionsAndIndices = meshes => {
  const mergedPositions = [];
  const mergedIndices = [];
  const positionToIndex = {};
  let indexCounter = 0;
  for (const {
    positions,
    indices
  } of meshes) {
    for (let i = 0; i < indices.length; i++) {
      const pt = indices[i] * 3;
      const x = positions[pt];
      const y = positions[pt + 1];
      const z = positions[pt + 2];
      const key = `${x}_${y}_${z}`;
      let idx = positionToIndex[key];
      if (!idx) {
        positionToIndex[key] = idx = indexCounter;
        mergedPositions.push(x, y, z);
        indexCounter++;
      }
      mergedIndices.push(idx);
    }
  }
  return [Float32Array.from(mergedPositions), Uint32Array.from(mergedIndices)];
};

export { buildTiledNavMeshRcConfig, createDefaultTileCacheMeshProcess, dtIlog2, dtNextPow2, generateSoloNavMesh, generateSoloNavMeshData, generateTileCache, generateTileNavMeshData, generateTiledNavMesh, getBoundingBox, mergePositionsAndIndices, soloNavMeshGeneratorConfigDefaults, tileCacheGeneratorConfigDefaults, tiledNavMeshGeneratorConfigDefaults };
