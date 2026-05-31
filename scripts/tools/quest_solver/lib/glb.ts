// GLB binary parser. Ported from simulate_field_quest.py:load_floor_triangles.
// No external deps — GLB is just a JSON header + binary blob, well-documented in
// the glTF spec.
//
// What we return per mesh primitive: the raw POSITION accessor as XYZ floats,
// plus index buffer. floor.ts turns that into XZ triangles.

import { readFileSync } from "node:fs";

export interface GlbPrimitive {
	meshName: string;
	positions: Float32Array; // [x0, y0, z0, x1, y1, z1, ...]
	indices: Uint32Array | null; // null if non-indexed (every 3 verts = a triangle)
}

interface Accessor {
	bufferView: number;
	byteOffset?: number;
	componentType: number;
	count: number;
	type: string;
}

interface BufferView {
	byteOffset?: number;
	byteLength: number;
	byteStride?: number;
}

/** Parse a .glb file from disk and return its mesh primitives. */
export function loadGlb(path: string): GlbPrimitive[] {
	const buf = readFileSync(path);
	const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

	// 12-byte header: magic ('glTF'), version, total length
	const magic = view.getUint32(0, true);
	if (magic !== 0x46546c67) {
		throw new Error(`${path}: not a GLB file (magic=0x${magic.toString(16)})`);
	}

	// Chunk 0 (JSON): 4-byte length, 4-byte type, payload
	const jsonLen = view.getUint32(12, true);
	const jsonStr = new TextDecoder("utf-8").decode(buf.subarray(20, 20 + jsonLen));
	const json = JSON.parse(jsonStr);

	// Chunk 1 (BIN): 4-byte length, 4-byte type, payload
	// JSON chunk may be padded to 4-byte boundary
	const padding = (4 - (jsonLen % 4)) % 4;
	const binStart = 20 + jsonLen + padding + 8;
	const binLen = view.getUint32(20 + jsonLen + padding, true);
	const bin = buf.subarray(binStart, binStart + binLen);
	const binView = new DataView(bin.buffer, bin.byteOffset, bin.byteLength);

	const accessors: Accessor[] = json.accessors ?? [];
	const bufferViews: BufferView[] = json.bufferViews ?? [];
	const result: GlbPrimitive[] = [];

	for (const mesh of json.meshes ?? []) {
		const meshName: string = mesh.name ?? "";
		for (const prim of mesh.primitives ?? []) {
			const posIdx = prim.attributes?.POSITION;
			if (posIdx == null) continue;

			const posAcc = accessors[posIdx];
			const posBv = bufferViews[posAcc.bufferView];
			const posOffset = (posBv.byteOffset ?? 0) + (posAcc.byteOffset ?? 0);
			const stride = posBv.byteStride ?? 12;
			const positions = new Float32Array(posAcc.count * 3);
			for (let i = 0; i < posAcc.count; i++) {
				positions[i * 3 + 0] = binView.getFloat32(posOffset + i * stride + 0, true);
				positions[i * 3 + 1] = binView.getFloat32(posOffset + i * stride + 4, true);
				positions[i * 3 + 2] = binView.getFloat32(posOffset + i * stride + 8, true);
			}

			let indices: Uint32Array | null = null;
			const idxIdx = prim.indices;
			if (idxIdx != null) {
				const idxAcc = accessors[idxIdx];
				const idxBv = bufferViews[idxAcc.bufferView];
				const idxOffset = (idxBv.byteOffset ?? 0) + (idxAcc.byteOffset ?? 0);
				indices = new Uint32Array(idxAcc.count);
				if (idxAcc.componentType === 5123) {
					// UNSIGNED_SHORT
					for (let i = 0; i < idxAcc.count; i++) {
						indices[i] = binView.getUint16(idxOffset + i * 2, true);
					}
				} else if (idxAcc.componentType === 5125) {
					// UNSIGNED_INT
					for (let i = 0; i < idxAcc.count; i++) {
						indices[i] = binView.getUint32(idxOffset + i * 4, true);
					}
				} else if (idxAcc.componentType === 5121) {
					// UNSIGNED_BYTE
					for (let i = 0; i < idxAcc.count; i++) {
						indices[i] = binView.getUint8(idxOffset + i);
					}
				} else {
					throw new Error(`${path}: unsupported index componentType ${idxAcc.componentType}`);
				}
			}

			result.push({ meshName, positions, indices });
		}
	}

	return result;
}
