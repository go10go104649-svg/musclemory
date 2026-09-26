"""Render still thumbnails from existing verified form assets, without authoring new forms.

Run with Blender's Python interpreter:
  Blender --background --factory-startup --python tool/exercise_forms/render_list_thumbnails.py
"""

import json
import struct
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/exercise_thumbnails"
CATALOG = ROOT / "tool/exercise_forms/catalog.json"
SCRATCH = ROOT / "build/exercise_thumbnails"


def unpack_recipe(path):
    recipe = json.loads(path.read_text())
    document = recipe["gltf"]
    binary = bytearray()
    for view, chunk in zip(document["bufferViews"], recipe["chunks"], strict=True):
        while len(binary) % 4:
            binary.append(0)
        view["byteOffset"] = len(binary)
        data = (ROOT / chunk["path"]).read_bytes()
        if len(data) != chunk["length"]:
            raise ValueError(f"Corrupt form chunk: {chunk['path']}")
        binary.extend(data)
    while len(binary) % 4:
        binary.append(0)
    document["buffers"] = [{"byteLength": len(binary)}]
    encoded = json.dumps(document, separators=(",", ":")).encode()
    encoded += b" " * ((-len(encoded)) % 4)
    glb = bytearray(struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary)))
    glb.extend(struct.pack("<II", len(encoded), 0x4E4F534A))
    glb.extend(encoded)
    glb.extend(struct.pack("<II", len(binary), 0x004E4942))
    glb.extend(binary)
    SCRATCH.mkdir(parents=True, exist_ok=True)
    target = SCRATCH / f"{recipe['exerciseId']}.glb"
    target.write_bytes(glb)
    return target


def render_form(entry):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    path = ROOT / entry["assetPath"]
    if path.suffix == ".json":
        path = unpack_recipe(path)
    bpy.ops.import_scene.gltf(filepath=str(path))
    scene = bpy.context.scene
    scene.frame_set(24)

    # The two original GLBs include a large presentation floor. It is not
    # exercise equipment and would shrink the athlete to a few pixels.
    for obj in scene.objects:
        if path.name in {"bench_press.glb", "incline_dumbbell_press.glb"} and obj.type == "MESH" and obj.name.lower() == "floor":
            obj.hide_render = True
    meshes = [obj for obj in scene.objects if obj.type == "MESH"]
    meshes = [obj for obj in meshes if not obj.hide_render]
    if not meshes:
        raise ValueError(f"No renderable geometry: {entry['exerciseId']}")
    corners = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    mins = Vector(min(point[i] for point in corners) for i in range(3))
    maxs = Vector(max(point[i] for point in corners) for i in range(3))
    center = (mins + maxs) / 2
    extent = maxs - mins

    camera_data = bpy.data.cameras.new("Thumbnail camera")
    camera = bpy.data.objects.new("Thumbnail camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.location = center + Vector((extent.length * 0.8, -extent.length * 1.3, extent.length * 0.7))
    direction = center - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(extent.x, extent.y, extent.z) * 1.15

    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.render.film_transparent = True
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    OUTPUT.mkdir(exist_ok=True)
    target = OUTPUT / f"{entry['exerciseId']}.png"
    scene.render.filepath = str(target)
    bpy.ops.render.render(write_still=True)
    print(f"THUMBNAIL {entry['exerciseId']} {target} {extent[:]}")


entries = json.loads(CATALOG.read_text())["exercises"]
for entry in entries:
    if entry.get("status") == "verified" and entry.get("assetPath"):
        render_form(entry)
