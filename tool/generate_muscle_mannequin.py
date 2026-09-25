#!/usr/bin/env python3
"""Generate the original, redistributable SETKEEP segmented mannequin GLB."""
import json, math, struct, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if len(sys.argv) == 1:
    for filename, angle in (
        ('muscle_mannequin_front.glb', 0),
        ('muscle_mannequin_side.glb', math.pi / 2),
        ('muscle_mannequin_back.glb', math.pi),
    ):
        subprocess.run(
            [sys.executable, __file__, str(angle), filename], check=True
        )
    raise SystemExit

GLOBAL_Y = float(sys.argv[1])
OUT = ROOT / 'assets/models' / sys.argv[2]
LAT, LON = 12, 18
parts = []

MUSCLE = [0.55, 0.24, 0.20, 1.0]
MUSCLE_LIGHT = [0.68, 0.34, 0.29, 1.0]
TENDON = [0.76, 0.65, 0.50, 1.0]


def add(name, center, scale, rotation=(0, 0, 0), color=MUSCLE):
    parts.append((name, center, scale, rotation, color))


def paired(base, x, y, z, scale, rotation_z=0, color=MUSCLE):
    add(base + '_l', (-x, y, z), scale, (0, 0, rotation_z), color)
    add(base + '_r', (x, y, z), scale, (0, 0, -rotation_z), color)

# Neutral structural pieces.
add('head', (0, 1.72, 0), (0.27, 0.34, 0.25), color=MUSCLE_LIGHT)
paired('sternocleidomastoid', 0.09, 1.39, 0.03, (0.075, 0.23, 0.08), 0.12)
add('pelvis_core', (0, -0.28, 0), (0.36, 0.28, 0.23), color=MUSCLE_LIGHT)
paired('hand', 0.98, 0.02, 0.0, (0.12, 0.25, 0.07), 0.08, TENDON)
paired('foot', 0.24, -1.82, 0.10, (0.21, 0.12, 0.38), 0, TENDON)

# Torso muscles, each independently addressable.
paired('pectoralis_major', 0.23, 1.02, 0.18, (0.27, 0.22, 0.12), 0.05)
paired('pectoralis_upper', 0.22, 1.18, 0.14, (0.25, 0.12, 0.11), 0.04, MUSCLE_LIGHT)
add('trapezius', (0, 1.18, -0.12), (0.38, 0.32, 0.12), color=MUSCLE_LIGHT)
paired('latissimus_dorsi', 0.25, 0.66, -0.14, (0.25, 0.48, 0.12), 0.06)
paired('serratus_anterior', 0.38, 0.67, 0.10, (0.11, 0.30, 0.08), 0.06, MUSCLE_LIGHT)
paired('external_oblique', 0.26, 0.25, 0.08, (0.17, 0.38, 0.10), 0.03, MUSCLE_LIGHT)
for row, y in enumerate((0.70, 0.46, 0.22, -0.02)):
    paired(f'rectus_abdominis_{row + 1}', 0.105, y, 0.17, (0.10, 0.125, 0.075), 0)

# Shoulder and arm groups.
paired('deltoid_anterior', 0.55, 1.08, 0.12, (0.20, 0.25, 0.18), 0.20)
paired('deltoid_posterior', 0.56, 1.06, -0.13, (0.19, 0.24, 0.16), 0.20, MUSCLE_LIGHT)
paired('biceps_brachii', 0.70, 0.69, 0.12, (0.13, 0.29, 0.12), 0.23)
paired('triceps_brachii', 0.72, 0.67, -0.11, (0.14, 0.31, 0.12), 0.23, MUSCLE_LIGHT)
paired('forearm_flexors', 0.86, 0.29, 0.08, (0.11, 0.31, 0.10), 0.15)
paired('forearm_extensors', 0.87, 0.27, -0.08, (0.10, 0.31, 0.09), 0.15, MUSCLE_LIGHT)

# Hip and leg groups.
paired('gluteus_maximus', 0.23, -0.42, -0.17, (0.25, 0.30, 0.18), 0.02)
paired('quadriceps', 0.24, -0.86, 0.13, (0.22, 0.47, 0.16), 0.03)
paired('adductors', 0.10, -0.83, 0.01, (0.13, 0.43, 0.12), -0.02, MUSCLE_LIGHT)
paired('hamstrings', 0.25, -0.89, -0.14, (0.20, 0.46, 0.14), 0.03, MUSCLE_LIGHT)
paired('tibialis_anterior', 0.23, -1.43, 0.10, (0.12, 0.40, 0.10), 0.01)
paired('gastrocnemius', 0.24, -1.42, -0.13, (0.15, 0.38, 0.13), 0.01, MUSCLE_LIGHT)


def rotate(v, rot):
    x, y, z = v
    rx, ry, rz = rot
    cy, sy, cx, sx, cz, sz = math.cos(ry), math.sin(ry), math.cos(rx), math.sin(rx), math.cos(rz), math.sin(rz)
    y, z = y * cx - z * sx, y * sx + z * cx
    x, z = x * cy + z * sy, -x * sy + z * cy
    return (x * cz - y * sz, x * sz + y * cz, z)


def sphere(center, scale, rot):
    positions, normals, indices = [], [], []
    world_center = rotate(center, (0, GLOBAL_Y, 0))
    for i in range(LAT + 1):
        theta = math.pi * i / LAT
        st, ct = math.sin(theta), math.cos(theta)
        for j in range(LON + 1):
            phi = 2 * math.pi * j / LON
            cp, sp = math.cos(phi), math.sin(phi)
            local = (st * cp, ct, st * sp)
            point = rotate((local[0] * scale[0], local[1] * scale[1], local[2] * scale[2]), rot)
            point = rotate(point, (0, GLOBAL_Y, 0))
            positions.extend(
                (
                    point[0] + world_center[0],
                    point[1] + world_center[1],
                    point[2] + world_center[2],
                )
            )
            n = rotate((local[0] / scale[0], local[1] / scale[1], local[2] / scale[2]), rot)
            n = rotate(n, (0, GLOBAL_Y, 0))
            length = math.sqrt(sum(c * c for c in n))
            normals.extend(c / length for c in n)
    stride = LON + 1
    for i in range(LAT):
        for j in range(LON):
            a, b = i * stride + j, (i + 1) * stride + j
            indices.extend((a, b, a + 1, a + 1, b, b + 1))
    return positions, normals, indices

blob = bytearray()
views, accessors, meshes, nodes, materials = [], [], [], [], []

def align4():
    while len(blob) % 4: blob.append(0)

def write_view(data, target):
    align4(); offset = len(blob); blob.extend(data)
    views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(data), 'target': target})
    return len(views) - 1

for name, center, scale, rot, color in parts:
    pos, norm, idx = sphere(center, scale, rot)
    pview = write_view(struct.pack('<%sf' % len(pos), *pos), 34962)
    nview = write_view(struct.pack('<%sf' % len(norm), *norm), 34962)
    iview = write_view(struct.pack('<%sH' % len(idx), *idx), 34963)
    xs, ys, zs = pos[0::3], pos[1::3], pos[2::3]
    pacc = len(accessors); accessors.append({'bufferView': pview, 'componentType': 5126, 'count': len(pos)//3, 'type': 'VEC3', 'min': [min(xs), min(ys), min(zs)], 'max': [max(xs), max(ys), max(zs)]})
    nacc = len(accessors); accessors.append({'bufferView': nview, 'componentType': 5126, 'count': len(norm)//3, 'type': 'VEC3'})
    iacc = len(accessors); accessors.append({'bufferView': iview, 'componentType': 5123, 'count': len(idx), 'type': 'SCALAR'})
    mat = len(materials); materials.append({'name': name + '_material', 'pbrMetallicRoughness': {'baseColorFactor': color, 'metallicFactor': 0.0, 'roughnessFactor': 0.72}})
    mesh = len(meshes); meshes.append({'name': name, 'primitives': [{'attributes': {'POSITION': pacc, 'NORMAL': nacc}, 'indices': iacc, 'material': mat}]})
    nodes.append({'name': name, 'mesh': mesh})

camera_node = len(nodes)
nodes.append({'name': 'Camera', 'camera': 0, 'translation': [0, 0.05, 5.2]})
gltf = {
    'asset': {'version': '2.0', 'generator': 'SETKEEP procedural mannequin generator'},
    'scene': 0,
    'scenes': [{'nodes': list(range(len(nodes)))}],
    'cameras': [
        {
            'name': 'Camera',
            'type': 'perspective',
            'perspective': {'yfov': 0.72, 'znear': 0.01, 'zfar': 100.0},
        }
    ],
    'nodes': nodes, 'meshes': meshes, 'materials': materials,
    'buffers': [{'byteLength': len(blob)}], 'bufferViews': views, 'accessors': accessors,
}
json_bytes = json.dumps(gltf, separators=(',', ':')).encode()
while len(json_bytes) % 4: json_bytes += b' '
while len(blob) % 4: blob.append(0)
total = 12 + 8 + len(json_bytes) + 8 + len(blob)
OUT.parent.mkdir(parents=True, exist_ok=True)
with OUT.open('wb') as f:
    f.write(struct.pack('<III', 0x46546C67, 2, total))
    f.write(struct.pack('<II', len(json_bytes), 0x4E4F534A)); f.write(json_bytes)
    f.write(struct.pack('<II', len(blob), 0x004E4942)); f.write(blob)
print(f'{OUT} ({OUT.stat().st_size:,} bytes, {len(parts)} named parts)')
