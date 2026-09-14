# Bench press 3D quality audit and verification

2026-09-14. Scope: bench press only.

## Status

Prototype implemented; iOS Simulator runtime verified; Android APK build verified. The user approved this bench-press appearance in the subsequent message on 2026-09-14. No other exercise was migrated. No video playback implementation, paid asset purchase or GitHub push.

AGENTS.md specified priority and runtime verification rules, but no concrete earlier unfinished priority. After the material shortage was explained, the user approved production from a free human base.

## Original causes (code and actual iOS screen inspected)

The old renderer was real 3D (SceneKit / Filament), but the generator built 51 disconnected ellipsoids rather than a connected anatomical surface. This produced gaps at joints, round attached muscle lumps, simplified hands and unnatural body proportions. Lighting alone could not fix the geometry.

The original GLBs had no skin, animation or textures. The base color was reddish/tan even for non-target muscles. All 20,196 non-degenerate triangles opposed their stored normals; another 1,836 triangles were degenerate. This was a structural defect, but its isolated visual contribution was not measured. The body-tab frame also clipped the head/feet. The old bench detail contained a standing static model, no bench/bar and no form controls.

Original GLBs: front 476,876 bytes, side 476,812 bytes, back 476,888 bytes. Each: 51 meshes, 12,597 vertices, 22,032 triangles, skins 0, animations 0. Those common views remain outside this bench-only prototype scope.

## Implementation

- Replaced the bench detail's human with the CC0 MPFB2 base, shaped using pectoral/shoulder/arm targets. Connected surface, smooth normals and a game_engine skeleton; joints deform through skin weights.
- Matte neutral gray surface. Pectoral, anterior-deltoid and triceps masks are attributes of the same skinned mesh; COLOR_0 renders dark red pecs and light red supporting muscles. No floating red geometry or multicolor heatmap.
- Authored bench, barbell, bent legs, grip and a 4-second baked bone/bar animation. Controlled descent, bottom hold, ascent and top; analytic palm/bar anchors and identical clip endpoints.
- Fixed oblique camera, square dark form area, play/pause and 0.5/1/1.5 speed. No orbit/zoom/angle controls.
- Vendored interactive_3d 2.2.0 with MIT license. Opt-in SceneKit and Filament playback clocks preserve pause/speed, stop in background and dispose on close. EventChannel subscriptions are canceled on texture disposal.
- Actual iOS loading exposed GLTFSceneKit rejection of custom vertex semantics. An in-memory GLB adapter removes only custom attribute references from drawing JSON, retaining the authored masks, BIN, colors and animation. Regression tested.

Asset: assets/models/bench_press.glb, 4,835,556 bytes (4.61 MiB), one skin, one synchronized animation, 160 channels. Editable Blender source and reproducible scripts are in art/bench_press and tool/bench_press, excluded from app assets.

Source/license: art/bench_press/README.md and LICENSE.MPFB-ASSETS.md. MPFB asset dedication is CC0; MPFB/Blender software are production tools, not incorporated into the app. No paid or marketplace animation was used.

Form reference: https://www.nasm.org/resource-center/exercise-library/barbell-bench-press . Checked controlled raising/lowering, feet on floor and torso supported by the bench. The display explains target muscles, not measured activation or individualized coaching.

## Verification

| Check | Result |
| --- | --- |
| flutter analyze | No issues found (3.2s) |
| flutter test | All 64 tests passed, including 3 new GLB/adapter/control/lifecycle tests |
| iOS debug simulator build | Successful, final Runner.app installed |
| Android arm64 debug APK | Successful, temporary JDK21/SDK36/NDK28.2 environment |
| iOS runtime | iPhone 17, iOS 26.5 Simulator: loaded model, bone/bar motion, loop, pause, speed selection to 0.5, resume, close/reopen |
| Pause preservation | Model viewport from two screenshots separated in time had zero changed pixels; manual pause persisted after background/foreground |
| Existing features | Record screen navigation, Home, monthly history and existing weight display checked in actual app. Regression suite covers records/history/timers/share |
| Android runtime | Not tested; build success is not visual/runtime validation |
| Performance | Continuous movement inspected through actual recording frames; FPS, memory, battery and post-close CPU not measured. Disposal verified in code/tests |

Initial load and test failures were fixed before the successful final run. Initial logs are not final results. See qa/bench_press_2026-09-14/final_verification.md.

## Actual evidence

Same iPhone bench-detail screen, same device resolution. Identical pose/camera comparison is impossible because the old implementation was a standing static human. No generated reference image is used as evidence.

- Before: qa/bench_press_2026-09-14/before_bench_detail.png
- After: qa/bench_press_2026-09-14/after_bench_detail.png
- Actual app recording, 5 seconds / more than one cycle: qa/bench_press_2026-09-14/bench_press_preview.mp4
- Actual recording frames: qa/bench_press_2026-09-14/phase_0.5.png through phase_4.5.png

## Remaining limitations and approval boundary

The connected human is substantially different from the ellipsoid mannequin, but is not a fully sculpted anatomical atlas like the reference image. Chest/shoulder definition and mask boundaries can benefit from additional sculpting. The visible floor boundary remains a visual refinement opportunity.

The free base, equipment, motion and editable target masks are now available; no paid material is required for this prototype. The subsequent bench-press visual approval allows incremental expansion. Each new exercise still requires its own implementation and runtime verification. Android device visuals, physical iPhone performance and exhaustive per-vertex body/equipment collision tests remain unverified.

Subsequent approved expansion: qa/incline_press_2026-09-14/verification.md records the incline dumbbell press implementation and verification.
