"""Offline batch regressions; mocked Blender is not anatomical validation."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import batch_forms
from batch_support import blockers, family, run_selected
from author_options import parse_options


class BatchFormsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.report = self.root / 'result.json'

    def spec(self, eid):
        return dict(exerciseId=eid, animationId='lever_row', equipmentId='row_machine',
                    references=['local observation'], review={'equipmentReference': True})

    def test_failure_and_missing_reference_do_not_block_remaining_scenes(self):
        specs = [self.spec(eid) for eid in ('failed', 'unreviewed', 'working')]
        specs[1]['review']['equipmentReference'] = False
        def generate(spec):
            if spec['exerciseId'] == 'failed':
                raise ValueError('Unreachable joint')
        author = Mock(side_effect=generate)
        results = run_selected(specs, author, self.report)
        self.assertEqual([r['result'] for r in results], ['failed', 'skipped', 'generated'])
        self.assertEqual([call.args[0]['exerciseId'] for call in author.call_args_list], ['failed', 'working'])
        self.assertEqual(json.loads(self.report.read_text()), results)
        self.assertNotIn('staticPose', specs[2]['review'])
        self.assertFalse(results[-1]['reviewApproved'])

    def test_explicit_offline_draft_keeps_evidence_unreviewed(self):
        spec = self.spec('draft')
        spec['references'] = []
        spec['review']['equipmentReference'] = False
        author = Mock()
        results = run_selected([spec], author, self.report, unreviewed_draft=True)
        author.assert_called_once_with(spec)
        self.assertEqual(results[0]['result'], 'generated')
        self.assertFalse(results[0]['equipmentReferenceReviewed'])
        self.assertFalse(results[0]['reviewApproved'])
        self.assertEqual(spec['references'], [])
        self.assertFalse(spec['review']['equipmentReference'])
        self.assertIn('equipment reference not reviewed', blockers(spec))

    def test_offline_draft_does_not_allow_unknown_motion_family(self):
        spec = self.spec('draft')
        spec['animationId'] = 'unimplemented'
        author = Mock()
        results = run_selected([spec], author, self.report, unreviewed_draft=True)
        author.assert_not_called()
        self.assertEqual(results[0]['result'], 'skipped')

    def test_unknown_mechanism_is_skipped_before_blender(self):
        spec = self.spec('future'); spec['animationId'] = 'future_family'
        author = Mock()
        results = run_selected([spec], author, self.report)
        self.assertEqual(results[0]['result'], 'skipped')
        author.assert_not_called()

    def test_seated_dumbbell_press_reuses_vertical_family_with_review_gates(self):
        entries = json.loads((TOOLS / 'catalog.json').read_text())['exercises']
        by_id = {e['exerciseId']: e for e in entries}
        standing = by_id['military_press']
        seated = by_id['dumbbell_shoulder_press']
        self.assertEqual(family(standing), family(seated))
        self.assertTrue(seated['parameters']['seated'])
        self.assertNotIn('seated', standing['parameters'])
        self.assertFalse(seated.get('previewEnabled', False))
        if seated['status'] == 'verified':
            self.assertTrue(all(seated['review'].values()))
        else:
            self.assertFalse(seated['review']['productionRoute'])

    def test_fly_recipe_opts_into_constant_elbow_path_only_for_new_assets(self):
        entries = json.loads((TOOLS / 'catalog.json').read_text())['exercises']
        by_id = {e['exerciseId']: e for e in entries}
        for eid in ('dumbbell_fly', 'incline_dumbbell_fly'):
            entry = by_id[eid]
            self.assertEqual(entry['animationId'], 'fly')
            self.assertTrue(entry['parameters']['constantElbowFly'])
            self.assertEqual(entry['gripType'], 'neutral')
            self.assertFalse(entry.get('previewEnabled', False))
        for eid in batch_forms.TARGETS:
            self.assertFalse(by_id[eid]['parameters'].get('constantElbowFly', False))

    def test_rebuild_keeps_incomplete_scenes_unpublished_and_preserves_original_two(self):
        entries = json.loads((TOOLS / 'catalog.json').read_text())['exercises']
        originals = {'bench_press', 'incline_dumbbell_press'}
        for spec in entries:
            if spec['exerciseId'] in originals:
                self.assertEqual(spec['status'], 'verified')
                continue
            if not spec.get('assetPath'):
                continue
            gates = ('equipmentReference', 'staticPose', 'motion', 'android', 'ios', 'productionRoute')
            if not all(spec['review'].get(gate) is True for gate in gates):
                self.assertEqual(spec['status'], 'authored', spec['exerciseId'])
            self.assertFalse(spec.get('previewEnabled', False))
            self.assertTrue((TOOLS.parents[1] / spec['assetPath']).is_file())

    def test_target_manifest_covers_exactly_17_unique_implemented_recipes(self):
        entries = json.loads((TOOLS / 'catalog.json').read_text())['exercises']
        by_id = {e['exerciseId']: e for e in entries}
        self.assertEqual(len(batch_forms.TARGETS), 17)
        self.assertEqual(len(set(batch_forms.TARGETS)), 17)
        for eid in batch_forms.TARGETS:
            self.assertIsNotNone(family(by_id[eid]), eid)
        weighted = by_id['weighted_back_extension']
        self.assertGreater(weighted['parameters']['additionalWeight'], 0)
        self.assertEqual(weighted['animationId'], by_id['back_extension']['animationId'])
        self.assertEqual(weighted['status'], 'authored')
        self.assertFalse(weighted['review']['motion'])
        self.assertTrue((TOOLS.parents[1] / weighted['assetPath']).is_file())
        for eid in ('cable_row', 'rear_delt', 'ab_wheel', 'military_press', 'incline_fly_machine'):
            self.assertEqual('equipment reference not reviewed' in blockers(by_id[eid]),
                             not by_id[eid]['review']['equipmentReference'])

    def test_quality_review_does_not_publish_unverified_preview_assets(self):
        entries = json.loads((TOOLS / 'catalog.json').read_text())['exercises']
        self.assertFalse(any(e.get('previewEnabled') for e in entries))
        for entry in entries:
            if entry['status'] == 'verified' and entry['exerciseId'] not in ('bench_press', 'incline_dumbbell_press'):
                self.assertTrue(all(entry['review'].values()), entry['exerciseId'])

    def test_lower_body_recipes_share_planted_feet_without_changing_identity(self):
        by_id = {e['exerciseId']: e for e in json.loads((TOOLS / 'catalog.json').read_text())['exercises']}
        for eid in ('barbell_squat', 'front_squat', 'goblet_squat', 'romanian_deadlift', 'good_morning'):
            entry = by_id[eid]
            self.assertEqual(family(entry), 'lower_body')
            self.assertEqual(entry['category'], '\u811a')
            self.assertEqual(entry['recordType'], 'weightReps')
            self.assertTrue(entry['parameters']['plantedFeet'])
            self.assertFalse(entry['review']['productionRoute'])

    def test_new_families_route_through_full_loop_and_preview_without_export(self):
        from types import SimpleNamespace
        from unittest.mock import MagicMock
        from test_preview_only import method
        cases = [('row', 'cable_row', 'cable_row'),
                 ('pulldown', 'lat_pulldown', 'pulldown'),
                 ('lever_row', 'low_row', 'lever_row'),
                 ('overhead_press', 'barbell', 'vertical_press'),
                 ('overhead_press', 'dumbbell', 'vertical_press'),
                 ('curl', 'barbell', 'curl'),
                 ('curl', 'dumbbell', 'curl'),
                 ('pressdown', 'cable', 'pressdown'),
                 ('raise', 'dumbbell', 'raise'),
                 ('reverse_fly', 'fly_machine', 'reverse_fly'),
                 ('rollout', 'ab_wheel', 'rollout'),
                 ('fly', 'incline_fly_machine', 'decline_fly')]
        for animation, equipment, suffix in cases:
            with self.subTest(animation=animation):
                bpy = MagicMock()
                rig = SimpleNamespace(pose=SimpleNamespace(bones=MagicMock()), animation_data=None)
                plate = SimpleNamespace(name='Low row working plate', matrix_world=SimpleNamespace(translation=SimpleNamespace(z=.77)))
                obj = SimpleNamespace(id=animation, family=animation, equipment=equipment,
                    spec={'rangeOfMotion': 1, 'parameters': {'raisePlane': 15}}, scene=MagicMock(), rig=rig, metrics=[], moving=[],
                    fit_camera=Mock(), world=MagicMock(), row_stack=plate, stack=plate)
                if animation == 'lever_row':
                    obj.spec['parameters']['rebuildLowRowMachine'] = True
                    obj.scene.objects = [plate]
                setup, animate = Mock(), Mock(return_value=0.001)
                setattr(obj, 'setup_' + suffix, setup)
                setattr(obj, 'animate_' + suffix, animate)
                def preview(**kwargs):
                    for label in ('start', 'mid', 'end'):
                        (self.root / (animation + '_' + label + '.png')).write_bytes(b'mocked')
                obj.preview = preview
                ns = {'bpy': bpy, 'opt': SimpleNamespace(output=self.root, preview_only=True),
                      'json': json, 'FRAMES': 96, 'phase': lambda x: x, 'key': Mock(),
                      'math': SimpleNamespace(degrees=lambda _: 0), 'validate_resisted_pull': Mock()}
                with contextlib.redirect_stdout(io.StringIO()):
                    method('run', ns)(obj)
                setup.assert_called_once()
                self.assertEqual(animate.call_count, 97)
                if animation in ('row', 'pulldown', 'lever_row'):
                    ns['validate_resisted_pull'].assert_called_once_with(obj.metrics)
                    self.assertEqual(len(obj.metrics), 97)
                    self.assertTrue(all(m['workingPlateZ'] == [.77] for m in obj.metrics))
                else:
                    ns['validate_resisted_pull'].assert_not_called()
                bpy.ops.export_scene.gltf.assert_not_called()
                report = json.loads((self.root / (animation + '.preview.json')).read_text())
                self.assertFalse(report['productionExport'])
                self.assertFalse(report['reviewApproved'])

    def test_workspace_preview_is_explicit_and_confined(self):
        repo = self.root / 'repo'; repo.mkdir()
        output = repo / 'build/exercise_forms/previews'
        args = ['--ids', 'low_row', '--preview-only', '--workspace-preview', '--output', str(output)]
        self.assertEqual(parse_options(args, repo).output, output)
        for forbidden in (repo / 'assets', self.root / 'outside'):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                parse_options(args[:-1] + [str(forbidden)], repo)
        output.parent.mkdir(parents=True)
        output.symlink_to(self.root, target_is_directory=True)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parse_options(args, repo)

    def test_workspace_preview_never_enables_production_export(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parse_options(['--ids', 'low_row', '--workspace-preview', '--output', str(self.root)], self.root)

    def test_missing_blender_still_reports_every_target_without_writing_catalog(self):
        catalog = self.root / 'tool/exercise_forms/catalog.json'
        catalog.parent.mkdir(parents=True)
        entries = []
        for eid in batch_forms.TARGETS:
            spec = self.spec(eid)
            spec.update(exerciseName=eid, status='planned', assetPath=None)
            entries.append(spec)
        text = json.dumps({'exercises': entries})
        catalog.write_text(text)
        with patch.object(batch_forms, 'ROOT', self.root), patch.object(batch_forms, 'CATALOG', catalog), \
             patch.object(batch_forms, 'validate_bundle', return_value={}), \
             patch.object(batch_forms.shutil, 'which', return_value=None), \
             patch.object(batch_forms.subprocess, 'run') as process, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(batch_forms.main(['--mode', 'export']), 1)
        process.assert_not_called()
        self.assertEqual(catalog.read_text(), text)
        report = json.loads(next((self.root / 'build').rglob('report.json')).read_text())
        self.assertEqual(len(report['results']), 17)
        self.assertTrue(all(r['result'] == 'skipped' for r in report['results']))

    def test_workspace_scratch_symlink_cannot_escape(self):
        repo = self.root / 'repo'; repo.mkdir()
        catalog = repo / 'catalog.json'
        catalog.write_text(json.dumps({'exercises': [dict(self.spec('low_row'), exerciseName='Row', status='planned', assetPath=None)]}))
        (repo / 'build').symlink_to(self.root, target_is_directory=True)
        with patch.object(batch_forms, 'ROOT', repo), patch.object(batch_forms, 'CATALOG', catalog), \
             contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            batch_forms.main(['--ids', 'low_row'])


if __name__ == '__main__':
    unittest.main()
