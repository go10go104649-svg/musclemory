"""Offline activity renders from the same CC0 MPFB athlete as category images.
Run with Blender --background --python tool/render_activity_categories.py.
Only writes cardio.png and hyrox.png; existing models and renders are untouched.
"""
import pathlib
import bpy
from mathutils import Vector, Matrix

ROOT = pathlib.Path(__file__).resolve().parents[1]

def aim(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat('-Z', 'Y').to_euler()

def pose(rig, name, direction):
    bone = rig.data.bones[name]
    pb = rig.pose.bones[name]
    matrix = (bone.tail_local - bone.head_local).normalized().rotation_difference(
        Vector(direction).normalized()).to_matrix().to_4x4() @ bone.matrix_local
    matrix.translation = pb.head.copy()
    pb.matrix = matrix
    bpy.context.view_layer.update()

for category in ['cardio', 'hyrox']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/bench_press/bench_press.blend'))
    human = bpy.data.objects['Athlete']
    rig = bpy.data.objects['Athlete.rig']
    for obj in list(bpy.data.objects):
        if obj not in [human, rig]:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in [human, rig]:
        obj.animation_data_clear()
        obj.matrix_world = Matrix.Identity(4)
    human.matrix_parent_inverse = Matrix.Identity(4)
    human.matrix_basis = Matrix.Identity(4)
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    material = bpy.data.materials.new('Neutral category athlete')
    material.use_nodes = True
    bs = material.node_tree.nodes['Principled BSDF']
    bs.inputs['Base Color'].default_value = (.50, .52, .54, 1)
    bs.inputs['Roughness'].default_value = .7
    human.data.materials.clear()
    human.data.materials.append(material)
    for poly in human.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True
    if category == 'cardio':
        directions = {
            'thigh_l': (.03, -.32, -.27), 'calf_l': (.01, .10, -.42),
            'thigh_r': (-.02, .30, -.30), 'calf_r': (-.01, .31, .24),
            'upperarm_l': (.05, .15, -.20), 'lowerarm_l': (.01, -.22, -.02),
            'upperarm_r': (-.04, -.16, -.19), 'lowerarm_r': (0, -.18, .17),
        }
    else:
        directions = {
            'thigh_l': (.01, -.13, -.39), 'calf_l': (0, .03, -.43),
            'thigh_r': (-.01, .12, -.40), 'calf_r': (0, .06, -.42),
            'upperarm_l': (.07, 0, -.24), 'lowerarm_l': (.01, -.01, -.27),
            'upperarm_r': (-.07, 0, -.24), 'lowerarm_r': (-.01, -.01, -.27),
        }
    for name, direction in directions.items():
        pose(rig, name, direction)
    for side in ['l', 'r']:
        pose(rig, 'foot_' + side, (0, -.14, -.03))
    if category == 'hyrox':
        for side, sign in [('l', 1), ('r', -1)]:
            pose(rig, 'hand_' + side, (0, 0, -.10))
            for finger in ['index', 'middle', 'ring', 'pinky']:
                for segment, direction in [('01', (-sign * .02, 0, -.03)),
                                           ('02', (-sign * .02, 0, .012)),
                                           ('03', (sign * .006, 0, .02))]:
                    name = f'{finger}_{segment}_{side}'
                    if name in rig.pose.bones:
                        pose(rig, name, direction)
        # Compact dumbbells communicate a loaded carry, without branding.
        for side in ['l', 'r']:
            wrist = rig.matrix_world @ rig.pose.bones['lowerarm_' + side].tail
            center = wrist + Vector((0, 0, -.055))
            for y, radius, depth in [(0, .022, .25), (-.13, .095, .08), (.13, .095, .08)]:
                bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=depth,
                    location=center + Vector((0, y, 0)), rotation=(1.57079632679, 0, 0))
                obj = bpy.context.object
                obj.data.materials.append(material)
                bevel = obj.modifiers.new('Soft edges', 'BEVEL')
                bevel.width = .008
                bevel.segments = 3
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 600
    scene.render.resolution_y = 480
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.8, .8, .8, 1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = .06
    for position, power, size in [((-2, -3, 3), 130, 2), ((2, -2, 1.5), 35, 3), ((0, 3, 3), 100, 2)]:
        bpy.ops.object.light_add(type='AREA', location=position)
        light = bpy.context.object
        light.data.energy = power
        light.data.shape = 'DISK'
        light.data.size = size
        aim(light, (0, 0, 1))
    bpy.ops.object.camera_add(location=(3, -5, 2.1) if category == 'cardio' else (1.8, -6, 1.7))
    camera = bpy.context.object
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 2.30
    aim(camera, (0, 0, .88))
    scene.camera = camera
    scene.render.filepath = str(ROOT / 'assets/category_muscles' / (category + '.png'))
    bpy.ops.render.render(write_still=True)
