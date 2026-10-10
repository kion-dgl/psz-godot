#!/usr/bin/env python3
"""Check unit conversion across all coordinate-bearing parts of a skinned GLB."""
import json
import struct
import unittest
from import_pso_boomas import bake


def fixture():
    binary = bytearray()
    views, accessors = [], []
    for values, kind in [([10, 20, 30], 'VEC3'), ([40, 50, 60], 'VEC3'),
                         ([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -10, -20, -30, 1], 'MAT4')]:
        views.append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(values) * 4})
        binary += struct.pack('<' + 'f' * len(values), *values)
        accessors.append({'bufferView': len(views)-1, 'componentType':5126, 'count':1, 'type':kind,
                          'min':values[:], 'max':values[:]})
    views.append({'buffer':0, 'byteOffset':len(binary), 'byteLength':4})
    binary += b'PNG!'
    doc = {'asset':{'version':'2.0'}, 'buffers':[{'byteLength':len(binary)}],
           'bufferViews':views, 'accessors':accessors,
           'meshes':[{'primitives':[{'attributes':{'POSITION':0}}, {'attributes':{'POSITION':0}}]}],
           'nodes':[{'translation':[10,20,30], 'scale':[1,1,1]}],
           'skins':[{'inverseBindMatrices':2, 'joints':[0]}],
           'images':[{'bufferView':3,'mimeType':'image/png'}],
           'animations':[{'name':'walk_bm1_s_wala_body','samplers':[{'input':0,'output':1}],
                          'channels':[{'sampler':0,'target':{'node':0,'path':'translation'}},
                                      {'sampler':0,'target':{'node':0,'path':'translation'}}]}]}
    encoded=json.dumps(doc).encode();encoded+=b' '*(-len(encoded)%4)
    return struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary


class BakeTests(unittest.TestCase):
    def test_mesh_skeleton_animation_bind_and_shared_accessors(self):
        raw, mapping=bake(fixture(),0.089)
        size=struct.unpack_from('<I',raw,12)[0]
        doc=json.loads(raw[20:20+size]);binary=raw[28+size:]
        self.assertEqual(struct.unpack_from('<I',raw,8)[0],len(raw))
        self.assertEqual(doc['nodes'][0]['scale'],[1,1,1])
        for got, expected in zip(doc['nodes'][0]['translation'],[0.89,1.78,2.67]):
            self.assertAlmostEqual(got,expected)
        self.assertAlmostEqual(struct.unpack_from('<f',binary,0)[0],0.89,places=5)
        self.assertAlmostEqual(struct.unpack_from('<f',binary,12)[0],3.56,places=5)
        self.assertAlmostEqual(struct.unpack_from('<f',binary,24+48)[0],-0.89,places=5)
        self.assertEqual(struct.unpack_from('<f',binary,24)[0],1)
        self.assertEqual(binary[-4:],b'PNG!')
        self.assertEqual(mapping,{'walk_bm1_s_wala_body':'wlk'})
        self.assertEqual(doc['animations'][0]['extras']['source_animation'],'walk_bm1_s_wala_body')
        self.assertAlmostEqual(doc['accessors'][0]['max'][2],2.67)

    def test_rejects_invalid_glb_header(self):
        with self.assertRaises(ValueError):
            bake(b'not-a-glb-at-all',0.089)


if __name__ == '__main__': unittest.main()
