# Bench press editable source

Base: MakeHuman Community MPFB2 bundled human mesh, targets and game_engine rig.
Source: https://github.com/makehumancommunity/mpfb2/tree/437dd513888a92399d1d3200d2e80859fae55abc
Bundled asset license: CC0 1.0 (full text in LICENSE.MPFB-ASSETS.md). Commercial use, modification and app incorporation are permitted by the CC0 asset dedication. MPFB software is GPLv3 and is a production tool; it is not incorporated into the app. No paid or third-party marketplace assets were used.

Production: Blender 4.5.3, MPFB2 commit above. Shape adjusted using the supplied muscle/pectoral/shoulder targets; modifiers baked and mesh decimated; skinning retained. Bench, barbell, animation and red masks authored for this project.

bench_press.blend is the editable source, excluded from Flutter assets. The app uses assets/models/bench_press.glb. Muscle masks are point attributes muscle_pectoral, muscle_deltoid_anterior, muscle_triceps; export renames them _MUSCLE_*. They deform with the same skinned surface. The visible COLOR_0 uses dark red for pecs, light red for anterior deltoids/triceps. Masks describe targets, not measured activation.

Rebuild scripts: tool/bench_press/{make_base,pose_bench,export_bench}.py, in that order through Blender --background --factory-startup --python-exit-code 1 --python SCRIPT. Set MPFB_REPO to the checked-out MPFB2 repository and SETKEEP_ART_WORK to an existing scratch folder. Export uses the project's assets directory. An installed MPFB extension is unnecessary; make_base registers the source in an isolated extension repository. Use a separate BLENDER_USER_CONFIG/BLENDER_USER_EXTENSIONS to preserve personal Blender settings.

Animation: 4-second cycle at 30 authored samples/sec, neutral top hold, controlled descent, short bottom hold, ascent and top. Palm/bar anchor IK and bent legs are baked into one synchronized clip. Fixed oblique camera; no orbit/zoom controls.

Form reference: https://www.nasm.org/resource-center/exercise-library/barbell-bench-press — stable torso on bench, feet planted, controlled lowering and pressing. No claim of individualized coaching or measured muscle activity.

## Incline dumbbell press expansion (2026-09-14)

After the user approved the bench-press appearance, the same human and CC0 provenance were reused for incline dumbbell press. Source: incline_dumbbell_press.blend. Rebuild with pose_incline.py then export_incline.py after make_base.py. Added 45-degree backrest, seat and two independent dumbbells. Each hand's contact anchor follows its own dumbbell throughout the four-second closed cycle.

Reference: https://www.nasm.org/resource-center/exercise-library/two-arm-incline-dumbbell-chest-press . Checked 45-degree backrest, feet planted, back supported, controlled pressing/lowering and soft elbows at the top. This is a target-muscle explanation, not measured activation. No paid material was added.
