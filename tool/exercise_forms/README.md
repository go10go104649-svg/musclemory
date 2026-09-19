# Exercise form authoring

`catalog.json` is the source of truth. The production Flutter viewer consumes the generated catalog; it does not select motion through exercise-specific screen branches. Existing bench press and incline dumbbell press retain their original GLBs and legacy camera behavior.

## Scope and stopping rules

- Work only on the explicitly requested exercise IDs. Normally use one motion family and at most three distinct exercises per task unless a different scope is explicitly requested. Historical `progress.md` / `next_session.md` files are reference material, not authorization to resume the 65-exercise backlog.
- Distinguish a parameter-only variant from a new motion or equipment mechanism. Reuse existing athlete, rig, authoring families and recipes. A new mechanism is a separate, bounded task; do not force it into an unsuitable family or redesign the shared system during a variant task.
- Reuse recorded reference observations when they match the equipment being made; investigate missing or conflicting details rather than restarting unrelated research.
- Preserve posture, grip/contact, pad/foot support, joint paths and equipment pivots. Do not spend a variant task reproducing logos, decorative bolts, hidden internals or retuning shared lighting/materials unless required by the request or a correctness defect.
- If the same defect remains after two deliberate correction attempts, stop work on that scene at a safe checkpoint. Record the symptom, attempts and next decision briefly. Leave it unverified, preserve working scenes and do not expand to other unfinished tasks.
- Finish after the requested implementation and necessary verification. Report changes, checks actually performed and remaining uncertainties; do not invent usage percentages or quality approval.

## Reference before production

1. Inspect a manufacturer product page and actual demonstration for the specific equipment. Record URLs and observations in the relevant task's QA note. Existing reference reviews include `docs/qa/forms_expansion_2026-09-16/reference_review.md`. Distinguish observed facts, artist-selected dimensions and unresolved details.
2. Confirm user orientation, seat/pad contact, grip, joint path, pivot/rail position and moving equipment. Do not infer the entire machine from its name or copy another exercise's pose.
3. Set `review.equipmentReference` only after that review. The author rejects entries without a reference review.
4. Select a shared motion family and equipment recipe. Supply differences through `parameters`. New fundamentally different mechanics require a new authoring family, not a special case in the Flutter screen.
5. Review start, intermediate and end poses plus a motion loop before repeated app packaging/builds. Keep working output outside app assets. The existing `--preview` command exports a GLB first and renders only two endpoint images; it is NOT preview-only. Use Blender inspection for missing views until the pending mode below is implemented. The numeric palm-anchor metric is not a visual contact or anatomical certification.
6. Once geometry and motion are ready, generate the production export and copy its camera metadata into the catalog. Camera fitting samples evaluated geometry across the loop, keeping one fixed view.
7. Pack assets, generate the Dart catalog, run relevant tests and inspect the real native renderers. Verify the production detail route as well as isolated playback. Reuse passing common checks only for unchanged code/assets; rerun checks affected by subsequent changes.
8. Keep status `authored` until reference, static pose, motion, Android, iOS and production-route review are all complete. `verified` is a technical review state, not user appearance approval. A representative's pass does not approve other exercises.

## Existing commands

Run from the repository root. Use the installed official Blender executable and an external working directory. These commands retain their existing behavior:

```sh
Blender --background --factory-startup --python-exit-code 1 --python tool/exercise_forms/author_forms.py -- --ids exercise_id --output /tmp/form-work --preview
python3 tool/exercise_forms/pack_assets.py /tmp/form-work --prune
python3 tool/exercise_forms/generate_catalog.py
flutter analyze
flutter test
```

Do not run the whole sequence after every parameter adjustment. Resolve geometry/contact defects before packaging and native checks. Do not delete or skip necessary tests to achieve a usage target.

For a focused native integration run, pass `--dart-define=FORM_QA_IDS=id1,id2,id1` to the exercise form expansion test. Include reopening and inspect its screenshots; a passing nonblank-pixel assertion alone is not an appearance review. The current test still runs the full playback checklist for every selected ID. No lightweight mode is implemented yet.

Choose affected IDs explicitly: individual variant changes need that variant and relevant regression examples; renderer, camera, rig or loader changes need broader affected-family coverage. Both Android and iOS still require appropriate evidence. Use dedicated QA devices/simulators only, never the user's normal app storage.

## Pending tooling task — not implemented

This section defines the next bounded implementation task. Do not start it merely because this document was read; it must be the current request.

**Target:** reduce authoring/review rework using existing tools, without producing new exercise assets.

- Add opt-in `--preview-only` to `author_forms.py`: render lower-cost start/intermediate/end views before export. Do not write GLBs, Blender source files, production recipes, chunks or generated Dart catalogs in this mode. Keep output separate from production exports so stale GLBs cannot be mistaken for new results. Keep joint/contact checks; still review a motion loop before acceptance. Preserve existing export behavior when the option is absent.
- Add explicit full versus lightweight native checks for selected `FORM_QA_IDS`. Keep full checks as the default and reject invalid modes/IDs. A representative uses the full playback checklist; a compatible variant may use lighter display/reopen checks only when unchanged shared behavior has valid evidence. Record the mode and what was not checked. Require per-exercise pose/motion and appropriate evidence on both OSes; keep the normal route test separate. Never infer or auto-set review flags from a lightweight pass.
- Run common analysis/tests once for the same unchanged revision, then the necessary per-OS checks. If code/assets change, repeat affected checks. Preserve QA-device guards, successful-build checks and all catalog publication gates.

**Out of scope:** new exercise batches, rebuilding the athlete, changing rendering technology, production asset edits, `main.dart` / widget-test splitting, automatic backlog resumption and unrelated refactors.

**Done:** verify the new modes with one existing representative and a compatible variant; prove preview-only produces no production exports, full mode retains its checks, and lightweight results cannot bypass publication gates. Report actual validation and stop. If Blender/native execution is unavailable, explicitly leave that validation pending rather than claiming this task complete.

## Assets and rights

The athlete and skeleton are reused from the project's existing `art/bench_press/bench_press.blend`; retain that source's existing license/provenance documentation. Equipment is original procedural geometry informed by product demonstrations. Manufacturer photographs, logos, videos and CAD files are not packaged in the application.

App assets contain `.form.json` scene recipes and immutable SHA-256-addressed binary chunks. Identical geometry, skin, materials and animation data share chunks where their bytes match. Packing validates chunk hashes and reports referenced capacity. `--prune` removes only generated hash-named chunks no recipe references; it does not delete source art or training data. Source `.blend`, previews and duplicate raw GLBs stay outside the app bundle.

Recipes retain logical model/animation/equipment identifiers so future asset delivery can be introduced without replacing the screen API. Download delivery is not implemented. A data entry alone cannot create an unavailable motion family: obtain and review that motion first.

## Candidate route verification

Once reference, static-pose, motion and both native-platform checks pass, use
`python3 tool/exercise_forms/generate_catalog.py --review-candidates low_row,dy_row`
to enable only those candidates in a temporary generated QA catalog. Run
`integration_test/exercise_form_route_test.dart` with matching `FORM_QA_IDS` through
the normal category picker and detail screen. Always restore the normal generated
catalog afterwards (use an EXIT trap around the test command). This does not
change the source review state. Set `productionRoute` and `verified` in the source
only after the real route succeeds. Never ship a generated file marked
`TEMPORARY QA CANDIDATES`.
