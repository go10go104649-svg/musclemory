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

Light mode requires explicit IDs and `FORM_QA_BASELINE`, a reference to valid full checks for unchanged shared behavior on that OS. This reference is a caller declaration, not automatically verified evidence. Light automatically opens, checks visible geometry, disposes and reopens every selected ID. It omits four motion captures, pause/resume testing; pose/motion review and the separate production-route test are still required. Duplicate light IDs, unknown IDs, missing assets and invalid modes are rejected. Neither mode edits review flags or grants publication approval.

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

After reference, pose, motion and both native-platform checks, run the guarded wrapper with `MUSCLEMORY_QA_TARGET=integration_test/exercise_form_route_test.dart`, matching `FORM_QA_IDS` and `FORM_QA_REVIEW_CANDIDATES`. It runs analysis/unit tests against the normal catalog, then invokes the generator's `--review-candidates` validation for the route build only. Its EXIT trap restores the normal catalog on success or failure. Do not change catalog/source/assets during the run or run another catalog writer concurrently. Set source `productionRoute`/`verified` only after actual route success. Never ship `TEMPORARY QA CANDIDATES` output.

## Offline 17-form batch (2026-09-22)

`batch_forms.py` selects the requested 17 IDs, groups them by existing mechanism,
validates every shared chunk and reports all unavailable prerequisites without
asking for confirmation. No network, installation, device or Git operation is
performed. Scratch output and logs stay in ignored `build/exercise_forms/`.

```sh
python3 -B tool/exercise_forms/batch_forms.py --mode check
python3 -B tool/exercise_forms/batch_forms.py --mode preview
python3 -B tool/exercise_forms/batch_forms.py --mode export
```

Use `--blender PATH` only for an already installed executable allowed by the task
constraints. `--ids id1,id2` narrows the batch. Export preserves existing assets
unless `--rebuild` is explicitly supplied. Each family uses the authorer's multi-ID
path with `--continue-on-error`: blocked or failed scenes are reported separately,
other scenes continue, and an incomplete invocation exits nonzero. Only successful
exports from the fresh invocation are packed. Generated scenes remain `authored`;
regeneration clears their pose/motion/platform/route flags and never promotes them
to `verified`. Inspect emitted cameras and complete existing review gates before
publication. A successful batch is not visual or native-platform certification.

`--preview-only --workspace-preview --output build/exercise_forms/previews`
explicitly permits local previews in that ignored subtree. The original default
still rejects preview output inside the repository. Symlinks escaping the allowed
subtree are rejected. This option never enables production export.

Added authoring paths (exported offline drafts): cable row, standing barbell press,
reverse fly and kneeling ab rollout. Incline fly shares the existing rigid fly
levers with negative `arcDeclination`; its dimensions are illustrative and still
need reference review. Weighted back extension uses the original optional chest
plate with a separate `weighted_back_extension` catalog ID, preserving the working
unweighted animation and record identity. Existing reference observations cover
the chest-held plate; they do not constitute verification of this new export.

Five recipes still lack equipment-reference review. Do not fill those flags with
assumptions. The explicit `--unreviewed-draft` option permits offline draft creation
when external reference work is prohibited; it does not approve equipment or
publish a scene. Default authoring retains its reference prerequisite. Batch
reports identify missing equipment evidence, and authored catalog entries retain
false reference/platform/route checks. Normal publication gates are unchanged.

After the user allowed the installed Blender executable, the 2026-09-22 run used
Blender 4.5.3 at `/Applications/Blender.app/Contents/MacOS/Blender`. The six missing
forms were exported and packed; all 17 requested forms now have assets and actual
start/mid/end previews. Existing assets were preserved. Native/browser QA remains
prohibited. See `docs/qa/forms_batch_2026-09-22.md` for the final evidence and limits.

For an explicitly requested offline draft batch using that existing executable:

```sh
python3 -B tool/exercise_forms/batch_forms.py --mode preview --unreviewed-draft --blender /Applications/Blender.app/Contents/MacOS/Blender
python3 -B tool/exercise_forms/batch_forms.py --mode export --unreviewed-draft --blender /Applications/Blender.app/Contents/MacOS/Blender
```

These commands do not fetch/install Blender or use a browser/device. Runtime
configuration and temporary outputs remain under `build/exercise_forms`.

### Explicit trial availability

The 2026-09-22 user-requested trial enables only the 14 authored batch targets
with `previewEnabled: true`. The normal form view labels these as Preview / 試用.
This does not promote status or complete any review. The catalog generator
requires an existing asset and static-pose review for the opt-in. Other authored
scenes remain unavailable. Re-export clears the opt-in until pose QA is repeated.
Verified publication still requires all existing review gates.


### Publication review and phase 2 (2026-09-22)

The subsequent user request authorizes dedicated iOS Simulator and Android
Emulator review; the earlier offline-only restriction above is historical.
All authored trial opt-ins were removed during quality re-review. Only verified
entries with completed individual review gates are normally available.

New shared authoring paths: planted-foot squat/hinge (`lower_body`), cable
pressdown (bar/rope, grip and unilateral parameters), and dumbbell shoulder
raise (plane and fixed elbow-bend parameters). Existing curl and press/fly
families remain reusable. No new external models or packages were introduced.

See `docs/qa/forms_phase2_2026-09-22.md` for per-exercise decisions, actual
platform evidence and held scenes. Passing numeric QA does not approve a pose.

### Asset-only QA preflight scope

After a successful full regression run, batches changing only form assets,
recipe parameters and catalog review flags may set `FORM_QA_TEST_SCOPE=forms`.
This still runs analysis, catalog/asset tests, viewer lifecycle/playback tests,
QA-plan tests, the build and the requested native checks. It omits unrelated
workout/account widget tests. The default remains `all`; use it again for
shared app/native changes or an unresolved regression. The scoped option is
rejected for non-form targets. It does not skip per-scene visual review,
platform checks, candidate gates or normal-route checks.
