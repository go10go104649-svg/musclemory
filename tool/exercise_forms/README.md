# Exercise form authoring

`catalog.json` is the source of truth. The viewer consumes generated Dart data. Reuse the athlete, rig, motion families and recipes; preserve the original bench/incline-dumbbell GLBs and legacy cameras.

## Scope and stopping rules

- Work only on requested IDs, normally one family and up to three distinct exercises unless explicitly requested otherwise. Historical `progress.md` / `next_session.md` files do not authorize backlog resumption.
- Separate parameter variants from new mechanisms. A new mechanism is a bounded task, not a screen-specific branch or an unsuitable reused motion.
- Reuse matching reference observations; investigate gaps/conflicts. Preserve posture, grip/contact, support, joint paths and pivots. Skip decoration, logos, hidden internals and shared lighting/material retuning unless required for correctness or explicitly requested.
- After two unsuccessful corrections of the same defect, stop that scene safely. Record symptoms, attempts and the next decision; leave it unverified, preserve working scenes and do not start other unfinished work.
- Stop after the requested implementation and necessary checks. Report actual results and uncertainties, never invented usage savings or user quality approval.

## Choose the minimum pipeline

| Change | Required work |
| --- | --- |
| Only `animationSpeed`, or custom-camera `cameraAngle` / `cameraTarget` / `cameraScale` | Edit `catalog.json`, regenerate the Dart catalog and check playback/framing. No Blender regeneration or asset packing. Preserve `legacy_press` behavior. |
| Pose, grip, joint path, geometry, or authored range of motion | Regenerate and pack affected IDs; review poses/motion and affected native behavior. A catalog entry alone cannot create a missing motion. |
| Shared rig, authoring family, renderer, camera logic or loader | Determine affected families first; expand generation/regression checks accordingly. |

When later regenerating a scene, review its emitted camera metadata before replacing deliberately tuned catalog values. Do not change unrelated assets, publication status or review flags.

## Reference and verification

1. Review actual manufacturer references and demonstrations. Record URLs/observations in task QA notes; reuse `docs/qa/forms_expansion_2026-09-16/reference_review.md` where relevant. Distinguish facts, chosen dimensions and unknowns. Confirm orientation, contacts, grip, joint path, pivot/rail and moving equipment; names alone are not evidence. Only then set `review.equipmentReference`.
2. Select the shared motion family and recipe, expressing differences through `parameters`. Review start/intermediate/end poses and a motion loop before repeated packaging/builds. Keep working output outside app assets. Palm-anchor metrics alone do not certify visual contact or anatomy.
3. Current `--preview` exports GLB first and renders only two endpoints, NOT preview-only. Inspect missing views in Blender. Export after geometry/motion review; check the emitted camera metadata (fixed view fitted from loop samples).
4. Pack only the affected IDs, regenerate the catalog and run relevant tests. Run common analysis/tests once for unchanged code/assets, then necessary per-OS checks. Later changes invalidate affected results. Do not skip required tests for a usage target.
5. Use explicit `FORM_QA_IDS` for native tests and inspect the screenshots. Include reopening and the normal category-to-detail route. A nonblank-pixel pass is not an appearance review. Both Android and iOS need appropriate evidence; use dedicated QA devices/simulators, never normal user app storage.
6. Keep new scenes `authored` until reference, static pose, motion, Android, iOS and production-route checks pass. `verified` is technical review, not user appearance approval. A representative's pass never approves other exercises. Preserve all generator publication gates.

## Commands

Run from the repository root with the installed official Blender executable. Use a task-specific working directory outside app assets; do not mix new exports with stale GLBs. Commands are pipeline stages, not a sequence to rerun after every parameter tweak.

```sh
Blender --background --factory-startup --python-exit-code 1 --python tool/exercise_forms/author_forms.py -- --ids exercise_id --output /tmp/form-work --preview
python3 tool/exercise_forms/pack_assets.py /tmp/form-work --ids exercise_id
python3 tool/exercise_forms/generate_catalog.py
flutter analyze
flutter test
```

### Targeted packing (implemented)

`--ids low_row,dy_row` packs only those GLBs; omitting it processes all source-folder GLBs as before. Empty, duplicate, path-like or missing selections fail before writes, never fall back to all. The source directory must exist. IDs select filenames, not catalog approval.

Identical recipes are not rewritten; source and shared-chunk checks still run. All recipes count toward global references/hash checks. Optional `--prune` removes only unreferenced hash-named chunks after validation, never source art or another scene's referenced chunks. Prune at a completed batch, not every edit.

JSON retains capacity fields and adds `selected_recipes`, `updated_recipes` (IDs), `unchanged_recipes`: write counts, not saved tokens or quality approval.

Packer tests use only temporary synthetic assets and Python's standard library:

```sh
python3 -m unittest discover -s tool/exercise_forms/tests -p 'test_*.py'
```

### Native scope and logs

Use `--dart-define=FORM_QA_IDS=id1,id2,id1` for selected scenes/reopening. Full playback still runs per ID; lightweight mode is pending. Select relevant regressions for variants; broaden affected-family coverage for shared changes.

Keep full logs outside tracked assets. First report IDs, changed outputs, pass/fail, unrun checks and log paths; inspect actual errors and surrounding logs on failure. Never hide nonzero exits or treat partial output as success. Reuse existing commands, not new orchestration. Start/intermediate/end comparisons support review; use original images for contacts and a loop for motion, retaining required evidence.

## Pending tooling — not implemented

Do not start these tasks merely because this file was read; implement only when they are the current request.

- **Preview-only:** opt-in `--preview-only`, lower-cost start/intermediate/end views before export. No GLB, `.blend`, production recipe/chunk or generated-Dart writes; separate output from production so stale exports cannot be used. Keep joint/contact checks and final loop review. Preserve normal export behavior without the option.
- **Lightweight native mode:** explicit full/light modes and IDs, full by default; reject invalid values. Use full checks on representatives and lighter display/reopen checks only for compatible variants with valid unchanged shared evidence. Record omissions, retain per-scene pose/motion and both-OS evidence, keep the route test separate and never auto-set review flags. Preserve QA-device/build-success guards.
- **Authoring cache:** defer until repetition warrants it. Future keys must cover parameters, athlete/rig, authoring/painting/export code, Blender version/settings; reuse only intact successful outputs. Invalidate affected output and stale approval after changes. No generation-cache skip exists today.

For the preview/light-mode task, verify one existing representative and a compatible variant without new production assets. Prove preview-only produces no production exports, full mode retains checks and light mode cannot bypass publication gates. No new exercise batches, athlete rebuild, renderer replacement, `main.dart`/widget-test split or unrelated refactor. If Blender/native execution is unavailable, leave those checks pending and report the limitation, not completion.

## Assets and rights

Reuse `art/bench_press/bench_press.blend` and retain its license/provenance documentation. Equipment is original procedural geometry informed by demonstrations, not packaged manufacturer photographs, logos, videos or CAD.

App assets contain `.form.json` recipes and immutable SHA-256-addressed binary chunks. Identical binary data shares chunks; the runtime reconstructs only the selected scene. Source `.blend`, previews and duplicate raw GLBs stay outside the app bundle. Logical model/animation/equipment IDs allow future delivery changes, but download delivery is not implemented.

## Candidate route verification

After reference, static pose, motion and both native-platform checks, run
`python3 tool/exercise_forms/generate_catalog.py --review-candidates low_row,dy_row`
to temporarily enable only those authored candidates. Run
`integration_test/exercise_form_route_test.dart` with matching `FORM_QA_IDS` via
the normal category picker/detail screen. Always restore the normal generated
catalog with an EXIT trap. This does not change source review status. Set
`productionRoute` and `verified` in the source only after actual route success.
Never ship a generated catalog marked `TEMPORARY QA CANDIDATES`.
