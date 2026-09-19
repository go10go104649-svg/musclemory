# Exercise form authoring

`catalog.json` is the source of truth. Reuse the athlete, rig, motion families and recipes; preserve the original bench/incline-dumbbell GLBs and legacy cameras. The viewer consumes generated Dart data.

## Scope and stopping rules

- Work only on requested IDs, normally one family and up to three distinct exercises unless explicitly requested otherwise. Historical logs do not authorize backlog resumption.
- Separate parameter variants from new mechanisms. Reuse matching reference observations; investigate gaps/conflicts. Preserve posture, contacts, support, paths and pivots, not decorative detail or unrelated lighting changes.
- After two unsuccessful corrections of the same defect, stop that scene safely. Record attempts and the next decision; leave it unverified and preserve working scenes.
- Stop after requested implementation and necessary checks. Report actual results, omissions and uncertainties, not invented usage savings or user approval.

## Choose the minimum pipeline

| Change | Work |
| --- | --- |
| Only `animationSpeed`, or custom-camera angle/target/scale | Edit catalog, regenerate Dart, check playback/framing. No Blender regeneration or packing. Preserve `legacy_press`. |
| Pose, grip, path, geometry or authored range of motion | Regenerate/pack affected IDs and review motion plus native behavior. |
| Shared rig/family/renderer/camera logic/loader | Determine affected families and expand regression checks. |

Review emitted camera metadata before overwriting deliberately tuned catalog values. Do not change unrelated assets or publication status. A catalog entry alone cannot create a missing motion.

## Production gates

1. Review actual equipment and demonstrations; reuse relevant observations in `docs/qa/forms_expansion_2026-09-16/reference_review.md`. Record new evidence in the task QA note, distinguishing facts, chosen dimensions and unknowns. Only then set `equipmentReference`.
2. Review start/intermediate/end poses and a complete motion loop before repeated packaging. Numeric palm-anchor checks are not visual/anatomical certification.
3. Export, check camera metadata, pack affected IDs, regenerate Dart and run relevant tests. Common checks may be reused only for unchanged code/assets; subsequent changes invalidate affected results.
4. Review appropriate Android and iOS evidence and the normal category-to-detail route on dedicated QA devices. Never use normal user app storage. Nonblank pixels are not appearance approval.
5. Keep scenes `authored` until reference, pose, motion, both OSes and production-route checks pass. A representative's pass never approves other scenes. Preserve generator publication gates; `verified` is not user approval.

## Preview-only (implemented; real Blender validation pending)

Run from the repository root using the installed Blender executable:

```sh
Blender --background --factory-startup --python-exit-code 1 --python tool/exercise_forms/author_forms.py -- --ids low_row,dy_row --output /tmp/musclemory-preview --preview-only
```

`--preview-only` renders start/mid/end (frames 1/24/47, 420px, 6 Cycles samples) in a fresh `preview-*` subdirectory outside the repository. It still evaluates all 97 motion frames and existing joint/contact checks. Outputs are images, camera/metric data and a per-scene `.preview.json` report written only after all three images exist. No GLB, `.blend`, production recipe/chunk or generated Dart is written. Partial runs have no success report; do not treat older directories as current evidence or feed previews to packing. Static images do not replace full loop/native review.

`--preview` and `--preview-only` are mutually exclusive. Without the new option, existing GLB export is retained; `--preview` additionally saves `.blend` and two 700px endpoint images as before.

## Export and targeted packing

Use a separate task-specific export directory, never a stale mixed folder. These are stages, not commands to repeat after every parameter tweak:

```sh
Blender --background --factory-startup --python-exit-code 1 --python tool/exercise_forms/author_forms.py -- --ids low_row --output /tmp/form-export --preview
python3 tool/exercise_forms/pack_assets.py /tmp/form-export --ids low_row
python3 tool/exercise_forms/generate_catalog.py
flutter analyze
flutter test
```

Packer `--ids` processes only selected filenames, not catalog approval. Omit it for legacy all-source behavior. Invalid/missing selections fail before writes. Identical recipes are not rewritten; global shared-chunk validation still includes all recipes. Optional `--prune` only removes unreferenced hash-named chunks after validation; use at a completed batch, not every edit. JSON reports selected/updated/unchanged recipes and capacity, not token savings.

## Native full/light modes (implemented; Flutter/device validation pending)

Full remains the default, retaining the existing sequence and playback checklist. `FORM_QA_IDS` narrows scope; deliberate repeated IDs still test reopening in full mode.

Light mode requires explicit IDs and `FORM_QA_BASELINE`, a reference to valid full checks for unchanged shared behavior on that OS. This reference is a caller declaration, not automatically verified evidence. Light automatically opens, checks visible geometry, disposes and reopens every selected ID. It omits four motion captures, pause/resume and half-speed testing; pose/motion review and the separate production-route test are still required. Duplicate light IDs, unknown IDs, missing assets and invalid modes are rejected. Neither mode edits review flags or grants publication approval.

The existing guarded wrapper forwards the options to the actual build. Example (replace the evidence reference and QA device ID):

```sh
MUSCLEMORY_QA_TARGET=integration_test/exercise_form_expansion_test.dart \
FORM_QA_MODE=light FORM_QA_IDS=dy_row FORM_QA_BASELINE='QA note for unchanged full checks' \
./tool/verify_workout_lifecycle.sh ios QA_DEVICE_ID
```

Repeat on the dedicated Android emulator with its ID and matching baseline. Use full mode for new mechanisms or affected common behavior. Do not bypass device-name guards or build-success checks; the wrapper still runs analysis and unit tests. `reportData.formQa` and `QA_FORM_PLAN`/`QA_FORM_RESULT` record mode, declared evidence, completed sessions, pass/fail and omissions. On failure inspect actual errors and surrounding logs. Keep complete logs outside tracked assets and summarize first; never hide nonzero exits. Use original images for detailed contact review.

## Validation and remaining work

- Python control tests: `python3 -m unittest discover -s tool/exercise_forms/tests -p 'test_*.py'`. Preview tests mock Blender; wrapper tests use fake external commands and no devices.
- Plan tests: `flutter test test/form_qa_plan_test.dart`. These test selection/reporting, not native rendering.
- At implementation on 2026-09-19, 21 new Python tests and shell syntax checks passed. The 10 new Flutter plan tests, actual Blender rendering and native full/light runs were not executable in the editing environment. Validate low_row (full) and compatible dy_row (light) on both QA OSes, and draft preview output, before relying on the new modes. No production assets/statuses were changed.
- Authoring cache remains deferred. Future reuse must validate inputs, rig, scripts, Blender/settings and output integrity; no generation-cache skip exists today. Do not start unrelated tooling or backlog tasks merely by reading this file.

## Assets and rights

Reuse `art/bench_press/bench_press.blend` with license/provenance documentation. Equipment is original procedural geometry; do not package manufacturer photos, logos, videos or CAD. `.form.json` recipes reference immutable SHA-256-addressed binary chunks; the runtime reconstructs the selected scene. Editable sources/previews/duplicate GLBs stay outside the app bundle. Download delivery is not implemented.

## Candidate route verification

After reference, pose, motion and both native-platform checks, temporarily enable authored candidates with `python3 tool/exercise_forms/generate_catalog.py --review-candidates low_row,dy_row`. Run `integration_test/exercise_form_route_test.dart` with matching `FORM_QA_IDS` through the normal picker/detail screen. Always restore the normal catalog with an EXIT trap. Set source `productionRoute`/`verified` only after actual route success. Never ship `TEMPORARY QA CANDIDATES` output.
