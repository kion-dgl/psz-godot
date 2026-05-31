const instances = ['Recast', 'Detour', 'DetourNavMeshBuilder', 'DetourTileCacheBuilder', 'NavMeshImporter', 'NavMeshExporter', 'CrowdUtils', 'ChunkyTriMeshUtils', 'RecastDebugDraw', 'DetourDebugDraw'];
const classes = ['rcConfig', 'rcContext', 'dtNavMeshParams', 'dtNavMeshCreateParams', 'RecastLinearAllocator', 'RecastFastLZCompressor', 'rcChunkyTriMesh', 'dtTileCacheParams', 'dtTileCacheLayerHeader', 'Vec3', 'BoolRef', 'IntRef', 'UnsignedIntRef', 'UnsignedCharRef', 'UnsignedShortRef', 'FloatRef', 'IntArray', 'UnsignedIntArray', 'UnsignedCharArray', 'UnsignedShortArray', 'FloatArray'];
/**
 * Lower level bindings for the Recast and Detour libraries.
 *
 * The `init` function must be called before using the `Raw` api.
 */
const Raw = {
  isNull: obj => {
    return Raw.Module.getPointer(obj) === 0;
  },
  destroy: obj => {
    Raw.Module.destroy(obj);
  }
};
const Recast = {};
const Detour = {};
const init = async impl => {
  if (Raw.Module !== undefined) {
    return;
  }
  if (impl) {
    Raw.Module = await impl();
  } else {
    const defaultExport = (await import('@recast-navigation/wasm')).default;
    Raw.Module = await defaultExport();
  }
  for (const instance of instances) {
    Raw[instance] = new Raw.Module[instance]();
  }
  for (const clazz of classes) {
    Raw[clazz] = Raw.Module[clazz];
  }
  // recast constants
  Recast.RC_BORDER_REG = Raw.Recast.BORDER_REG;
  Recast.RC_MULTIPLE_REGS = Raw.Recast.MULTIPLE_REGS;
  Recast.RC_BORDER_VERTEX = Raw.Recast.BORDER_VERTEX;
  Recast.RC_AREA_BORDER = Raw.Recast.AREA_BORDER;
  Recast.RC_CONTOUR_REG_MASK = Raw.Recast.CONTOUR_REG_MASK;
  Recast.RC_MESH_NULL_IDX = Raw.Recast.MESH_NULL_IDX;
  Recast.RC_NULL_AREA = Raw.Recast.NULL_AREA;
  Recast.RC_WALKABLE_AREA = Raw.Recast.WALKABLE_AREA;
  Recast.RC_NOT_CONNECTED = Raw.Recast.NOT_CONNECTED;
  // recast enums
  Recast.RC_CONTOUR_TESS_WALL_EDGES = Raw.Module.RC_CONTOUR_TESS_WALL_EDGES;
  Recast.RC_CONTOUR_TESS_AREA_EDGES = Raw.Module.RC_CONTOUR_TESS_AREA_EDGES;
  Recast.RC_LOG_PROGRESS = Raw.Module.RC_LOG_PROGRESS;
  Recast.RC_LOG_WARNING = Raw.Module.RC_LOG_WARNING;
  Recast.RC_LOG_ERROR = Raw.Module.RC_LOG_ERROR;
  Recast.RC_TIMER_TOTAL = Raw.Module.RC_TIMER_TOTAL;
  Recast.RC_TIMER_TEMP = Raw.Module.RC_TIMER_TEMP;
  Recast.RC_TIMER_RASTERIZE_TRIANGLES = Raw.Module.RC_TIMER_RASTERIZE_TRIANGLES;
  Recast.RC_TIMER_BUILD_COMPACTHEIGHTFIELD = Raw.Module.RC_TIMER_BUILD_COMPACTHEIGHTFIELD;
  Recast.RC_TIMER_BUILD_CONTOURS = Raw.Module.RC_TIMER_BUILD_CONTOURS;
  Recast.RC_TIMER_BUILD_CONTOURS_TRACE = Raw.Module.RC_TIMER_BUILD_CONTOURS_TRACE;
  Recast.RC_TIMER_BUILD_CONTOURS_SIMPLIFY = Raw.Module.RC_TIMER_BUILD_CONTOURS_SIMPLIFY;
  Recast.RC_TIMER_FILTER_BORDER = Raw.Module.RC_TIMER_FILTER_BORDER;
  Recast.RC_TIMER_FILTER_WALKABLE = Raw.Module.RC_TIMER_FILTER_WALKABLE;
  Recast.RC_TIMER_MEDIAN_AREA = Raw.Module.RC_TIMER_MEDIAN_AREA;
  Recast.RC_TIMER_FILTER_LOW_OBSTACLES = Raw.Module.RC_TIMER_FILTER_LOW_OBSTACLES;
  Recast.RC_TIMER_BUILD_POLYMESH = Raw.Module.RC_TIMER_BUILD_POLYMESH;
  Recast.RC_TIMER_MERGE_POLYMESH = Raw.Module.RC_TIMER_MERGE_POLYMESH;
  Recast.RC_TIMER_ERODE_AREA = Raw.Module.RC_TIMER_ERODE_AREA;
  Recast.RC_TIMER_MARK_BOX_AREA = Raw.Module.RC_TIMER_MARK_BOX_AREA;
  Recast.RC_TIMER_MARK_CYLINDER_AREA = Raw.Module.RC_TIMER_MARK_CYLINDER_AREA;
  Recast.RC_TIMER_MARK_CONVEXPOLY_AREA = Raw.Module.RC_TIMER_MARK_CONVEXPOLY_AREA;
  Recast.RC_TIMER_BUILD_DISTANCEFIELD = Raw.Module.RC_TIMER_BUILD_DISTANCEFIELD;
  Recast.RC_TIMER_BUILD_DISTANCEFIELD_DIST = Raw.Module.RC_TIMER_BUILD_DISTANCEFIELD_DIST;
  Recast.RC_TIMER_BUILD_DISTANCEFIELD_BLUR = Raw.Module.RC_TIMER_BUILD_DISTANCEFIELD_BLUR;
  Recast.RC_TIMER_BUILD_REGIONS = Raw.Module.RC_TIMER_BUILD_REGIONS;
  Recast.RC_TIMER_BUILD_REGIONS_WATERSHED = Raw.Module.RC_TIMER_BUILD_REGIONS_WATERSHED;
  Recast.RC_TIMER_BUILD_REGIONS_EXPAND = Raw.Module.RC_TIMER_BUILD_REGIONS_EXPAND;
  Recast.RC_TIMER_BUILD_REGIONS_FLOOD = Raw.Module.RC_TIMER_BUILD_REGIONS_FLOOD;
  Recast.RC_TIMER_BUILD_REGIONS_FILTER = Raw.Module.RC_TIMER_BUILD_REGIONS_FILTER;
  Recast.RC_TIMER_BUILD_LAYERS = Raw.Module.RC_TIMER_BUILD_LAYERS;
  Recast.RC_TIMER_BUILD_POLYMESHDETAIL = Raw.Module.RC_TIMER_BUILD_POLYMESHDETAIL;
  Recast.RC_TIMER_MERGE_POLYMESHDETAIL = Raw.Module.RC_TIMER_MERGE_POLYMESHDETAIL;
  Recast.RC_MAX_TIMERS = Raw.Module.RC_MAX_TIMERS;
  // detour constants
  Detour.DT_FAILURE = Raw.Detour.FAILURE;
  Detour.DT_SUCCESS = Raw.Detour.SUCCESS;
  Detour.DT_IN_PROGRESS = Raw.Detour.IN_PROGRESS;
  Detour.DT_STATUS_DETAIL_MASK = Raw.Detour.STATUS_DETAIL_MASK;
  Detour.DT_WRONG_MAGIC = Raw.Detour.WRONG_MAGIC;
  Detour.DT_WRONG_VERSION = Raw.Detour.WRONG_VERSION;
  Detour.DT_OUT_OF_MEMORY = Raw.Detour.OUT_OF_MEMORY;
  Detour.DT_INVALID_PARAM = Raw.Detour.INVALID_PARAM;
  Detour.DT_BUFFER_TOO_SMALL = Raw.Detour.BUFFER_TOO_SMALL;
  Detour.DT_OUT_OF_NODES = Raw.Detour.OUT_OF_NODES;
  Detour.DT_PARTIAL_RESULT = Raw.Detour.PARTIAL_RESULT;
  Detour.DT_ALREADY_OCCUPIED = Raw.Detour.ALREADY_OCCUPIED;
  Detour.DT_VERTS_PER_POLYGON = Raw.Detour.VERTS_PER_POLYGON;
  Detour.DT_NAVMESH_MAGIC = Raw.Detour.NAVMESH_MAGIC;
  Detour.DT_NAVMESH_VERSION = Raw.Detour.NAVMESH_VERSION;
  Detour.DT_NAVMESH_STATE_MAGIC = Raw.Detour.NAVMESH_STATE_MAGIC;
  Detour.DT_NAVMESH_STATE_VERSION = Raw.Detour.NAVMESH_STATE_VERSION;
  Detour.DT_TILECACHE_MAGIC = Raw.Detour.TILECACHE_MAGIC;
  Detour.DT_TILECACHE_VERSION = Raw.Detour.TILECACHE_VERSION;
  Detour.DT_TILECACHE_NULL_AREA = Raw.Detour.TILECACHE_NULL_AREA;
  Detour.DT_TILECACHE_WALKABLE_AREA = Raw.Detour.TILECACHE_WALKABLE_AREA;
  Detour.DT_TILECACHE_NULL_IDX = Raw.Detour.TILECACHE_NULL_IDX;
  Detour.DT_NULL_LINK = Raw.Detour.NULL_LINK;
  Detour.DT_NULL_LINK = Raw.Detour.NULL_LINK;
  Detour.DT_EXT_LINK = Raw.Detour.EXT_LINK;
  Detour.DT_OFFMESH_CON_BIDIR = Raw.Detour.OFFMESH_CON_BIDIR;
  // detour enums
  Detour.DT_STRAIGHTPATH_START = Raw.Module.DT_STRAIGHTPATH_START;
  Detour.DT_STRAIGHTPATH_END = Raw.Module.DT_STRAIGHTPATH_END;
  Detour.DT_STRAIGHTPATH_OFFMESH_CONNECTION = Raw.Module.DT_STRAIGHTPATH_OFFMESH_CONNECTION;
  Detour.DT_STRAIGHTPATH_AREA_CROSSINGS = Raw.Module.DT_STRAIGHTPATH_AREA_CROSSINGS;
  Detour.DT_STRAIGHTPATH_ALL_CROSSINGS = Raw.Module.DT_STRAIGHTPATH_ALL_CROSSINGS;
  Detour.DT_FINDPATH_ANY_ANGLE = Raw.Module.DT_FINDPATH_ANY_ANGLE;
  Detour.DT_RAYCAST_USE_COSTS = Raw.Module.DT_RAYCAST_USE_COSTS;
  Detour.DT_CROWDAGENT_STATE_INVALID = Raw.Module.DT_CROWDAGENT_STATE_INVALID;
  Detour.DT_CROWDAGENT_STATE_WALKING = Raw.Module.DT_CROWDAGENT_STATE_WALKING;
  Detour.DT_CROWDAGENT_STATE_OFFMESH = Raw.Module.DT_CROWDAGENT_STATE_OFFMESH;
  Detour.DT_CROWDAGENT_TARGET_NONE = Raw.Module.DT_CROWDAGENT_TARGET_NONE;
  Detour.DT_CROWDAGENT_TARGET_FAILED = Raw.Module.DT_CROWDAGENT_TARGET_FAILED;
  Detour.DT_CROWDAGENT_TARGET_VALID = Raw.Module.DT_CROWDAGENT_TARGET_VALID;
  Detour.DT_CROWDAGENT_TARGET_REQUESTING = Raw.Module.DT_CROWDAGENT_TARGET_REQUESTING;
  Detour.DT_CROWDAGENT_TARGET_WAITING_FOR_QUEUE = Raw.Module.DT_CROWDAGENT_TARGET_WAITING_FOR_QUEUE;
  Detour.DT_CROWDAGENT_TARGET_WAITING_FOR_PATH = Raw.Module.DT_CROWDAGENT_TARGET_WAITING_FOR_PATH;
  Detour.DT_CROWDAGENT_TARGET_VELOCITY = Raw.Module.DT_CROWDAGENT_TARGET_VELOCITY;
  Detour.DT_COMPRESSEDTILE_FREE_DATA = Raw.Module.DT_COMPRESSEDTILE_FREE_DATA;
  Detour.DT_TILE_FREE_DATA = Raw.Module.DT_TILE_FREE_DATA;
};

class BaseArray {
  get size() {
    return this.raw.size;
  }
  constructor(raw) {
    this.raw = raw;
  }
  get(i) {
    return this.raw.get(i);
  }
  set(i, value) {
    this.raw.set(i, value);
  }
  resize(size) {
    this.raw.resize(size);
  }
  copy(data) {
    this.raw.resize(data.length);
    const view = this.getHeapView();
    view.set(data);
  }
  destroy() {
    Raw.destroy(this.raw);
  }
  getHeapView() {
    const heap = this.getHeap();
    return new this.ArrayConstructor(heap.buffer, this.raw.getDataPointer(), this.size);
  }
  toTypedArray() {
    const view = this.getHeapView();
    const data = new this.ArrayConstructor(new ArrayBuffer(this.size * view.BYTES_PER_ELEMENT), 0, this.size);
    data.set(view);
    return data;
  }
}
class IntArray extends BaseArray {
  ArrayConstructor = Int32Array;
  constructor(raw) {
    super(raw ?? new Raw.Module.IntArray());
  }
  getHeap() {
    return Raw.Module.HEAP32;
  }
  static fromRaw(raw) {
    return new IntArray(raw);
  }
}
class UnsignedIntArray extends BaseArray {
  ArrayConstructor = Uint32Array;
  constructor(raw) {
    super(raw ?? new Raw.Module.UnsignedIntArray());
  }
  getHeap() {
    return Raw.Module.HEAPU32;
  }
  static fromRaw(raw) {
    return new UnsignedIntArray(raw);
  }
}
class UnsignedCharArray extends BaseArray {
  ArrayConstructor = Uint8Array;
  constructor(raw) {
    super(raw ?? new Raw.Module.UnsignedCharArray());
  }
  getHeap() {
    return Raw.Module.HEAPU8;
  }
  static fromRaw(raw) {
    return new UnsignedCharArray(raw);
  }
}
class UnsignedShortArray extends BaseArray {
  ArrayConstructor = Uint16Array;
  constructor(raw) {
    super(raw ?? new Raw.Module.UnsignedShortArray());
  }
  getHeap() {
    return Raw.Module.HEAPU16;
  }
  static fromRaw(raw) {
    return new UnsignedShortArray(raw);
  }
}
class FloatArray extends BaseArray {
  ArrayConstructor = Float32Array;
  constructor(raw) {
    super(raw ?? new Raw.Module.FloatArray());
  }
  getHeap() {
    return Raw.Module.HEAPF32;
  }
  static fromRaw(raw) {
    return new FloatArray(raw);
  }
}
const VerticesArray = FloatArray;
const TrianglesArray = IntArray;
const TriangleAreasArray = UnsignedCharArray;
const ChunkIdsArray = IntArray;
const TileCacheData = UnsignedCharArray;

const vec3 = {
  toRaw: ({
    x,
    y,
    z
  }, existing) => {
    if (existing) {
      existing.x = x;
      existing.y = y;
      existing.z = z;
      return existing;
    }
    return new Raw.Module.Vec3(x, y, z);
  },
  fromRaw: vec3 => {
    const {
      x,
      y,
      z
    } = vec3;
    return {
      x,
      y,
      z
    };
  },
  fromArray: ([x, y, z]) => {
    return {
      x,
      y,
      z
    };
  },
  toArray: ({
    x,
    y,
    z
  }) => {
    return [x, y, z];
  },
  lerp: (a, b, t, out = {
    x: 0,
    y: 0,
    z: 0
  }) => {
    out.x = a.x + (b.x - a.x) * t;
    out.y = a.y + (b.y - a.y) * t;
    out.z = a.z + (b.z - a.z) * t;
  },
  copy: (source, out = {
    x: 0,
    y: 0,
    z: 0
  }) => {
    out.x = source.x;
    out.y = source.y;
    out.z = source.z;
  }
};
const array = (getter, count) => {
  const array = [];
  for (let i = 0; i < count; i++) {
    array.push(getter(i));
  }
  return array;
};

const statusSucceed = status => {
  return Raw.Detour.statusSucceed(status);
};
const statusFailed = status => {
  return Raw.Detour.statusFailed(status);
};
const statusInProgress = status => {
  return Raw.Detour.statusInProgress(status);
};
const statusDetail = (status, detail) => {
  return Raw.Detour.statusDetail(status, detail);
};
const statusToReadableString = status => {
  if (Raw.Detour.statusSucceed(status)) {
    return 'success';
  }
  if (Raw.Detour.statusInProgress(status)) {
    return 'in progress';
  }
  if (Raw.Detour.statusFailed(status)) {
    let reason;
    const DT_STATUS_REASONS = {
      DT_WRONG_MAGIC: Detour.DT_WRONG_MAGIC,
      DT_WRONG_VERSION: Detour.DT_WRONG_VERSION,
      DT_OUT_OF_MEMORY: Detour.DT_OUT_OF_MEMORY,
      DT_INVALID_PARAM: Detour.DT_INVALID_PARAM,
      DT_BUFFER_TOO_SMALL: Detour.DT_BUFFER_TOO_SMALL,
      DT_OUT_OF_NODES: Detour.DT_OUT_OF_NODES,
      DT_PARTIAL_RESULT: Detour.DT_PARTIAL_RESULT,
      DT_ALREADY_OCCUPIED: Detour.DT_ALREADY_OCCUPIED
    };
    for (const [reasonName, reasonMask] of Object.entries(DT_STATUS_REASONS)) {
      if (Raw.Detour.statusDetail(status, reasonMask)) {
        reason = reasonName;
        break;
      }
    }
    if (reason) {
      return `failed - ${reason}`;
    }
    return `failed - unknown`;
  }
  return 'unknown';
};
class DetourPolyDetail {
  constructor(raw) {
    this.raw = raw;
  }
  vertBase() {
    return this.raw.vertBase;
  }
  triBase() {
    return this.raw.triBase;
  }
  vertCount() {
    return this.raw.vertCount;
  }
  triCount() {
    return this.raw.triCount;
  }
}
class DetourLink {
  constructor(raw) {
    this.raw = raw;
  }
  ref() {
    return this.raw.ref;
  }
  next() {
    return this.raw.next;
  }
  edge() {
    return this.raw.edge;
  }
  side() {
    return this.raw.side;
  }
  bmin() {
    return this.raw.bmin;
  }
  bmax() {
    return this.raw.bmax;
  }
}
class DetourBVNode {
  constructor(raw) {
    this.raw = raw;
  }
  bmin() {
    return vec3.fromArray(array(i => this.raw.get_bmin(i), 3));
  }
  bmax() {
    return vec3.fromArray(array(i => this.raw.get_bmax(i), 3));
  }
  i() {
    return this.raw.i;
  }
}
class DetourOffMeshConnection {
  constructor(raw) {
    this.raw = raw;
  }
  pos(index) {
    return this.raw.get_pos(index);
  }
  rad() {
    return this.raw.rad;
  }
  poly() {
    return this.raw.poly;
  }
  flags() {
    return this.raw.flags;
  }
  side() {
    return this.raw.side;
  }
  userId() {
    return this.raw.userId;
  }
}
class DetourMeshHeader {
  constructor(raw) {
    this.raw = raw;
  }
  magic() {
    return this.raw.magic;
  }
  version() {
    return this.raw.version;
  }
  x() {
    return this.raw.x;
  }
  y() {
    return this.raw.y;
  }
  layer() {
    return this.raw.layer;
  }
  userId() {
    return this.raw.userId;
  }
  polyCount() {
    return this.raw.polyCount;
  }
  vertCount() {
    return this.raw.vertCount;
  }
  maxLinkCount() {
    return this.raw.maxLinkCount;
  }
  detailMeshCount() {
    return this.raw.detailMeshCount;
  }
  detailVertCount() {
    return this.raw.detailVertCount;
  }
  detailTriCount() {
    return this.raw.detailTriCount;
  }
  bvNodeCount() {
    return this.raw.bvNodeCount;
  }
  offMeshConCount() {
    return this.raw.offMeshConCount;
  }
  offMeshBase() {
    return this.raw.offMeshBase;
  }
  walkableHeight() {
    return this.raw.walkableHeight;
  }
  walkableRadius() {
    return this.raw.walkableRadius;
  }
  walkableClimb() {
    return this.raw.walkableClimb;
  }
  bmin(index) {
    return this.raw.get_bmin(index);
  }
  bmax(index) {
    return this.raw.get_bmax(index);
  }
  bvQuantFactor() {
    return this.raw.bvQuantFactor;
  }
}
class DetourPoly {
  constructor(raw) {
    this.raw = raw;
  }
  firstLink() {
    return this.raw.firstLink;
  }
  verts(index) {
    return this.raw.get_verts(index);
  }
  neis(index) {
    return this.raw.get_neis(index);
  }
  flags() {
    return this.raw.flags;
  }
  vertCount() {
    return this.raw.vertCount;
  }
  areaAndType() {
    return this.raw.get_areaAndtype();
  }
  getType() {
    return this.raw.getType();
  }
}
class DetourMeshTile {
  constructor(raw) {
    this.raw = raw;
  }
  salt() {
    return this.raw.salt;
  }
  linksFreeList() {
    return this.raw.linksFreeList;
  }
  header() {
    return !Raw.isNull(this.raw.header) ? new DetourMeshHeader(this.raw.header) : null;
  }
  polys(index) {
    return new DetourPoly(this.raw.get_polys(index));
  }
  verts(index) {
    return this.raw.get_verts(index);
  }
  links(index) {
    return new DetourLink(this.raw.get_links(index));
  }
  detailMeshes(index) {
    return new DetourPolyDetail(this.raw.get_detailMeshes(index));
  }
  detailVerts(index) {
    return this.raw.get_detailVerts(index);
  }
  detailTris(index) {
    return this.raw.get_detailTris(index);
  }
  bvTree(index) {
    return new DetourBVNode(this.raw.get_bvTree(index));
  }
  offMeshCons(index) {
    return new DetourOffMeshConnection(this.raw.get_offMeshCons(index));
  }
  data(index) {
    return this.raw.get_data(index);
  }
  dataSize() {
    return this.raw.dataSize;
  }
  flags() {
    return this.raw.flags;
  }
  next() {
    return new DetourMeshTile(this.raw.next);
  }
}
const createNavMeshData = navMeshCreateParams => {
  const result = Raw.DetourNavMeshBuilder.createNavMeshData(navMeshCreateParams.raw);
  return {
    success: result.success,
    navMeshData: UnsignedCharArray.fromRaw(result.navMeshData)
  };
};
class NavMeshCreateParams {
  constructor(raw) {
    this.raw = raw ?? new Raw.Module.dtNavMeshCreateParams();
  }
  setPolyMeshCreateParams(polyMesh) {
    Raw.DetourNavMeshBuilder.setPolyMeshCreateParams(this.raw, polyMesh.raw);
  }
  setPolyMeshDetailCreateParams(polyMeshDetail) {
    Raw.DetourNavMeshBuilder.setPolyMeshDetailCreateParams(this.raw, polyMeshDetail.raw);
  }
  setOffMeshConnections(offMeshConnections) {
    if (offMeshConnections.length <= 0) return;
    const verts = [];
    const rads = [];
    const dir = [];
    const areas = [];
    const flags = [];
    const userIds = [];
    for (let i = 0; i < offMeshConnections.length; i++) {
      const connection = offMeshConnections[i];
      verts.push(connection.startPosition.x, connection.startPosition.y, connection.startPosition.z);
      verts.push(connection.endPosition.x, connection.endPosition.y, connection.endPosition.z);
      rads.push(connection.radius);
      dir.push(connection.bidirectional ? 1 : 0);
      areas.push(connection.area ?? 0);
      flags.push(connection.flags ?? 1);
      userIds.push(connection.userId ?? 1000 + i);
    }
    Raw.DetourNavMeshBuilder.setOffMeshConnections(this.raw, offMeshConnections.length, verts, rads, dir, areas, flags, userIds);
  }
  verts(index) {
    return this.raw.get_verts(index);
  }
  setVerts(index, value) {
    this.raw.set_verts(index, value);
  }
  vertCount() {
    return this.raw.vertCount;
  }
  polys(index) {
    return this.raw.get_polys(index);
  }
  setPolys(index, value) {
    this.raw.set_polys(index, value);
  }
  polyAreas(index) {
    return this.raw.get_polyAreas(index);
  }
  setPolyAreas(index, value) {
    this.raw.set_polyAreas(index, value);
  }
  polyFlags(index) {
    return this.raw.get_polyFlags(index);
  }
  setPolyFlags(index, value) {
    this.raw.set_polyFlags(index, value);
  }
  polyCount() {
    return this.raw.polyCount;
  }
  nvp() {
    return this.raw.nvp;
  }
  setNvp(value) {
    this.raw.nvp = value;
  }
  detailMeshes(index) {
    return this.raw.get_detailMeshes(index);
  }
  setDetailMeshes(index, value) {
    this.raw.set_detailMeshes(index, value);
  }
  detailVerts(index) {
    return this.raw.get_detailVerts(index);
  }
  setDetailVerts(index, value) {
    this.raw.set_detailVerts(index, value);
  }
  detailVertsCount() {
    return this.raw.detailVertsCount;
  }
  detailTris(index) {
    return this.raw.get_detailTris(index);
  }
  setDetailTris(index, value) {
    this.raw.set_detailTris(index, value);
  }
  detailTriCount() {
    return this.raw.detailTriCount;
  }
  offMeshConVerts(index) {
    return this.raw.get_offMeshConVerts(index);
  }
  offMeshConRad(index) {
    return this.raw.get_offMeshConRad(index);
  }
  offMeshConDir(index) {
    return this.raw.get_offMeshConDir(index);
  }
  offMeshConAreas(index) {
    return this.raw.get_offMeshConAreas(index);
  }
  offMeshConFlags(index) {
    return this.raw.get_offMeshConFlags(index);
  }
  offMeshConUserID(index) {
    return this.raw.get_offMeshConUserID(index);
  }
  offMeshConCount() {
    return this.raw.offMeshConCount;
  }
  userId() {
    return this.raw.userId;
  }
  tileX() {
    return this.raw.tileX;
  }
  setTileX(value) {
    this.raw.tileX = value;
  }
  tileY() {
    return this.raw.tileY;
  }
  setTileY(value) {
    this.raw.tileY = value;
  }
  tileLayer() {
    return this.raw.tileLayer;
  }
  setTileLayer(value) {
    this.raw.tileLayer = value;
  }
  boundsMin() {
    return array(i => this.raw.get_bmin(i), 3);
  }
  setBoundsMin(value) {
    this.raw.set_bmin(0, value[0]);
    this.raw.set_bmin(1, value[1]);
    this.raw.set_bmin(2, value[2]);
  }
  boundsMax() {
    return array(i => this.raw.get_bmax(i), 3);
  }
  setBoundsMax(value) {
    this.raw.set_bmax(0, value[0]);
    this.raw.set_bmax(1, value[1]);
    this.raw.set_bmax(2, value[2]);
  }
  walkableHeight() {
    return this.raw.walkableHeight;
  }
  setWalkableHeight(value) {
    this.raw.walkableHeight = value;
  }
  walkableRadius() {
    return this.raw.walkableRadius;
  }
  setWalkableRadius(value) {
    this.raw.walkableRadius = value;
  }
  walkableClimb() {
    return this.raw.walkableClimb;
  }
  setWalkableClimb(value) {
    this.raw.walkableClimb = value;
  }
  cellSize() {
    return this.raw.cs;
  }
  setCellSize(value) {
    this.raw.cs = value;
  }
  cellHeight() {
    return this.raw.ch;
  }
  setCellHeight(value) {
    this.raw.ch = value;
  }
  buildBvTree() {
    return this.raw.buildBvTree;
  }
  setBuildBvTree(value) {
    this.raw.buildBvTree = value;
  }
}

class QueryFilter {
  get includeFlags() {
    return this.raw.getIncludeFlags();
  }
  set includeFlags(flags) {
    this.raw.setIncludeFlags(flags);
  }
  get excludeFlags() {
    return this.raw.getExcludeFlags();
  }
  set excludeFlags(flags) {
    this.raw.setExcludeFlags(flags);
  }
  constructor(raw) {
    this.raw = raw ?? new Raw.Module.dtQueryFilter();
  }
  getAreaCost(i) {
    return this.raw.getAreaCost(i);
  }
  setAreaCost(i, cost) {
    this.raw.setAreaCost(i, cost);
  }
}
class NavMeshQuery {
  /**
   * Default query filter.
   */

  /**
   * Default search distance along each axis.
   */
  defaultQueryHalfExtents = {
    x: 1,
    y: 1,
    z: 1
  };
  constructor(value, params) {
    if (value instanceof Raw.Module.NavMeshQuery) {
      this.raw = value;
    } else {
      this.raw = new Raw.Module.NavMeshQuery();
      this.raw.init(value.raw, params?.maxNodes ?? 2048);
    }
    if (params?.defaultQueryFilter) {
      this.defaultFilter = params.defaultQueryFilter;
    } else {
      this.defaultFilter = new QueryFilter();
      this.defaultFilter.includeFlags = 0xffff;
      this.defaultFilter.excludeFlags = 0;
    }
  }
  /**
   * Finds the polygon nearest to the given position.
   */
  findNearestPoly(position, options) {
    const nearestRefRaw = new Raw.UnsignedIntRef();
    const nearestPointRaw = new Raw.Vec3();
    const isOverPolyRaw = new Raw.BoolRef();
    const status = this.raw.findNearestPoly(vec3.toArray(position), vec3.toArray(options?.halfExtents ?? this.defaultQueryHalfExtents), options?.filter?.raw ?? this.defaultFilter.raw, nearestRefRaw, nearestPointRaw, isOverPolyRaw);
    const nearestPoint = vec3.fromRaw(nearestPointRaw);
    Raw.destroy(nearestPointRaw);
    const nearestRef = nearestRefRaw.value;
    Raw.destroy(nearestRefRaw);
    const isOverPoly = isOverPolyRaw.value;
    Raw.destroy(isOverPolyRaw);
    return {
      success: statusSucceed(status),
      status,
      nearestRef,
      nearestPoint,
      isOverPoly
    };
  }
  /**
   * Finds the polygons along the navigation graph that touch the specified circle.
   * @param startRef Reference of polygon to start search from
   * @param centerPos Center of circle
   * @param radius Radius of circle
   * @param options
   */
  findPolysAroundCircle(startRef, centerPos, radius, options) {
    const filter = options?.filter ?? this.defaultFilter;
    const maxPolys = options?.maxPolys ?? 256;
    const resultRefArray = new UnsignedIntArray();
    const resultParentArray = new UnsignedIntArray();
    const resultCostArray = new FloatArray();
    resultRefArray.resize(maxPolys);
    resultParentArray.resize(maxPolys);
    resultCostArray.resize(maxPolys);
    const resultCountRef = new Raw.IntRef();
    const status = this.raw.findPolysAroundCircle(startRef, vec3.toArray(centerPos), radius, filter.raw, resultRefArray.raw, resultParentArray.raw, resultCostArray.raw, resultCountRef, maxPolys);
    const resultRefs = [...resultRefArray.getHeapView()];
    resultRefArray.destroy();
    const resultParents = [...resultParentArray.getHeapView()];
    resultParentArray.destroy();
    const resultCost = [...resultCostArray.getHeapView()];
    resultCostArray.destroy();
    const resultCount = resultCountRef.value;
    Raw.destroy(resultCountRef);
    // todo: freeing resultCostRef and resultCountRef intermittently throws
    // memory related errors.
    // const resultCost = resultCostRef.value;
    // const resultCount = resultCountRef.value;
    return {
      success: statusSucceed(status),
      status,
      resultRefs,
      resultParents,
      resultCost,
      resultCount
    };
  }
  /**
   * Finds polygons that overlap the search box.
   * @param center The center of the search box
   * @param halfExtents The search distance along each axis
   * @param options
   */
  queryPolygons(center, halfExtents, options) {
    const filter = options?.filter ?? this.defaultFilter;
    const maxPolys = options?.maxPolys ?? 256;
    const polysRefsArray = new UnsignedIntArray();
    polysRefsArray.resize(maxPolys);
    const polyCountRef = new Raw.IntRef();
    const status = this.raw.queryPolygons(vec3.toArray(center), vec3.toArray(halfExtents), filter.raw, polysRefsArray.raw, polyCountRef, maxPolys);
    const polyCount = polyCountRef.value;
    Raw.destroy(polyCountRef);
    const polyRefs = [...polysRefsArray.getHeapView()].slice(0, polyCount);
    polysRefsArray.destroy();
    return {
      success: statusSucceed(status),
      status,
      polyRefs
    };
  }
  /**
   * Returns the closest point on the given polygon to the given position.
   *
   * @param polyRef The reference of the polygon
   * @param position The position to find the closest point to
   */
  closestPointOnPoly(polyRef, position) {
    const closestPointRaw = new Raw.Vec3();
    const positionOverPolyRaw = new Raw.BoolRef();
    const status = this.raw.closestPointOnPoly(polyRef, vec3.toArray(position), closestPointRaw, positionOverPolyRaw);
    const closestPoint = vec3.fromRaw(closestPointRaw);
    Raw.destroy(closestPointRaw);
    const isPointOverPoly = positionOverPolyRaw.value;
    Raw.destroy(positionOverPolyRaw);
    return {
      success: statusSucceed(status),
      status,
      closestPoint,
      isPointOverPoly
    };
  }
  /**
   * Finds the closest point on the NavMesh to the given position.
   * @param position the position to find the closest point to
   * @param options additional options
   * @returns the result of the find closest point operation
   */
  findClosestPoint(position, options) {
    const filter = options?.filter ?? this.defaultFilter;
    const halfExtents = options?.halfExtents ?? this.defaultQueryHalfExtents;
    const resultPolyRef = new Raw.UnsignedIntRef();
    const resultPoint = new Raw.Vec3();
    const resultPointOverPoly = new Raw.BoolRef();
    const status = this.raw.findClosestPoint(vec3.toArray(position), vec3.toArray(halfExtents), filter.raw, resultPolyRef, resultPoint, resultPointOverPoly);
    const polyRef = resultPolyRef.value;
    Raw.destroy(resultPolyRef);
    const point = vec3.fromRaw(resultPoint);
    Raw.destroy(resultPoint);
    const isPointOverPoly = resultPointOverPoly.value;
    Raw.destroy(resultPointOverPoly);
    return {
      success: statusSucceed(status),
      status,
      polyRef,
      point,
      isPointOverPoly
    };
  }
  /**
   * Returns a random point on the NavMesh within the given radius of the given position.
   *
   * @param position the center of the search circle
   * @param radius the radius of the search circle
   * @param options additional options
   */
  findRandomPointAroundCircle(position, radius, options) {
    const filter = options?.filter ?? this.defaultFilter;
    const halfExtents = options?.halfExtents ?? this.defaultQueryHalfExtents;
    let startRef;
    if (options?.startRef) {
      startRef = options.startRef;
    } else {
      const nearestPoly = this.findNearestPoly(position, {
        filter,
        halfExtents
      });
      if (!nearestPoly.success) {
        return {
          success: false,
          status: nearestPoly.status,
          randomPolyRef: 0,
          randomPoint: {
            x: 0,
            y: 0,
            z: 0
          }
        };
      }
      startRef = nearestPoly.nearestRef;
    }
    const randomPolyRefRaw = new Raw.UnsignedIntRef();
    const randomPointRaw = new Raw.Vec3();
    const status = this.raw.findRandomPointAroundCircle(startRef, vec3.toArray(position), radius, filter.raw, randomPolyRefRaw, randomPointRaw);
    const randomPolyRef = randomPolyRefRaw.value;
    Raw.destroy(randomPolyRefRaw);
    const randomPoint = vec3.fromRaw(randomPointRaw);
    Raw.destroy(randomPointRaw);
    return {
      success: statusSucceed(status),
      status,
      randomPolyRef,
      randomPoint
    };
  }
  /**
   * Moves from the start to the end position constrained to the navigation mesh.
   *
   * @param startRef the reference id of the start polygon.
   * @param startPosition a position of the mover within the start polygon.
   * @param endPosition the desired end position of the mover.
   *
   * @returns The result of the move along surface operation.
   */
  moveAlongSurface(startRef, startPosition, endPosition, options) {
    const maxVisitedSize = options?.maxVisitedSize ?? 256;
    const resultPositionRaw = new Raw.Vec3();
    const visitedArray = new UnsignedIntArray();
    const filter = options?.filter?.raw ?? this.defaultFilter.raw;
    const status = this.raw.moveAlongSurface(startRef, vec3.toArray(startPosition), vec3.toArray(endPosition), filter, resultPositionRaw, visitedArray.raw, maxVisitedSize);
    const resultPosition = vec3.fromRaw(resultPositionRaw);
    Raw.destroy(resultPositionRaw);
    const visited = [...visitedArray.getHeapView()];
    visitedArray.destroy();
    return {
      success: statusSucceed(status),
      status,
      resultPosition,
      visited
    };
  }
  /**
   * Returns a random point on the navmesh.
   * @param options additional options
   * @returns a random point on the navmesh
   */
  findRandomPoint(options) {
    const randomPolyRefRaw = new Raw.UnsignedIntRef();
    const randomPointRaw = new Raw.Vec3();
    const status = this.raw.findRandomPoint(options?.filter?.raw ?? this.defaultFilter.raw, randomPolyRefRaw, randomPointRaw);
    const randomPolyRef = randomPolyRefRaw.value;
    Raw.destroy(randomPolyRefRaw);
    const randomPoint = vec3.fromRaw(randomPointRaw);
    Raw.destroy(randomPointRaw);
    return {
      success: statusSucceed(status),
      status,
      randomPolyRef,
      randomPoint
    };
  }
  /**
   * Gets the height of the polygon at the provided position using the height detail.
   *
   * @param polyRef the reference id of the polygon.
   * @param position a position within the xz-bounds of the polygon.
   */
  getPolyHeight(polyRef, position) {
    const floatRef = new Raw.FloatRef();
    const status = this.raw.getPolyHeight(polyRef, vec3.toArray(position), floatRef);
    const height = floatRef.value;
    Raw.destroy(floatRef);
    return {
      success: statusSucceed(status),
      status,
      height
    };
  }
  /**
   * Finds a straight path from the start position to the end position.
   *
   * @param start the start position
   * @param end the end position
   * @param options additional options
   *
   * @returns an array of Vector3 positions that make up the path, or an empty array if no path was found.
   */
  computePath(start, end, options) {
    const filter = options?.filter ?? this.defaultFilter;
    const halfExtents = options?.halfExtents ?? this.defaultQueryHalfExtents;
    // find nearest polygons for start and end positions
    const startNearestPolyResult = this.findNearestPoly(start, {
      filter,
      halfExtents
    });
    if (!startNearestPolyResult.success) {
      return {
        success: false,
        error: {
          name: 'findNearestPoly for start position failed',
          status: startNearestPolyResult.status
        },
        path: []
      };
    }
    const endNearestPolyResult = this.findNearestPoly(end, {
      filter,
      halfExtents
    });
    if (!endNearestPolyResult.success) {
      return {
        success: false,
        error: {
          name: 'findNearestPoly for end position failed',
          status: endNearestPolyResult.status
        },
        path: []
      };
    }
    const startRef = startNearestPolyResult.nearestRef;
    const endRef = endNearestPolyResult.nearestRef;
    // find polygon path
    const maxPathPolys = options?.maxPathPolys ?? 256;
    const findPathResult = this.findPath(startRef, endRef, start, end, {
      filter,
      maxPathPolys
    });
    if (!findPathResult.success) {
      return {
        success: false,
        error: {
          name: 'findPath unsuccessful',
          status: findPathResult.status
        },
        path: []
      };
    }
    if (findPathResult.polys.size <= 0) {
      return {
        success: false,
        error: {
          name: 'no polygon path found'
        },
        path: []
      };
    }
    const lastPoly = findPathResult.polys.get(findPathResult.polys.size - 1);
    let closestEnd = {
      x: end.x,
      y: end.y,
      z: end.z
    };
    if (lastPoly !== endRef) {
      const lastPolyClosestPointResult = this.closestPointOnPoly(lastPoly, end);
      if (!lastPolyClosestPointResult.success) {
        return {
          success: false,
          error: {
            name: 'no closest point on last polygon found',
            status: lastPolyClosestPointResult.status
          },
          path: []
        };
      }
      closestEnd = lastPolyClosestPointResult.closestPoint;
    }
    // find straight path
    const maxStraightPathPoints = options?.maxStraightPathPoints;
    const findStraightPathResult = this.findStraightPath(start, closestEnd, findPathResult.polys, {
      maxStraightPathPoints
    });
    if (!findStraightPathResult.success) {
      return {
        success: false,
        error: {
          name: 'findStraightPath unsuccessful',
          status: findStraightPathResult.status
        },
        path: []
      };
    }
    const {
      straightPath,
      straightPathCount
    } = findStraightPathResult;
    // format output
    const points = [];
    for (let i = 0; i < straightPathCount; i++) {
      points.push({
        x: straightPath.get(i * 3),
        y: straightPath.get(i * 3 + 1),
        z: straightPath.get(i * 3 + 2)
      });
    }
    findPathResult.polys.destroy();
    findStraightPathResult.straightPath.destroy();
    findStraightPathResult.straightPathFlags.destroy();
    findStraightPathResult.straightPathRefs.destroy();
    return {
      success: true,
      path: points
    };
  }
  /**
   * Finds a path from the start polygon to the end polygon.
   * @param startRef the reference id of the start polygon.
   * @param endRef the reference id of the end polygon.
   * @param startPosition position within the start polygon.
   * @param endPosition position within the end polygon.
   * @param options additional options
   * @returns
   *
   * The `polys` array returned must be freed after use.
   *
   * ```ts
   * findPathResult.polys.destroy();
   * ```
   */
  findPath(startRef, endRef, startPosition, endPosition, options) {
    const filter = options?.filter ?? this.defaultFilter;
    const maxPathPolys = options?.maxPathPolys ?? 256;
    const polysArray = new UnsignedIntArray();
    polysArray.resize(maxPathPolys);
    const status = this.raw.findPath(startRef, endRef, vec3.toArray(startPosition), vec3.toArray(endPosition), filter.raw, polysArray.raw, maxPathPolys);
    return {
      success: statusSucceed(status),
      status,
      polys: polysArray
    };
  }
  /**
   * Finds the straight path from the start to the end position within the polygon corridor.
   *
   * This method peforms what is often called 'string pulling'.
   *
   * The start position is clamped to the first polygon in the path, and the
   * end position is clamped to the last. So the start and end positions should
   * normally be within or very near the first and last polygons respectively.
   *
   * The returned polygon references represent the reference id of the polygon
   * that is entered at the associated path position. The reference id associated
   * with the end point will always be zero.  This allows, for example, matching
   * off-mesh link points to their representative polygons.
   *
   * If the provided result arrays are too small for the entire result set,
   * they will be filled as far as possible from the start toward the end
   * position.
   *
   * @param start path start position
   * @param end path end position
   * @param path an array of polygon references that represent the path corridor
   * @param options additional options
   * @returns the straight path result
   *
   * The straightPath, straightPathFlags, and straightPathRefs arrays returned must be freed after use.
   *
   * ```ts
   * findStraightPathResult.straightPath.destroy();
   * findStraightPathResult.straightPathFlags.destroy();
   * findStraightPathResult.straightPathRefs.destroy();
   * ```
   */
  findStraightPath(start, end, path, options) {
    const maxStraightPathPoints = options?.maxStraightPathPoints ?? 256;
    const straightPathOptions = options?.straightPathOptions ?? 0;
    let pathPolys;
    if (Array.isArray(path)) {
      pathPolys = new UnsignedIntArray();
      pathPolys.copy(path);
    } else {
      pathPolys = path;
    }
    const straightPath = new FloatArray();
    straightPath.resize(maxStraightPathPoints * 3);
    const straightPathFlags = new UnsignedCharArray();
    straightPathFlags.resize(maxStraightPathPoints);
    const straightPathRefs = new UnsignedIntArray();
    straightPathRefs.resize(maxStraightPathPoints);
    const straightPathCountRaw = new Raw.IntRef();
    const status = this.raw.findStraightPath(vec3.toArray(start), vec3.toArray(end), pathPolys.raw, straightPath.raw, straightPathFlags.raw, straightPathRefs.raw, straightPathCountRaw, maxStraightPathPoints, straightPathOptions);
    const straightPathCount = straightPathCountRaw.value;
    Raw.destroy(straightPathCountRaw);
    if (Array.isArray(path)) {
      pathPolys.destroy();
    }
    return {
      success: statusSucceed(status),
      status,
      straightPath,
      straightPathFlags,
      straightPathRefs,
      straightPathCount
    };
  }
  /**
   * Casts a 'walkability' ray along the surface of the navigation mesh from the start position toward the end position.
   *
   * This method is meant to be used for quick, short distance checks.
   *
   * If the path array is too small to hold the result, it will be filled as far as possible from the start postion toward the end position.
   *
   * The raycast ignores the y-value of the end position. (2D check.) This places significant limits on how it can be used.
   *
   * <b>Using the Hit Parameter (t)</b>
   *
   * If the hit parameter is a very high value, then the ray has hit
   * the end position. In this case the path represents a valid corridor to the
   * end position and the value of hitNormal is undefined.
   *
   * If the hit parameter is zero, then the start position is on the wall that
   * was hit and the value of hitNormal is undefined.
   *
   * If 0 < t < 1.0 then the following applies:
   *
   * ```
   * distanceToHitBorder = distanceToEndPosition * t
   * hitPoint = startPos + (endPos - startPos) * t
   * ```
   *
   * <b>Use Case Restriction</b>
   *
   * Consider a scene where there is a main floor with a second floor balcony that hangs over the main floor.
   * So the first floor mesh extends below the balcony mesh.
   * The start position is somewhere on the first floor.
   * The end position is on the balcony.
   *
   * The raycast will search toward the end position along the first floor mesh.
   * If it reaches the end position's xz-coordinates it will indicate FLT_MAX,(no wall hit), meaning it reached the end position.
   * This is one example of why this method is meant for short distance checks.
   *
   * @param startRef the reference id of the start polygon.
   * @param startPosition a position within the start polygon representing the start of the ray
   * @param endPosition the position to cast the ray toward.
   * @param options additional options
   */
  raycast(startRef, startPosition, endPosition, options) {
    const raycastHit = new Raw.Module.dtRaycastHit();
    const raycastOptions = options?.raycastOptions ?? 0;
    const prevRef = options?.prevRef ?? 0;
    const queryFilter = options?.filter?.raw ?? this.defaultFilter.raw;
    const status = this.raw.raycast(startRef, vec3.toArray(startPosition), vec3.toArray(endPosition), queryFilter, raycastOptions, raycastHit, prevRef);
    const result = {
      success: statusSucceed(status),
      status,
      t: raycastHit.t,
      hitNormal: vec3.fromArray(array(i => raycastHit.get_hitNormal(i), 3)),
      hitEdgeIndex: raycastHit.hitEdgeIndex,
      path: array(i => raycastHit.get_path(i), raycastHit.pathCount),
      maxPath: raycastHit.maxPath,
      pathCost: raycastHit.pathCost
    };
    Raw.destroy(raycastHit);
    return result;
  }
  /**
   * Destroys the NavMeshQuery instance
   */
  destroy() {
    this.raw.destroy();
  }
}

const crowdAgentParamsDefaults = {
  radius: 0.5,
  height: 1,
  maxAcceleration: 20,
  maxSpeed: 6,
  collisionQueryRange: 2.5,
  pathOptimizationRange: 0,
  separationWeight: 0,
  updateFlags: 7,
  obstacleAvoidanceType: 0,
  queryFilterType: 0,
  userData: 0
};
class CrowdAgent {
  get radius() {
    return this.raw.params.radius;
  }
  set radius(value) {
    this.raw.params.radius = value;
  }
  get height() {
    return this.raw.params.height;
  }
  set height(value) {
    this.raw.params.height = value;
  }
  get maxAcceleration() {
    return this.raw.params.maxAcceleration;
  }
  set maxAcceleration(value) {
    this.raw.params.maxAcceleration = value;
  }
  get maxSpeed() {
    return this.raw.params.maxSpeed;
  }
  set maxSpeed(value) {
    this.raw.params.maxSpeed = value;
  }
  get collisionQueryRange() {
    return this.raw.params.collisionQueryRange;
  }
  set collisionQueryRange(value) {
    this.raw.params.collisionQueryRange = value;
  }
  get pathOptimizationRange() {
    return this.raw.params.pathOptimizationRange;
  }
  set pathOptimizationRange(value) {
    this.raw.params.pathOptimizationRange = value;
  }
  get separationWeight() {
    return this.raw.params.separationWeight;
  }
  set separationWeight(value) {
    this.raw.params.separationWeight = value;
  }
  get updateFlags() {
    return this.raw.params.updateFlags;
  }
  set updateFlags(value) {
    this.raw.params.updateFlags = value;
  }
  get obstacleAvoidanceType() {
    return this.raw.params.obstacleAvoidanceType;
  }
  set obstacleAvoidanceType(value) {
    this.raw.params.obstacleAvoidanceType = value;
  }
  get queryFilterType() {
    return this.raw.params.queryFilterType;
  }
  set queryFilterType(value) {
    this.raw.params.queryFilterType = value;
  }
  get userData() {
    return this.raw.params.userData;
  }
  set userData(value) {
    this.raw.params.userData = value;
  }
  /**
   * The interpolated position of the agent.
   *
   * Use this if stepping the crowd with interpolation.
   * This will not be updated if stepping the crowd without interpolation.
   */
  interpolatedPosition = {
    x: 0,
    y: 0,
    z: 0
  };
  constructor(crowd, agentIndex) {
    this.crowd = crowd;
    this.agentIndex = agentIndex;
    this.raw = crowd.raw.getEditableAgent(agentIndex);
    this.interpolatedPosition = this.position();
  }
  /**
   * Updates the agent's target.
   * @param position The new target position.
   * @returns True if the request was successful.
   */
  requestMoveTarget(position) {
    const {
      nearestPoint,
      nearestRef
    } = this.crowd.navMeshQuery.findNearestPoly(position, {
      halfExtents: this.crowd.navMeshQuery.defaultQueryHalfExtents,
      filter: this.crowd.navMeshQuery.defaultFilter
    });
    return this.crowd.raw.requestMoveTarget(this.agentIndex, nearestRef, vec3.toArray(nearestPoint));
  }
  /**
   * Submits a new move request for the specified agent.
   * @param velocity The desired velocity of the agent.
   * @returns True if the request was successful.
   */
  requestMoveVelocity(velocity) {
    return this.crowd.raw.requestMoveVelocity(this.agentIndex, vec3.toArray(velocity));
  }
  /**
   * Resets the current move request for the specified agent.
   */
  resetMoveTarget() {
    this.crowd.raw.resetMoveTarget(this.agentIndex);
  }
  /**
   * Teleports the agent to the specified position.
   * @param position
   */
  teleport(position) {
    Raw.CrowdUtils.agentTeleport(this.crowd.raw, this.agentIndex, vec3.toArray(position), vec3.toArray(this.crowd.navMeshQuery.defaultQueryHalfExtents), this.crowd.navMeshQuery.defaultFilter.raw);
    vec3.copy(position, this.interpolatedPosition);
  }
  /**
   * The position of the agent.
   * @returns
   */
  position() {
    return {
      x: this.raw.get_npos(0),
      y: this.raw.get_npos(1),
      z: this.raw.get_npos(2)
    };
  }
  /**
   * The actual velocity of the agent. The change from velocityDesiredObstacleAdjusted -> velocity is constrained by max acceleration.
   */
  velocity() {
    return {
      x: this.raw.get_vel(0),
      y: this.raw.get_vel(1),
      z: this.raw.get_vel(2)
    };
  }
  /**
   * The desired velocity of the agent. Based on the current path, calculated from scratch each frame.
   */
  desiredVelocity() {
    return {
      x: this.raw.get_dvel(0),
      y: this.raw.get_dvel(1),
      z: this.raw.get_dvel(2)
    };
  }
  /**
   * The desired velocity adjusted by obstacle avoidance, calculated from scratch each frame.
   */
  desiredVelocityObstacleAdjusted() {
    return {
      x: this.raw.get_nvel(0),
      y: this.raw.get_nvel(1),
      z: this.raw.get_nvel(2)
    };
  }
  /**
   * Returns the state of the agent.
   *
   * 0 = DT_CROWDAGENT_STATE_INVALID
   * 1 = DT_CROWDAGENT_STATE_WALKING
   * 2 = DT_CROWDAGENT_STATE_OFFMESH
   */
  state() {
    return this.raw.state;
  }
  /**
   * Returns the next target position on the path to the target
   * @returns
   */
  target() {
    return {
      x: this.raw.get_targetPos(0),
      y: this.raw.get_targetPos(1),
      z: this.raw.get_targetPos(2)
    };
  }
  /**
   * Returns the next target position on the path to the target
   * @returns
   */
  nextTargetInPath() {
    return {
      x: this.raw.get_cornerVerts(0),
      y: this.raw.get_cornerVerts(1),
      z: this.raw.get_cornerVerts(2)
    };
  }
  /**
   * Returns the local path corridor corners for the agent
   * @returns
   */
  corners() {
    const points = [];
    for (let i = 0; i < this.raw.ncorners; i++) {
      points.push({
        x: this.raw.get_cornerVerts(i * 3),
        y: this.raw.get_cornerVerts(i * 3 + 1),
        z: this.raw.get_cornerVerts(i * 3 + 2)
      });
    }
    return points;
  }
  /**
   * Returns the agents parameters.
   * @returns
   */
  parameters() {
    const {
      params
    } = this.raw;
    return {
      radius: params.radius,
      height: params.height,
      maxAcceleration: params.maxAcceleration,
      maxSpeed: params.maxSpeed,
      collisionQueryRange: params.collisionQueryRange,
      pathOptimizationRange: params.pathOptimizationRange,
      separationWeight: params.separationWeight,
      updateFlags: params.updateFlags,
      obstacleAvoidanceType: params.obstacleAvoidanceType,
      queryFilterType: params.queryFilterType,
      userData: params.userData
    };
  }
  /**
   * Updates the agent's parameters.
   * Any parameters not specified in the crowdAgentParams object will be unchanged.
   * @param crowdAgentParams agent parameters to update.
   */
  updateParameters(crowdAgentParams) {
    const params = {
      ...this.parameters(),
      ...crowdAgentParams
    };
    this.setParameters(params);
  }
  /**
   * Sets the agent's parameters.
   * Any parameters not specified in the crowdAgentParams object will be set to their default values.
   * @param crowdAgentParams agent parameters
   */
  setParameters(crowdAgentParams) {
    const params = {
      ...crowdAgentParamsDefaults,
      ...crowdAgentParams
    };
    const dtCrowdAgentParams = new Raw.Module.dtCrowdAgentParams();
    dtCrowdAgentParams.radius = params.radius;
    dtCrowdAgentParams.height = params.height;
    dtCrowdAgentParams.maxAcceleration = params.maxAcceleration;
    dtCrowdAgentParams.maxSpeed = params.maxSpeed;
    dtCrowdAgentParams.collisionQueryRange = params.collisionQueryRange;
    dtCrowdAgentParams.pathOptimizationRange = params.pathOptimizationRange;
    dtCrowdAgentParams.separationWeight = params.separationWeight;
    dtCrowdAgentParams.updateFlags = params.updateFlags;
    dtCrowdAgentParams.obstacleAvoidanceType = params.obstacleAvoidanceType;
    dtCrowdAgentParams.queryFilterType = params.queryFilterType;
    dtCrowdAgentParams.userData = params.userData;
    this.crowd.raw.updateAgentParameters(this.agentIndex, dtCrowdAgentParams);
  }
  /**
   * Returns whether the agent is over an off-mesh connection.
   * @returns
   */
  overOffMeshConnection() {
    return Raw.CrowdUtils.overOffMeshConnection(this.crowd.raw, this.agentIndex);
  }
}
class Crowd {
  /**
   * The agents in the crowd.
   */
  agents = {};
  /**
   * The NavMesh the crowd is interacting with.
   */

  /**
   * The NavMeshQuery used to find nearest polys for commands
   */

  /**
   * Accumulator for fixed updates with interpolation
   */
  accumulator = 0;
  /**
   *
   * @param navMesh the navmesh the crowd will use for planning
   * @param param1 the crowd parameters
   *
   * @example
   * ```ts
   * const crowd = new Crowd(navMesh, {
   *   maxAgents: 100,
   *   maxAgentRadius: 1,
   * });
   * ```
   */
  constructor(navMesh, {
    maxAgents,
    maxAgentRadius
  }) {
    this.navMesh = navMesh;
    this.raw = Raw.Detour.allocCrowd();
    this.raw.init(maxAgents, maxAgentRadius, navMesh.raw.getNavMesh());
    this.navMeshQuery = new NavMeshQuery(new Raw.Module.NavMeshQuery(this.raw.getNavMeshQuery()));
  }
  /**
   * Steps the crowd forward in time with a fixed time step.
   *
   * There are two modes. The simple mode is fixed timestepping without interpolation. In this case you only use the first argument. The second case uses interpolation. In that you also provide the time since the function was last used, as well as the maximum fixed timesteps to take.
   *
   * @param dt The fixed time step size to use.
   * @param timeSinceLastCalled The time elapsed since the function was last called.
   * @param maxSubSteps Maximum number of fixed steps to take per function call.
   *
   * @example fixed time stepping
   * ```ts
   * const deltaTime = 1 / 60;
   * crowd.update(deltaTime);
   * ```
   *
   * @example variable time stepping
   * ```ts
   * crowd.update(timeSinceLastUpdate);
   * ```
   *
   * @example fixed time stepping with interpolation
   * ```ts
   * const deltaTime = 1 / 60;
   * const maxSubSteps = 10;
   * crowd.update(deltaTime, timeSinceLastUpdate, maxSubSteps);
   *
   * console.log(agent.interpolatedPosition);
   * ```
   */
  update(dt, timeSinceLastCalled, maxSubSteps = 10) {
    if (timeSinceLastCalled === undefined) {
      // fixed step
      this.raw.update(dt, undefined);
    } else {
      this.accumulator += timeSinceLastCalled;
      // Do fixed steps to catch up
      let substeps = 0;
      while (this.accumulator >= dt && substeps < maxSubSteps) {
        this.raw.update(dt, undefined);
        this.accumulator -= dt;
        substeps++;
      }
      // Interpolate the agent positions
      const t = this.accumulator % dt / dt;
      const agents = this.getAgents();
      for (const agent of agents) {
        vec3.lerp(agent.interpolatedPosition, agent.position(), t, agent.interpolatedPosition);
      }
    }
  }
  /**
   * Adds a new agent to the crowd.
   */
  addAgent(position, crowdAgentParams) {
    const params = {
      ...crowdAgentParamsDefaults,
      ...crowdAgentParams
    };
    const dtCrowdAgentParams = new Raw.Module.dtCrowdAgentParams();
    dtCrowdAgentParams.radius = params.radius;
    dtCrowdAgentParams.height = params.height;
    dtCrowdAgentParams.maxAcceleration = params.maxAcceleration;
    dtCrowdAgentParams.maxSpeed = params.maxSpeed;
    dtCrowdAgentParams.collisionQueryRange = params.collisionQueryRange;
    dtCrowdAgentParams.pathOptimizationRange = params.pathOptimizationRange;
    dtCrowdAgentParams.separationWeight = params.separationWeight;
    dtCrowdAgentParams.updateFlags = params.updateFlags;
    dtCrowdAgentParams.obstacleAvoidanceType = params.obstacleAvoidanceType;
    dtCrowdAgentParams.queryFilterType = params.queryFilterType;
    dtCrowdAgentParams.userData = params.userData;
    const agentIndex = this.raw.addAgent(vec3.toArray(position), dtCrowdAgentParams);
    const agent = new CrowdAgent(this, agentIndex);
    this.agents[agentIndex] = agent;
    return agent;
  }
  /**
   * Gets the agent for the specified index, or null if no agent has the given index.
   * @param agentIndex
   * @returns
   */
  getAgent(agentIndex) {
    const agent = this.agents[agentIndex];
    if (!agent) {
      return null;
    }
    return agent;
  }
  /**
   * Removes the agent from the crowd.
   */
  removeAgent(agent) {
    const agentIndex = typeof agent === 'number' ? agent : agent.agentIndex;
    this.raw.removeAgent(agentIndex);
    delete this.agents[agentIndex];
  }
  /**
   * Returns the maximum number of agents that can be managed by the crowd.
   */
  getAgentCount() {
    return this.raw.getAgentCount();
  }
  /**
   * Returns the number of active agents in the crowd.
   */
  getActiveAgentCount() {
    return Raw.CrowdUtils.getActiveAgentCount(this.raw);
  }
  /**
   * Returns all the agents managed by the crowd.
   */
  getAgents() {
    return Object.values(this.agents);
  }
  /**
   * Gets the query filter for the specified index.
   * @param filterIndex the index of the query filter to retrieve, (min 0, max 15)
   * @returns the query filter
   */
  getFilter(filterIndex) {
    return new QueryFilter(this.raw.getEditableFilter(filterIndex));
  }
  /**
   * Destroys the crowd.
   */
  destroy() {
    Raw.Detour.freeCrowd(this.raw);
  }
}

/**
 * Represents a helper class to visualize navigation cur and related data in PlayCanvas.
 */
class DebugDrawerUtils {
  currentPrimitiveType = 0;
  currentVertices = [];
  primitives = [];
  constructor() {
    this.debugDrawImpl = new Raw.Module.DebugDrawImpl();
    // Bind the debug draw implementation handlers
    this.debugDrawImpl.handleBegin = (primitive, _size) => {
      this.currentPrimitiveType = primitive;
      this.currentVertices = [];
    };
    this.debugDrawImpl.handleDepthMask = _state => {
      // unused for now...
    };
    this.debugDrawImpl.handleTexture = _state => {
      // unused for now...
    };
    this.debugDrawImpl.handleVertexWithColor = (x, y, z, color) => {
      this.vertex(x, y, z, color);
    };
    this.debugDrawImpl.handleVertexWithColorAndUV = (x, y, z, color, _u, _v) => {
      this.vertex(x, y, z, color);
    };
    const primitiveMap = {
      [Raw.Module.DU_DRAW_LINES]: 'lines',
      [Raw.Module.DU_DRAW_TRIS]: 'tris',
      [Raw.Module.DU_DRAW_QUADS]: 'quads',
      [Raw.Module.DU_DRAW_POINTS]: 'points'
    };
    this.debugDrawImpl.handleEnd = () => {
      const type = primitiveMap[this.currentPrimitiveType];
      this.primitives.push({
        type,
        vertices: this.currentVertices
      });
    };
  }
  flush() {
    const cur = this.primitives;
    this.primitives = [];
    return cur;
  }
  drawHeightfieldSolid(hf) {
    Raw.RecastDebugDraw.debugDrawHeightfieldSolid(this.debugDrawImpl, hf.raw);
    return this.flush();
  }
  drawHeightfieldWalkable(hf) {
    Raw.RecastDebugDraw.debugDrawHeightfieldWalkable(this.debugDrawImpl, hf.raw);
    return this.flush();
  }
  drawCompactHeightfieldSolid(chf) {
    Raw.RecastDebugDraw.debugDrawCompactHeightfieldSolid(this.debugDrawImpl, chf.raw);
    return this.flush();
  }
  drawCompactHeightfieldRegions(chf) {
    Raw.RecastDebugDraw.debugDrawCompactHeightfieldRegions(this.debugDrawImpl, chf.raw);
    return this.flush();
  }
  drawCompactHeightfieldDistance(chf) {
    Raw.RecastDebugDraw.debugDrawCompactHeightfieldDistance(this.debugDrawImpl, chf.raw);
    return this.flush();
  }
  drawHeightfieldLayer(layer, idx) {
    Raw.RecastDebugDraw.debugDrawHeightfieldLayer(this.debugDrawImpl, layer.raw, idx);
    return this.flush();
  }
  drawHeightfieldLayers(lset) {
    Raw.RecastDebugDraw.debugDrawHeightfieldLayers(this.debugDrawImpl, lset.raw);
    return this.flush();
  }
  drawRegionConnections(cset, alpha = 1) {
    Raw.RecastDebugDraw.debugDrawRegionConnections(this.debugDrawImpl, cset.raw, alpha);
    return this.flush();
  }
  drawRawContours(cset, alpha = 1) {
    Raw.RecastDebugDraw.debugDrawRawContours(this.debugDrawImpl, cset.raw, alpha);
    return this.flush();
  }
  drawContours(cset, alpha = 1) {
    Raw.RecastDebugDraw.debugDrawContours(this.debugDrawImpl, cset.raw, alpha);
    return this.flush();
  }
  drawPolyMesh(mesh) {
    Raw.RecastDebugDraw.debugDrawPolyMesh(this.debugDrawImpl, mesh.raw);
    return this.flush();
  }
  drawPolyMeshDetail(dmesh) {
    Raw.RecastDebugDraw.debugDrawPolyMeshDetail(this.debugDrawImpl, dmesh.raw);
    return this.flush();
  }
  drawNavMesh(mesh, flags = 0) {
    Raw.DetourDebugDraw.debugDrawNavMesh(this.debugDrawImpl, mesh.raw.getNavMesh(), flags);
    return this.flush();
  }
  drawNavMeshWithClosedList(mesh, query, flags = 0) {
    Raw.DetourDebugDraw.debugDrawNavMeshWithClosedList(this.debugDrawImpl, mesh.raw.m_navMesh, query.raw.m_navQuery, flags);
    return this.flush();
  }
  drawNavMeshNodes(query) {
    Raw.DetourDebugDraw.debugDrawNavMeshNodes(this.debugDrawImpl, query.raw.m_navQuery);
    return this.flush();
  }
  drawNavMeshBVTree(mesh) {
    Raw.DetourDebugDraw.debugDrawNavMeshBVTree(this.debugDrawImpl, mesh.raw.m_navMesh);
    return this.flush();
  }
  drawNavMeshPortals(mesh) {
    Raw.DetourDebugDraw.debugDrawNavMeshPortals(this.debugDrawImpl, mesh.raw.m_navMesh);
    return this.flush();
  }
  drawNavMeshPolysWithFlags(mesh, flags, col) {
    Raw.DetourDebugDraw.debugDrawNavMeshPolysWithFlags(this.debugDrawImpl, mesh.raw.m_navMesh, flags, col);
    return this.flush();
  }
  drawNavMeshPoly(mesh, ref, col) {
    Raw.DetourDebugDraw.debugDrawNavMeshPoly(this.debugDrawImpl, mesh.raw.m_navMesh, ref, col);
    return this.flush();
  }
  /**
   * Disposes of the debug drawer and releases resources.
   */
  dispose() {
    Raw.Module.destroy(this.debugDrawImpl);
  }
  vertex(x, y, z, color) {
    const r = (color & 0xff) / 255;
    const g = (color >> 8 & 0xff) / 255;
    const b = (color >> 16 & 0xff) / 255;
    const a = (color >> 24 & 0xff) / 255;
    this.currentVertices.push([x, y, z, r, g, b, a]);
  }
}
/**
 * Converts a color in 0xRRGGBBAA format to a duRGBA format.
 */
const rgbToDuRgba = hexColor => {
  const r = hexColor >> 16 & 0xff;
  const g = hexColor >> 8 & 0xff;
  const b = hexColor & 0xff;
  return r | g << 8 | b << 16 | 255 << 24;
};

class NavMeshGetTilesAtResult {
  constructor(raw) {
    this.raw = raw;
  }
  tiles(index) {
    return new DetourMeshTile(this.raw.get_tiles(index));
  }
  tileCount() {
    return this.raw.tileCount;
  }
}
class NavMeshRemoveTileResult {
  constructor(raw) {
    this.raw = raw;
  }
  data() {
    return array(i => this.raw.get_data(i), this.raw.dataSize);
  }
  dataSize() {
    return this.raw.dataSize;
  }
}
class NavMeshCalcTileLocResult {
  constructor(raw) {
    this.raw = raw;
  }
  tileX() {
    return this.raw.tileX;
  }
  tileY() {
    return this.raw.tileY;
  }
}
class NavMeshStoreTileStateResult {
  constructor(raw) {
    this.raw = raw;
  }
  data() {
    return array(i => this.raw.get_data(i), this.raw.dataSize);
  }
  dataSize() {
    return this.raw.dataSize;
  }
}
class NavMeshParams {
  constructor(raw) {
    this.raw = raw;
  }
  static create(params) {
    const raw = new Raw.Module.dtNavMeshParams();
    raw.set_orig(0, params.orig.x);
    raw.set_orig(1, params.orig.y);
    raw.set_orig(2, params.orig.z);
    raw.tileWidth = params.tileWidth;
    raw.tileHeight = params.tileHeight;
    raw.maxTiles = params.maxTiles;
    raw.maxPolys = params.maxPolys;
    return new NavMeshParams(raw);
  }
  clone() {
    return NavMeshParams.create({
      orig: {
        x: this.raw.get_orig(0),
        y: this.raw.get_orig(1),
        z: this.raw.get_orig(2)
      },
      tileWidth: this.raw.tileWidth,
      tileHeight: this.raw.tileHeight,
      maxTiles: this.raw.maxTiles,
      maxPolys: this.raw.maxPolys
    });
  }
}
class NavMesh {
  constructor(raw) {
    this.raw = raw ?? new Raw.Module.NavMesh();
  }
  /**
   * Initializes the NavMesh for use with a single tile.
   * @param navMeshData the nav mesh data
   * @returns the status of the operation
   */
  initSolo(navMeshData) {
    return this.raw.initSolo(navMeshData.raw);
  }
  /**
   * Initializes the NavMesh for use with multiple tiles.
   * @param params parameters for the NavMesh
   * @returns the status of the operation
   */
  initTiled(params) {
    return this.raw.initTiled(params.raw);
  }
  /**
   * Adds a tile to the NavMesh.
   * @param navMeshData the nav mesh data
   * @param flags the flags to use when building the nav mesh
   * @param lastRef
   * @returns the status of the operation and the reference of the added tile
   */
  addTile(navMeshData, flags, lastRef) {
    const tileRefRaw = new Raw.UnsignedIntRef();
    const status = this.raw.addTile(navMeshData.raw, flags, lastRef, tileRefRaw);
    const tileRef = tileRefRaw.value;
    Raw.destroy(tileRefRaw);
    return {
      status,
      tileRef
    };
  }
  /**
   * Decodes a standard polygon reference.
   * @param polyRef The polygon reference to decode
   * @returns the decoded polygon reference
   */
  decodePolyId(polyRef) {
    const saltRef = new Raw.UnsignedIntRef();
    const itRef = new Raw.UnsignedIntRef();
    const ipRef = new Raw.UnsignedIntRef();
    this.raw.decodePolyId(polyRef, saltRef, itRef, ipRef);
    const tileSalt = saltRef.value;
    Raw.destroy(saltRef);
    const tileIndex = itRef.value;
    Raw.destroy(itRef);
    const tilePolygonIndex = ipRef.value;
    Raw.destroy(ipRef);
    return {
      tileSalt,
      tileIndex,
      tilePolygonIndex
    };
  }
  /**
   * Derives a standard polygon reference.
   * @param salt The tile's salt value.
   * @param tileIndex The index of the tile. `it` in the C++ api.
   * @param tilePolygonIndex The index of the polygon within the tile. `ip` in the C++ api.
   * @returns the derived polygon reference
   */
  encodePolyId(salt, tileIndex, tilePolygonIndex) {
    return this.raw.encodePolyId(salt, tileIndex, tilePolygonIndex);
  }
  /**
   * Removes a tile from the NavMesh
   * @param ref the tile ref
   * @returns the nav mesh data, so it can be added back later
   */
  removeTile(ref) {
    return new NavMeshRemoveTileResult(this.raw.removeTile(ref));
  }
  /**
   * Calculates the tile grid location for the specified world position.
   * @param pos The world position for the query. [(x, y, z)]
   * @returns
   */
  calcTileLoc(pos) {
    return new NavMeshCalcTileLocResult(this.raw.calcTileLoc(vec3.toArray(pos)));
  }
  /**
   * Gets the tile at the specified grid location.
   * @param x The tile's x-location. (x, y, layer)
   * @param y The tile's y-location. (x, y, layer)
   * @param layer The tile's layer. (x, y, layer)
   * @returns The tile, or null if the tile does not exist.
   */
  getTileAt(x, y, layer) {
    const tile = this.raw.getTileAt(x, y, layer);
    return !Raw.isNull(tile) ? new DetourMeshTile(tile) : null;
  }
  /**
   * Gets all tiles at the specified grid location. (All layers.)
   * @param x The tile's x-location. (x, y)
   * @param y The tile's y-location. (x, y)
   * @param maxTiles The maximum tiles the tiles parameter can hold.
   */
  getTilesAt(x, y, maxTiles) {
    return new NavMeshGetTilesAtResult(this.raw.getTilesAt(x, y, maxTiles));
  }
  /**
   * Gets the tile reference for the tile at specified grid location.
   * @param x The tile's x-location. (x, y, layer)
   * @param y The tile's y-location. (x, y, layer)
   * @param layer The tile's layer. (x, y, layer)
   * @returns The tile reference of the tile, or 0 if there is none.
   */
  getTileRefAt(x, y, layer) {
    return this.raw.getTileRefAt(x, y, layer);
  }
  /**
   * Gets the tile reference for the specified tile.
   * @param tile
   * @returns
   */
  getTileRef(tile) {
    return this.raw.getTileRef(tile.raw);
  }
  /**
   * Gets the tile for the specified tile reference.
   * @param ref The tile reference of the tile to retrieve.
   * @returns The tile for the specified reference, or null if the reference is invalid.
   */
  getTileByRef(ref) {
    const tile = this.raw.getTileByRef(ref);
    return !Raw.isNull(tile) ? new DetourMeshTile(tile) : null;
  }
  /**
   * Returns the maximum number of tiles supported by the navigation mesh.
   */
  getMaxTiles() {
    return this.raw.getMaxTiles();
  }
  /**
   * Gets the tile at the specified index.
   * @param i the tile index. [Limit: 0 >= index < #getMaxTiles()]
   * @returns
   */
  getTile(i) {
    return new DetourMeshTile(this.raw.getTile(i));
  }
  /**
   * Gets the tile and polygon for the specified polygon reference.
   * @param ref The reference for the a polygon.
   * @returns
   */
  getTileAndPolyByRef(ref) {
    const result = this.raw.getTileAndPolyByRef(ref);
    const tile = new DetourMeshTile(result.tile);
    const poly = new DetourPoly(result.poly);
    return {
      success: statusSucceed(result.status),
      status: result.status,
      tile,
      poly
    };
  }
  /**
   * Gets the tile and polygon for the specified polygon reference.
   * @param ref A known valid reference for a polygon.
   * @returns
   */
  getTileAndPolyByRefUnsafe(ref) {
    const result = this.raw.getTileAndPolyByRef(ref);
    const tile = new DetourMeshTile(result.tile);
    const poly = new DetourPoly(result.poly);
    return {
      tile,
      poly
    };
  }
  /**
   * Checks the validity of a polygon reference.
   * @param ref
   * @returns
   */
  isValidPolyRef(ref) {
    return this.raw.isValidPolyRef(ref);
  }
  /**
   * Gets the polygon reference for the tile's base polygon.
   * @param tile
   * @returns
   */
  getPolyRefBase(tile) {
    return this.raw.getPolyRefBase(tile.raw);
  }
  /**
   * Gets the endpoints for an off-mesh connection, ordered by "direction of travel".
   * @param prevRef The reference of the polygon before the connection.
   * @param polyRef The reference of the off-mesh connection polygon.
   * @returns
   */
  getOffMeshConnectionPolyEndPoints(prevRef, polyRef) {
    const startRaw = new Raw.Vec3();
    const endRaw = new Raw.Vec3();
    const status = this.raw.getOffMeshConnectionPolyEndPoints(prevRef, polyRef, startRaw, endRaw);
    const start = vec3.fromRaw(startRaw);
    Raw.destroy(startRaw);
    const end = vec3.fromRaw(endRaw);
    Raw.destroy(endRaw);
    return {
      success: statusSucceed(status),
      status,
      start,
      end
    };
  }
  /**
   * Gets the specified off-mesh connection.
   * @param ref The polygon reference of the off-mesh connection.
   * @returns
   */
  getOffMeshConnectionByRef(ref) {
    return new DetourOffMeshConnection(this.raw.getOffMeshConnectionByRef(ref));
  }
  /**
   * Sets the user defined flags for the specified polygon.
   * @param ref The polygon reference.
   * @param flags The new flags for the polygon.
   */
  setPolyFlags(ref, flags) {
    return this.raw.setPolyFlags(ref, flags);
  }
  /**
   * Gets the user defined flags for the specified polygon.
   * @param ref The polygon reference.
   * @returns
   */
  getPolyFlags(ref) {
    const flagsRaw = new Raw.UnsignedShortRef();
    const status = this.raw.getPolyFlags(ref, flagsRaw);
    const flags = flagsRaw.value;
    Raw.destroy(flagsRaw);
    return {
      status,
      flags
    };
  }
  /**
   * Sets the user defined area for the specified polygon.
   * @param ref The polygon reference.
   * @param flags The new flags for the polygon.
   */
  setPolyArea(ref, area) {
    return this.raw.setPolyArea(ref, area);
  }
  /**
   * Gets the user defined area for the specified polygon.
   * @param ref The polygon reference.
   * @returns
   */
  getPolyArea(ref) {
    const areaRaw = new Raw.UnsignedCharRef();
    const status = this.raw.getPolyArea(ref, areaRaw);
    const area = areaRaw.value;
    Raw.destroy(areaRaw);
    return {
      status,
      area
    };
  }
  /**
   * Gets the size of the buffer required by #storeTileState to store the specified tile's state.
   * @param tile
   * @returns The size of the buffer required to store the state.
   */
  getTileStateSize(tile) {
    return this.raw.getTileStateSize(tile.raw);
  }
  /**
   * Stores the non-structural state of the tile in the specified buffer. (Flags, area ids, etc.)
   * @param tile The tile.
   * @param maxDataSize The size of the data buffer. [Limit: >= #getTileStateSize]
   * @returns
   */
  storeTileState(tile, maxDataSize) {
    return new NavMeshStoreTileStateResult(this.raw.storeTileState(tile.raw, maxDataSize));
  }
  /**
   * Restores the state of the tile.
   * @param tile The tile.
   * @param data The new state. (Obtained from @see storeTileState)
   * @param maxDataSize The size of the state within the data buffer.
   * @returns
   */
  restoreTileState(tile, data, maxDataSize) {
    return this.raw.restoreTileState(tile.raw, data, maxDataSize);
  }
  /**
   * Destroys the NavMesh.
   */
  destroy() {
    this.raw.destroy();
    Raw.Module.destroy(this.raw);
  }
}
/**
 * Gets the positions and indices of the nav mesh.
 * @param navMesh the nav mesh
 * @param flags poly flags to filter by, defaults to undefined to include all polys
 * @returns the positions and indices of the nav mesh
 */
const getNavMeshPositionsAndIndices = (navMesh, flags) => {
  const positions = [];
  const indices = [];
  let tri = 0;
  const maxTiles = navMesh.getMaxTiles();
  for (let tileIndex = 0; tileIndex < maxTiles; tileIndex++) {
    const tile = navMesh.getTile(tileIndex);
    const tileHeader = tile.header();
    if (!tileHeader) continue;
    const tilePolyCount = tileHeader.polyCount();
    for (let tilePolyIndex = 0; tilePolyIndex < tilePolyCount; ++tilePolyIndex) {
      const poly = tile.polys(tilePolyIndex);
      if (flags !== undefined && (poly.flags() & flags) === 0) continue;
      if (poly.getType() === 1) continue;
      const polyVertCount = poly.vertCount();
      const polyDetail = tile.detailMeshes(tilePolyIndex);
      const polyDetailTriBase = polyDetail.triBase();
      const polyDetailTriCount = polyDetail.triCount();
      for (let polyDetailTriIndex = 0; polyDetailTriIndex < polyDetailTriCount; ++polyDetailTriIndex) {
        const detailTrisBaseIndex = (polyDetailTriBase + polyDetailTriIndex) * 4;
        for (let trianglePoint = 0; trianglePoint < 3; ++trianglePoint) {
          if (tile.detailTris(detailTrisBaseIndex + trianglePoint) < polyVertCount) {
            const tileVertsBaseIndex = poly.verts(tile.detailTris(detailTrisBaseIndex + trianglePoint)) * 3;
            positions.push(tile.verts(tileVertsBaseIndex), tile.verts(tileVertsBaseIndex + 1), tile.verts(tileVertsBaseIndex + 2));
          } else {
            const tileVertsBaseIndex = (polyDetail.vertBase() + tile.detailTris(detailTrisBaseIndex + trianglePoint) - poly.vertCount()) * 3;
            positions.push(tile.detailVerts(tileVertsBaseIndex), tile.detailVerts(tileVertsBaseIndex + 1), tile.detailVerts(tileVertsBaseIndex + 2));
          }
          indices.push(tri++);
        }
      }
    }
  }
  return [positions, indices];
};
/**
 * Disables all polys not connected to provided start poly refs.
 * @param navMesh the nav mesh to prune
 * @param startPolyRefs poly refs to start the flood fill from, can be retrieved with `navMeshQuery.findNearestPoly`
 *
 * @example
 * ```ts
 * const navMeshQuery = new NavMeshQuery(navMesh);
 *
 * const nearestPolyResult = navMeshQuery.findNearestPoly(point, {
 *   halfExtents: { x: 2, y: 2, z: 2 },
 * });
 *
 * if (!nearestPolyResult.success) return;
 *
 * floodFillPruneNavMesh(navMesh, [nearestPolyResult.nearestRef]);
 * ```
 */
const floodFillPruneNavMesh = (navMesh, startPolyRefs) => {
  /* find all polys connected to the nearest poly */
  const visited = new Set();
  const openList = [];
  for (const startPolyRef of startPolyRefs) {
    visited.add(startPolyRef);
    openList.push(startPolyRef);
  }
  while (openList.length > 0) {
    const ref = openList.pop();
    // get current poly and tile
    const {
      poly,
      tile
    } = navMesh.getTileAndPolyByRefUnsafe(ref);
    // visit linked polys
    for (let i = poly.firstLink(); i !== Detour.DT_NULL_LINK; i = tile.links(i).next()) {
      const neiRef = tile.links(i).ref();
      // skip invalid and already visited
      if (!neiRef || visited.has(neiRef)) continue;
      // mark as visited
      visited.add(neiRef);
      // visit neighbours
      openList.push(neiRef);
    }
  }
  /* disable unvisited polys */
  for (let tileIndex = 0; tileIndex < navMesh.getMaxTiles(); tileIndex++) {
    const tile = navMesh.getTile(tileIndex);
    if (!tile || !tile.header()) continue;
    const tileHeader = tile.header();
    const base = navMesh.getPolyRefBase(tile);
    for (let i = 0; i < tileHeader.polyCount(); i++) {
      const ref = base | i;
      if (!visited.has(ref)) {
        // set flag to 0
        // this could also be a custom 'disabled' area flag if using custom areas
        navMesh.setPolyFlags(ref, 0);
      }
    }
  }
};

const getRandomSeed = () => {
  return Raw.Module.FastRand.prototype.getSeed();
};
const setRandomSeed = seed => {
  Raw.Module.FastRand.prototype.setSeed(seed);
};

const recastConfigDefaults = {
  borderSize: 0,
  tileSize: 0,
  cs: 0.2,
  ch: 0.2,
  walkableSlopeAngle: 60,
  walkableHeight: 2,
  walkableClimb: 2,
  walkableRadius: 0.5,
  maxEdgeLen: 12,
  maxSimplificationError: 1.3,
  minRegionArea: 8,
  mergeRegionArea: 20,
  maxVertsPerPoly: 6,
  detailSampleDist: 6,
  detailSampleMaxError: 1
};
const createRcConfig = partialConfig => {
  const config = {
    ...recastConfigDefaults,
    ...partialConfig
  };
  const rcConfig = new Raw.Module.rcConfig();
  rcConfig.borderSize = config.borderSize;
  rcConfig.tileSize = config.tileSize;
  rcConfig.cs = config.cs;
  rcConfig.ch = config.ch;
  rcConfig.walkableSlopeAngle = config.walkableSlopeAngle;
  rcConfig.walkableHeight = config.walkableHeight;
  rcConfig.walkableClimb = config.walkableClimb;
  rcConfig.walkableRadius = config.walkableRadius;
  rcConfig.maxEdgeLen = config.maxEdgeLen;
  rcConfig.maxSimplificationError = config.maxSimplificationError;
  rcConfig.minRegionArea = config.minRegionArea;
  rcConfig.mergeRegionArea = config.mergeRegionArea;
  rcConfig.maxVertsPerPoly = config.maxVertsPerPoly;
  rcConfig.detailSampleDist = config.detailSampleDist;
  rcConfig.detailSampleMaxError = config.detailSampleMaxError;
  return rcConfig;
};
const cloneRcConfig = rcConfig => {
  const clone = new Raw.Module.rcConfig();
  clone.set_bmin(0, rcConfig.get_bmin(0));
  clone.set_bmin(1, rcConfig.get_bmin(1));
  clone.set_bmin(2, rcConfig.get_bmin(2));
  clone.set_bmax(0, rcConfig.get_bmax(0));
  clone.set_bmax(1, rcConfig.get_bmax(1));
  clone.set_bmax(2, rcConfig.get_bmax(2));
  clone.width = rcConfig.width;
  clone.height = rcConfig.height;
  clone.borderSize = rcConfig.borderSize;
  clone.tileSize = rcConfig.tileSize;
  clone.cs = rcConfig.cs;
  clone.ch = rcConfig.ch;
  clone.walkableSlopeAngle = rcConfig.walkableSlopeAngle;
  clone.walkableHeight = rcConfig.walkableHeight;
  clone.walkableClimb = rcConfig.walkableClimb;
  clone.walkableRadius = rcConfig.walkableRadius;
  clone.maxEdgeLen = rcConfig.maxEdgeLen;
  clone.maxSimplificationError = rcConfig.maxSimplificationError;
  clone.minRegionArea = rcConfig.minRegionArea;
  clone.mergeRegionArea = rcConfig.mergeRegionArea;
  clone.maxVertsPerPoly = rcConfig.maxVertsPerPoly;
  clone.detailSampleDist = rcConfig.detailSampleDist;
  clone.detailSampleMaxError = rcConfig.detailSampleMaxError;
  return clone;
};
class RecastBuildContext {
  logs = [];
  startTimes = {};
  accumulatedTimes = {};
  constructor(timersAndLogsEnabled = true) {
    const impl = new Raw.Module.RecastBuildContextJsImpl();
    impl.log = (category, msg, len) => {
      if (!this.raw.logEnabled()) return;
      // type is string, but webidl binder passes us a pointer
      const msgPointer = msg;
      const view = new Uint8Array(Raw.Module.HEAPU8.buffer, msgPointer, len);
      const data = new Uint8Array(len);
      data.set(view);
      const msgString = new TextDecoder().decode(data);
      this.log(category, msgString);
    };
    impl.resetLog = () => {
      this.resetLog();
    };
    impl.startTimer = label => {
      if (!this.raw.timerEnabled()) return;
      this.startTimer(label);
    };
    impl.stopTimer = label => {
      if (!this.raw.timerEnabled()) return;
      this.stopTimer(label);
    };
    impl.getAccumulatedTime = label => {
      if (!this.raw.timerEnabled()) return -1;
      return this.getAccumulatedTime(label);
    };
    impl.resetTimers = () => {
      if (!this.raw.timerEnabled()) return;
      this.startTimes = {};
      this.accumulatedTimes = {};
    };
    this.raw = new Raw.Module.RecastBuildContext(impl);
    this.raw.enableTimer(timersAndLogsEnabled);
    this.raw.enableLog(timersAndLogsEnabled);
    this.resetTimers();
  }
  log(category, msg) {
    this.logs.push({
      category,
      msg
    });
  }
  resetLog() {
    this.logs = [];
  }
  startTimer(label) {
    this.startTimes[label] = performance.now();
  }
  stopTimer(label) {
    const endTime = performance.now();
    const deltaTime = endTime - this.startTimes[label];
    if (this.accumulatedTimes[label] === -1) {
      this.accumulatedTimes[label] = deltaTime;
    } else {
      this.accumulatedTimes[label] += deltaTime;
    }
  }
  getAccumulatedTime(label) {
    return this.accumulatedTimes[label];
  }
  resetTimers() {
    for (let i = 0; i < Recast.RC_MAX_TIMERS; i++) {
      this.startTimes[i] = -1;
      this.accumulatedTimes[i] = -1;
    }
  }
}
class RecastChunkyTriMesh {
  constructor(raw) {
    this.raw = raw ?? new Raw.rcChunkyTriMesh();
  }
  init(verts, tris, ntris, trisPerChunk) {
    return Raw.ChunkyTriMeshUtils.createChunkyTriMesh(verts.raw, tris.raw, ntris, trisPerChunk, this.raw);
  }
  getChunksOverlappingRect(boundsMin, boundsMax, chunks, maxChunks) {
    return Raw.ChunkyTriMeshUtils.getChunksOverlappingRect(this.raw, boundsMin, boundsMax, chunks.raw, maxChunks);
  }
  getNodeTris(nodeId) {
    return IntArray.fromRaw(Raw.ChunkyTriMeshUtils.getChunkyTriMeshNodeTris(this.raw, nodeId));
  }
  nodes(index) {
    return this.raw.get_nodes(index);
  }
  maxTrisPerChunk() {
    return this.raw.maxTrisPerChunk;
  }
}
class RecastSpan {
  constructor(raw) {
    this.raw = raw;
  }
  smin() {
    return this.raw.smin;
  }
  smax() {
    return this.raw.smax;
  }
  area() {
    return this.raw.area;
  }
  next() {
    return !Raw.isNull(this.raw.next) ? new RecastSpan(this.raw.next) : null;
  }
}
class RecastSpanPool {
  constructor(raw) {
    this.raw = raw;
  }
  next() {
    return !Raw.isNull(this.raw.next) ? new RecastSpanPool(this.raw.next) : null;
  }
  items(index) {
    return new RecastSpan(this.raw.get_items(index));
  }
}
class RecastHeightfield {
  constructor(raw) {
    this.raw = raw;
  }
  width() {
    return this.raw.width;
  }
  height() {
    return this.raw.height;
  }
  bmin() {
    return vec3.fromArray(array(i => this.raw.get_bmin(i), 3));
  }
  bmax() {
    return vec3.fromArray(array(i => this.raw.get_bmax(i), 3));
  }
  cs() {
    return this.raw.cs;
  }
  ch() {
    return this.raw.ch;
  }
  spans(index) {
    return new RecastSpan(this.raw.get_spans(index));
  }
  pools(index) {
    return new RecastSpanPool(this.raw.get_pools(index));
  }
  freelist(index) {
    return new RecastSpan(this.raw.get_freelist(index));
  }
}
class RecastCompactCell {
  constructor(raw) {
    this.raw = raw;
  }
  index() {
    return this.raw.get_index();
  }
  count() {
    return this.raw.get_count();
  }
}
class RecastCompactSpan {
  constructor(raw) {
    this.raw = raw;
  }
  y() {
    return this.raw.get_y();
  }
  reg() {
    return this.raw.get_reg();
  }
  con() {
    return this.raw.get_con();
  }
  h() {
    return this.raw.get_h();
  }
}
class RecastCompactHeightfield {
  constructor(raw) {
    this.raw = raw;
  }
  width() {
    return this.raw.width;
  }
  height() {
    return this.raw.height;
  }
  spanCount() {
    return this.raw.spanCount;
  }
  walkableHeight() {
    return this.raw.walkableHeight;
  }
  walkableClimb() {
    return this.raw.walkableClimb;
  }
  borderSize() {
    return this.raw.borderSize;
  }
  maxDistance() {
    return this.raw.maxDistance;
  }
  maxRegions() {
    return this.raw.maxRegions;
  }
  bmin() {
    return vec3.fromArray(array(i => this.raw.get_bmin(i), 3));
  }
  bmax() {
    return vec3.fromArray(array(i => this.raw.get_bmax(i), 3));
  }
  cs() {
    return this.raw.cs;
  }
  ch() {
    return this.raw.ch;
  }
  cells(index) {
    return new RecastCompactCell(this.raw.get_cells(index));
  }
  spans(index) {
    return new RecastCompactSpan(this.raw.get_spans(index));
  }
  dist(index) {
    return this.raw.get_dist(index);
  }
  areas(index) {
    return this.raw.get_areas(index);
  }
}
class RecastContour {
  constructor(raw) {
    this.raw = raw;
  }
  verts(index) {
    return this.raw.get_verts(index);
  }
  nverts() {
    return this.raw.nverts;
  }
  rverts(index) {
    return this.raw.get_rverts(index);
  }
  nrverts() {
    return this.raw.nrverts;
  }
  reg() {
    return this.raw.reg;
  }
  area() {
    return this.raw.area;
  }
}
class RecastContourSet {
  constructor(raw) {
    this.raw = raw;
  }
  conts(index) {
    return new RecastContour(this.raw.get_conts(index));
  }
  nconts() {
    return this.raw.nconts;
  }
  bmin() {
    return vec3.fromArray(array(i => this.raw.get_bmin(i), 3));
  }
  bmax() {
    return vec3.fromArray(array(i => this.raw.get_bmax(i), 3));
  }
  cs() {
    return this.raw.cs;
  }
  ch() {
    return this.raw.ch;
  }
  width() {
    return this.raw.width;
  }
  height() {
    return this.raw.height;
  }
  borderSize() {
    return this.raw.borderSize;
  }
  maxError() {
    return this.raw.maxError;
  }
}
class RecastHeightfieldLayer {
  constructor(raw) {
    this.raw = raw;
  }
  bmin() {
    return vec3.fromArray(array(i => this.raw.get_bmin(i), 3));
  }
  bmax() {
    return vec3.fromArray(array(i => this.raw.get_bmax(i), 3));
  }
  cs() {
    return this.raw.cs;
  }
  ch() {
    return this.raw.ch;
  }
  width() {
    return this.raw.width;
  }
  height() {
    return this.raw.height;
  }
  minx() {
    return this.raw.minx;
  }
  maxx() {
    return this.raw.maxx;
  }
  miny() {
    return this.raw.miny;
  }
  maxy() {
    return this.raw.maxy;
  }
  hmin() {
    return this.raw.hmin;
  }
  hmax() {
    return this.raw.hmax;
  }
  heights(index) {
    return this.raw.get_heights(index);
  }
  areas(index) {
    return this.raw.get_areas(index);
  }
  cons(index) {
    return this.raw.get_cons(index);
  }
}
class RecastHeightfieldLayerSet {
  constructor(raw) {
    this.raw = raw;
  }
  layers(index) {
    return new RecastHeightfieldLayer(this.raw.get_layers(index));
  }
  nlayers() {
    return this.raw.nlayers;
  }
}
class RecastPolyMesh {
  constructor(raw) {
    this.raw = raw;
  }
  verts(index) {
    return this.raw.get_verts(index);
  }
  polys(index) {
    return this.raw.get_polys(index);
  }
  regs(index) {
    return this.raw.get_regs(index);
  }
  flags(index) {
    return this.raw.get_flags(index);
  }
  setFlags(index, value) {
    this.raw.set_flags(index, value);
  }
  areas(index) {
    return this.raw.get_areas(index);
  }
  setAreas(index, value) {
    this.raw.set_areas(index, value);
  }
  nverts() {
    return this.raw.nverts;
  }
  npolys() {
    return this.raw.npolys;
  }
  maxpolys() {
    return this.raw.maxpolys;
  }
  nvp() {
    return this.raw.nvp;
  }
  bmin() {
    return vec3.fromArray(array(i => this.raw.get_bmin(i), 3));
  }
  bmax() {
    return vec3.fromArray(array(i => this.raw.get_bmax(i), 3));
  }
  cs() {
    return this.raw.cs;
  }
  ch() {
    return this.raw.ch;
  }
  borderSize() {
    return this.raw.borderSize;
  }
  maxEdgeError() {
    return this.raw.maxEdgeError;
  }
}
class RecastPolyMeshDetail {
  constructor(raw) {
    this.raw = raw;
  }
  meshes(index) {
    return this.raw.get_meshes(index);
  }
  verts(index) {
    return this.raw.get_verts(index);
  }
  tris(index) {
    return this.raw.get_tris(index);
  }
  nmeshes() {
    return this.raw.nmeshes;
  }
  nverts() {
    return this.raw.nverts;
  }
  ntris() {
    return this.raw.ntris;
  }
}
const calcBounds = (verts, nv) => {
  return Raw.Recast.calcBounds(verts.raw, nv);
};
const calcGridSize = (bmin, bmax, cs) => {
  return Raw.Recast.calcGridSize(bmin, bmax, cs);
};
const createHeightfield = (buildContext, heightfield, width, height, bmin, bmax, cs, ch) => {
  return Raw.Recast.createHeightfield(buildContext.raw, heightfield.raw, width, height, bmin, bmax, cs, ch);
};
const markWalkableTriangles = (buildContext, walkableSlopeAngle, verts, nv, tris, nt, areas) => {
  return Raw.Recast.markWalkableTriangles(buildContext.raw, walkableSlopeAngle, verts.raw, nv, tris.raw, nt, areas.raw);
};
const clearUnwalkableTriangles = (buildContext, walkableSlopeAngle, verts, nv, tris, nt, areas) => {
  return Raw.Recast.clearUnwalkableTriangles(buildContext.raw, walkableSlopeAngle, verts.raw, nv, tris.raw, nt, areas.raw);
};
const rasterizeTriangles = (buildContext, verts, nv, tris, areas, nt, heightfield, flagMergeThreshold = 1) => {
  return Raw.Recast.rasterizeTriangles(buildContext.raw, verts.raw, nv, tris.raw, areas.raw, nt, heightfield.raw, flagMergeThreshold);
};
const filterLowHangingWalkableObstacles = (buildContext, walkableClimb, heightfield) => {
  return Raw.Recast.filterLowHangingWalkableObstacles(buildContext.raw, walkableClimb, heightfield.raw);
};
const filterLedgeSpans = (buildContext, walkableHeight, walkableClimb, heightfield) => {
  return Raw.Recast.filterLedgeSpans(buildContext.raw, walkableHeight, walkableClimb, heightfield.raw);
};
const filterWalkableLowHeightSpans = (buildContext, walkableHeight, heightfield) => {
  return Raw.Recast.filterWalkableLowHeightSpans(buildContext.raw, walkableHeight, heightfield.raw);
};
const getHeightFieldSpanCount = (buildContext, heightfield) => {
  return Raw.Recast.getHeightFieldSpanCount(buildContext.raw, heightfield.raw);
};
const buildCompactHeightfield = (buildContext, walkableHeight, walkableClimb, heightfield, compactHeightfield) => {
  return Raw.Recast.buildCompactHeightfield(buildContext.raw, walkableHeight, walkableClimb, heightfield.raw, compactHeightfield.raw);
};
const erodeWalkableArea = (buildContext, radius, compactHeightfield) => {
  return Raw.Recast.erodeWalkableArea(buildContext.raw, radius, compactHeightfield.raw);
};
const medianFilterWalkableArea = (buildContext, compactHeightfield) => {
  return Raw.Recast.medianFilterWalkableArea(buildContext.raw, compactHeightfield.raw);
};
const markBoxArea = (buildContext, bmin, bmax, areaId, compactHeightfield) => {
  return Raw.Recast.markBoxArea(buildContext.raw, bmin, bmax, areaId, compactHeightfield.raw);
};
const markConvexPolyArea = (buildContext, verts, nverts, hmin, hmax, areaId, compactHeightfield) => {
  return Raw.Recast.markConvexPolyArea(buildContext.raw, verts.raw, nverts, hmin, hmax, areaId, compactHeightfield.raw);
};
const markCylinderArea = (buildContext, pos, radius, height, areaId, compactHeightfield) => {
  return Raw.Recast.markCylinderArea(buildContext.raw, pos, radius, height, areaId, compactHeightfield.raw);
};
const buildDistanceField = (buildContext, compactHeightfield) => {
  return Raw.Recast.buildDistanceField(buildContext.raw, compactHeightfield.raw);
};
const buildRegions = (buildContext, compactHeightfield, borderSize, minRegionArea, mergeRegionArea) => {
  return Raw.Recast.buildRegions(buildContext.raw, compactHeightfield.raw, borderSize, minRegionArea, mergeRegionArea);
};
const buildLayerRegions = (buildContext, compactHeightfield, borderSize, minRegionArea) => {
  return Raw.Recast.buildLayerRegions(buildContext.raw, compactHeightfield.raw, borderSize, minRegionArea);
};
const buildRegionsMonotone = (buildContext, compactHeightfield, borderSize, minRegionArea, mergeRegionArea) => {
  return Raw.Recast.buildRegionsMonotone(buildContext.raw, compactHeightfield.raw, borderSize, minRegionArea, mergeRegionArea);
};
const setCon = (compactSpan, dir, i) => {
  return Raw.Recast.setCon(compactSpan.raw, dir, i);
};
const getCon = (compactSpan, dir) => {
  return Raw.Recast.getCon(compactSpan.raw, dir);
};
const getDirOffsetX = dir => {
  return Raw.Recast.getDirOffsetX(dir);
};
const getDirOffsetY = dir => {
  return Raw.Recast.getDirOffsetY(dir);
};
const getDirForOffset = (x, y) => {
  return Raw.Recast.getDirForOffset(x, y);
};
const buildHeightfieldLayers = (buildContext, compactHeightfield, borderSize, walkableHeight, heightfieldLayerSet) => {
  return Raw.Recast.buildHeightfieldLayers(buildContext.raw, compactHeightfield.raw, borderSize, walkableHeight, heightfieldLayerSet.raw);
};
const buildContours = (buildContext, compactHeightfield, maxError, maxEdgeLen, contourSet, buildFlags = Recast.RC_CONTOUR_TESS_WALL_EDGES) => {
  return Raw.Recast.buildContours(buildContext.raw, compactHeightfield.raw, maxError, maxEdgeLen, contourSet.raw, buildFlags);
};
const buildPolyMesh = (buildContext, contourSet, nvp, polyMesh) => {
  return Raw.Recast.buildPolyMesh(buildContext.raw, contourSet.raw, nvp, polyMesh.raw);
};
const mergePolyMeshes = (buildContext, meshes, outPolyMesh) => {
  return Raw.Recast.mergePolyMeshes(buildContext.raw, meshes.map(m => m.raw), meshes.length, outPolyMesh.raw);
};
const buildPolyMeshDetail = (buildContext, mesh, compactHeightfield, sampleDist, sampleMaxError, polyMeshDetail) => {
  return Raw.Recast.buildPolyMeshDetail(buildContext.raw, mesh.raw, compactHeightfield.raw, sampleDist, sampleMaxError, polyMeshDetail.raw);
};
const copyPolyMesh = (buildContext, src, dest) => {
  return Raw.Recast.copyPolyMesh(buildContext.raw, src.raw, dest.raw);
};
const mergePolyMeshDetails = (buildContext, meshes, out) => {
  return Raw.Recast.mergePolyMeshDetails(buildContext.raw, meshes.map(m => m.raw), meshes.length, out.raw);
};
const getHeightfieldLayerHeights = heightfieldLayer => {
  return UnsignedCharArray.fromRaw(Raw.Recast.getHeightfieldLayerHeights(heightfieldLayer.raw));
};
const getHeightfieldLayerAreas = heightfieldLayer => {
  return UnsignedCharArray.fromRaw(Raw.Recast.getHeightfieldLayerAreas(heightfieldLayer.raw));
};
const getHeightfieldLayerCons = heightfieldLayer => {
  return UnsignedCharArray.fromRaw(Raw.Recast.getHeightfieldLayerCons(heightfieldLayer.raw));
};
const allocHeightfield = () => {
  return new RecastHeightfield(Raw.Recast.allocHeightfield());
};
const freeHeightfield = heightfield => {
  return Raw.Recast.freeHeightfield(heightfield.raw);
};
const allocCompactHeightfield = () => {
  return new RecastCompactHeightfield(Raw.Recast.allocCompactHeightfield());
};
const freeCompactHeightfield = compactHeightfield => {
  return Raw.Recast.freeCompactHeightfield(compactHeightfield.raw);
};
const allocHeightfieldLayerSet = () => {
  return new RecastHeightfieldLayerSet(Raw.Recast.allocHeightfieldLayerSet());
};
const freeHeightfieldLayerSet = heightfieldLayerSet => {
  return Raw.Recast.freeHeightfieldLayerSet(heightfieldLayerSet.raw);
};
const allocContourSet = () => {
  return new RecastContourSet(Raw.Recast.allocContourSet());
};
const freeContourSet = contourSet => {
  return Raw.Recast.freeContourSet(contourSet.raw);
};
const allocPolyMesh = () => {
  return new RecastPolyMesh(Raw.Recast.allocPolyMesh());
};
const freePolyMesh = polyMesh => {
  return Raw.Recast.freePolyMesh(polyMesh.raw);
};
const allocPolyMeshDetail = () => {
  return new RecastPolyMeshDetail(Raw.Recast.allocPolyMeshDetail());
};
const freePolyMeshDetail = polyMeshDetail => {
  return Raw.Recast.freePolyMeshDetail(polyMeshDetail.raw);
};

const exportImpl = (navMesh, tileCache) => {
  const navMeshExport = Raw.NavMeshExporter.exportNavMesh(navMesh.raw, tileCache?.raw);
  const arrView = new Uint8Array(Raw.Module.HEAPU8.buffer, navMeshExport.dataPointer, navMeshExport.size);
  const data = new Uint8Array(navMeshExport.size);
  data.set(arrView);
  Raw.NavMeshExporter.freeNavMeshExport(navMeshExport);
  return data;
};
const exportNavMesh = navMesh => {
  return exportImpl(navMesh);
};
const exportTileCache = (navMesh, tileCache) => {
  return exportImpl(navMesh, tileCache);
};

class DetourTileCacheParams {
  constructor(raw) {
    this.raw = raw;
  }
  static create(config) {
    const tileCacheParams = new Raw.Module.dtTileCacheParams();
    tileCacheParams.set_orig(0, config.orig[0]);
    tileCacheParams.set_orig(1, config.orig[1]);
    tileCacheParams.set_orig(2, config.orig[2]);
    tileCacheParams.set_cs(config.cs);
    tileCacheParams.set_ch(config.ch);
    tileCacheParams.set_width(config.width);
    tileCacheParams.set_height(config.height);
    tileCacheParams.set_walkableHeight(config.walkableHeight);
    tileCacheParams.set_walkableRadius(config.walkableRadius);
    tileCacheParams.set_walkableClimb(config.walkableClimb);
    tileCacheParams.set_maxSimplificationError(config.maxSimplificationError);
    tileCacheParams.set_maxTiles(config.maxTiles);
    tileCacheParams.set_maxObstacles(config.maxObstacles);
    return new DetourTileCacheParams(tileCacheParams);
  }
}
class TileCache {
  obstacles = new Map();
  constructor(raw) {
    this.raw = raw ?? new Raw.Module.TileCache();
  }
  /**
   * Initialises the TileCache
   * @param params
   */
  init(params, alloc, compressor, meshProcess) {
    return this.raw.init(params.raw, alloc, compressor, meshProcess.raw);
  }
  /**
   * Updates the tile cache by rebuilding tiles touched by unfinished obstacle requests.
   *
   * After adding or removing obstacles you can call `tileCache.update(navMesh)` to rebuild navmesh tiles.
   *
   * Adding or removing an obstacle will internally create an "obstacle request".
   * TileCache supports queuing up to 64 obstacle requests.
   *
   * The `tileCache.update` method returns `upToDate`, whether the tile cache is fully up to date with obstacle requests and tile rebuilds.
   * Each update call processes up to 64 tiles touched by added or removed obstacles.
   * If the tile cache isn't up to date another call will continue processing obstacle requests and tile rebuilds; otherwise it will have no effect.
   *
   * If not many obstacle requests occur between updates, an easy pattern is to call `tileCache.update` periodically, such as every game update.
   * If many obstacle requests have been made and you need to avoid reaching the 64 obstacle request limit, you can call `tileCache.update` multiple times, bailing out when `upToDate` is true or after a maximum number of updates.
   *
   * @example
   * ```ts
   * const { success, status, upToDate } = tileCache.update(navMesh);
   * ```
   */
  update(navMesh) {
    const {
      status,
      upToDate
    } = this.raw.update(navMesh.raw);
    return {
      success: statusSucceed(status),
      status,
      upToDate
    };
  }
  /**
   * Creates a cylinder obstacle and adds it to the navigation mesh.
   */
  addCylinderObstacle(position, radius, height) {
    const result = this.raw.addCylinderObstacle(vec3.toRaw(position), radius, height);
    if (result.status !== Detour.DT_SUCCESS) {
      return {
        success: false,
        status: result.status
      };
    }
    const ref = result.ref;
    const obstacle = {
      type: 'cylinder',
      ref,
      position,
      radius,
      height
    };
    this.obstacles.set(ref, obstacle);
    return {
      success: true,
      status: result.status,
      obstacle
    };
  }
  /**
   * Creates a box obstacle and adds it to the navigation mesh.
   */
  addBoxObstacle(position, halfExtents, angle) {
    const rawPosition = vec3.toRaw(position);
    const rawHalfExtents = vec3.toRaw(halfExtents);
    const result = this.raw.addBoxObstacle(rawPosition, rawHalfExtents, angle);
    Raw.destroy(rawPosition);
    Raw.destroy(rawHalfExtents);
    if (result.status !== Detour.DT_SUCCESS) {
      return {
        success: false,
        status: result.status
      };
    }
    const ref = result.ref;
    const obstacle = {
      type: 'box',
      ref,
      position,
      halfExtents,
      angle
    };
    this.obstacles.set(ref, obstacle);
    return {
      success: true,
      status: result.status,
      obstacle
    };
  }
  /**
   * Removes an obstacle from the navigation mesh.
   */
  removeObstacle(obstacle) {
    let ref;
    if (typeof obstacle === 'object') {
      ref = obstacle.ref;
    } else {
      ref = obstacle;
    }
    this.obstacles.delete(ref);
    const status = this.raw.removeObstacle(ref);
    return {
      success: statusSucceed(status),
      status
    };
  }
  addTile(data, flags = Detour.DT_COMPRESSEDTILE_FREE_DATA) {
    return this.raw.addTile(data.raw, flags);
  }
  buildNavMeshTile(ref, navMesh) {
    return this.raw.buildNavMeshTile(ref, navMesh.raw);
  }
  buildNavMeshTilesAt(tx, ty, navMesh) {
    return this.raw.buildNavMeshTilesAt(tx, ty, navMesh.raw);
  }
  destroy() {
    this.raw.destroy();
  }
}
class TileCacheMeshProcess {
  constructor(process) {
    this.raw = new Raw.Module.TileCacheMeshProcess();
    this.raw.process = (paramsPtr, polyAreasArrayPtr, polyFlagsArrayPtr) => {
      const params = new NavMeshCreateParams(Raw.Module.wrapPointer(paramsPtr, Raw.Module.dtNavMeshCreateParams));
      const polyAreasArray = Raw.Module.wrapPointer(polyAreasArrayPtr, Raw.Module.UnsignedCharArray);
      const polyFlagsArray = Raw.Module.wrapPointer(polyFlagsArrayPtr, Raw.Module.UnsignedShortArray);
      process(params, UnsignedCharArray.fromRaw(polyAreasArray), UnsignedShortArray.fromRaw(polyFlagsArray));
    };
  }
}
const buildTileCacheLayer = (comp, header, heights, areas, cons, tileCacheData) => {
  return Raw.DetourTileCacheBuilder.buildTileCacheLayer(comp, header, heights.raw, areas.raw, cons.raw, tileCacheData.raw);
};

const createNavMeshExport = data => {
  const nDataBytes = data.length * data.BYTES_PER_ELEMENT;
  const dataPtr = Raw.Module._malloc(nDataBytes);
  const dataHeap = new Uint8Array(Raw.Module.HEAPU8.buffer, dataPtr, nDataBytes);
  dataHeap.set(data);
  const navMeshExport = new Raw.Module.NavMeshExport();
  navMeshExport.dataPointer = dataHeap.byteOffset;
  navMeshExport.size = data.length;
  return {
    navMeshExport,
    dataHeap
  };
};
const importNavMesh = data => {
  const {
    navMeshExport,
    dataHeap
  } = createNavMeshExport(data);
  const result = Raw.NavMeshImporter.importNavMesh(navMeshExport, undefined);
  Raw.Module._free(dataHeap.byteOffset);
  const navMesh = new NavMesh(result.navMesh);
  return {
    navMesh
  };
};
const importTileCache = (data, tileCacheMeshProcess) => {
  const {
    navMeshExport,
    dataHeap
  } = createNavMeshExport(data);
  const result = Raw.NavMeshImporter.importNavMesh(navMeshExport, tileCacheMeshProcess.raw);
  Raw.Module._free(dataHeap.byteOffset);
  const navMesh = new NavMesh(result.navMesh);
  const tileCache = new TileCache(result.tileCache);
  const allocator = result.allocator;
  const compressor = result.compressor;
  return {
    navMesh,
    tileCache,
    allocator,
    compressor
  };
};

export { ChunkIdsArray, Crowd, CrowdAgent, DebugDrawerUtils, Detour, DetourBVNode, DetourLink, DetourMeshHeader, DetourMeshTile, DetourOffMeshConnection, DetourPoly, DetourPolyDetail, DetourTileCacheParams, FloatArray, IntArray, NavMesh, NavMeshCalcTileLocResult, NavMeshCreateParams, NavMeshGetTilesAtResult, NavMeshParams, NavMeshQuery, NavMeshRemoveTileResult, NavMeshStoreTileStateResult, QueryFilter, Raw, Recast, RecastBuildContext, RecastChunkyTriMesh, RecastCompactCell, RecastCompactHeightfield, RecastCompactSpan, RecastContour, RecastContourSet, RecastHeightfield, RecastHeightfieldLayer, RecastHeightfieldLayerSet, RecastPolyMesh, RecastPolyMeshDetail, RecastSpan, RecastSpanPool, TileCache, TileCacheData, TileCacheMeshProcess, TriangleAreasArray, TrianglesArray, UnsignedCharArray, UnsignedIntArray, UnsignedShortArray, VerticesArray, allocCompactHeightfield, allocContourSet, allocHeightfield, allocHeightfieldLayerSet, allocPolyMesh, allocPolyMeshDetail, array, buildCompactHeightfield, buildContours, buildDistanceField, buildHeightfieldLayers, buildLayerRegions, buildPolyMesh, buildPolyMeshDetail, buildRegions, buildRegionsMonotone, buildTileCacheLayer, calcBounds, calcGridSize, clearUnwalkableTriangles, cloneRcConfig, copyPolyMesh, createHeightfield, createNavMeshData, createRcConfig, crowdAgentParamsDefaults, erodeWalkableArea, exportNavMesh, exportTileCache, filterLedgeSpans, filterLowHangingWalkableObstacles, filterWalkableLowHeightSpans, floodFillPruneNavMesh, freeCompactHeightfield, freeContourSet, freeHeightfield, freeHeightfieldLayerSet, freePolyMesh, freePolyMeshDetail, getCon, getDirForOffset, getDirOffsetX, getDirOffsetY, getHeightFieldSpanCount, getHeightfieldLayerAreas, getHeightfieldLayerCons, getHeightfieldLayerHeights, getNavMeshPositionsAndIndices, getRandomSeed, importNavMesh, importTileCache, init, markBoxArea, markConvexPolyArea, markCylinderArea, markWalkableTriangles, medianFilterWalkableArea, mergePolyMeshDetails, mergePolyMeshes, rasterizeTriangles, recastConfigDefaults, rgbToDuRgba, setCon, setRandomSeed, statusDetail, statusFailed, statusInProgress, statusSucceed, statusToReadableString, vec3 };
