import os
import bpy, pathlib
root=pathlib.Path(os.environ.get('SETKEEP_ART_WORK', os.environ.get('MUSCLEMORY_ART_WORK', '/private/tmp/musclemory-3d-tools')))
bpy.ops.wm.open_mainfile(filepath=str(root/'bench.blend'))
bpy.context.scene.frame_set(1)
human=bpy.data.objects['Athlete']
for old,new in [('muscle_pectoral','_MUSCLE_PECTORAL'),('muscle_deltoid_anterior','_MUSCLE_DELTOID_ANTERIOR'),('muscle_triceps','_MUSCLE_TRICEPS')]:
    attribute=human.data.attributes.get(old)
    if attribute:attribute.name=new
output=pathlib.Path(__file__).resolve().parents[2]/'assets/models/bench_press.glb'
properties=bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
print('EXPORT_OPTIONS',[p for p in properties if any(x in p for x in ('anim','attrib','color','light'))])
bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',
    export_animations=True,export_animation_mode='SCENE',export_frame_range=True,
    export_force_sampling=True,export_anim_scene_split_object=False,
    export_morph=False,export_skins=True,export_def_bones=True,
    export_cameras=True,export_lights=False,export_extras=True,export_attributes=True,
    export_all_influences=False,export_materials='EXPORT')
print('EXPORTED',output.stat().st_size)
