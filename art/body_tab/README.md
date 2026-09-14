# Body tab: continuous athlete and anatomical material masks

The approved bench-press MPFB2 production body is reused in neutral standing pose. CC0 bundled human/targets: MPFB2 commit 437dd513888a92399d1d3200d2e80859fae55abc. License retained in LICENSE.MPFB-ASSETS.md; provenance in ../bench_press/README.md.

`body_tab.blend` contains one editable continuous athlete, 15 independently named face masks and a neutral surface material. `BodyTabProductionBase` is an unlinked mesh datablock retained for deterministic rebuilds. The original body is not replaced by separate muscle solids. The exported GLB has one node and one mesh with material primitives; all material boundaries lie on the same body surface.

`tool/body_tab/export_body.py` defines mirrored spline contours for pectoralis, anterior/posterior deltoid, biceps, triceps, forearms, trapezius, latissimus, four paired rectus abdominis bellies, obliques, gluteus, quadriceps, hamstrings, adductors and calves. Boundary edges alone are refined three times to retain smooth outlines after the original production decimation. `mask_contours.json` records the control points; `mask_*` face attributes and `body_tab_region_faces` preserve region assignments. These are explanatory training diagrams, not measured activation or clinical anatomy.

Rebuild with Blender 4.5.3:

```
Blender --background --factory-startup --python-exit-code 1 --python tool/body_tab/export_body.py
```

Optional `BODY_RENDER_DIR` renders all muscles in red from three directions after export. `BODY_BASE_BLEND` can select the approved initial base. GLB stays white until explicit runtime gray/relative-red material colors are applied. There are no animations, skinning, equipment, or exercise motions. Asset size: about 3.7 MB, 73,220 vertices and 146,436 triangles. Source and licenses are excluded from the Flutter bundle.

`lib/body_tab_colors.dart` maps the six body-part categories to muscle masks. Intensity is the category set count divided by the maximum of those six categories for the selected period. All-zero periods return zeros; untrained categories reset to neutral gray. Exercise primary/secondary weights remain separately available and do not enter this balance display. The same GLB and fixed front/side/back cameras persist across period changes.
