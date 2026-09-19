"""Control-flow tests with Blender mocked; not rendering/geometry validation."""
import argparse
import ast
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import Mock, MagicMock

TOOLS = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('author_options', TOOLS / 'author_options.py')
options = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(options)
SOURCE = ast.parse((TOOLS / 'author_forms.py').read_text())
AUTHOR = next(node for node in SOURCE.body if isinstance(node, ast.ClassDef) and node.name == 'Author')


def method(name, namespace):
    node = copy.deepcopy(next(node for node in AUTHOR.body if node.name == name))
    exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
                 str(TOOLS / 'author_forms.py'), 'exec'), namespace)
    return namespace[name]


class PreviewOnlyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'repo'
        self.root.mkdir()
        self.output = Path(self.temp.name) / 'previews'

    def parse(self, *extra, output=None):
        return options.parse_options(['--ids', 'low_row', '--output',
                                      str(output or self.output), *extra], self.root)

    def test_default_is_original_export_without_preview(self):
        opt = self.parse()
        self.assertFalse(opt.preview_only)
        self.assertFalse(opt.preview)
        self.assertEqual(options.prepare_output(opt), self.output)

    def test_existing_preview_flag_remains_export_mode(self):
        opt = self.parse('--preview')
        self.assertTrue(opt.preview)
        self.assertFalse(opt.preview_only)

    def test_modes_are_mutually_exclusive(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.parse('--preview', '--preview-only')

    def test_draft_rejects_repository_and_children(self):
        for output in (self.root, self.root / 'assets/models', self.root / 'art/new'):
            with self.subTest(output=output):
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    self.parse('--preview-only', output=output)
        self.assertFalse((self.root / 'assets').exists())

    def test_draft_rejects_symlink_back_into_repository(self):
        link = self.output
        link.symlink_to(self.root, target_is_directory=True)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.parse('--preview-only')

    def test_draft_rejects_invalid_or_duplicate_ids(self):
        for ids in ('', '../row', 'low_row,', 'low_row,low_row'):
            with self.subTest(ids=ids):
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    self.parse('--preview-only', '--ids', ids)
        self.assertFalse(self.output.exists())

    def test_draft_normalizes_ids(self):
        self.assertEqual(self.parse('--preview-only', '--ids', ' low_row, dy_row ').ids,
                         'low_row,dy_row')

    def test_fresh_output_does_not_reuse_or_delete_old_exports(self):
        self.output.mkdir()
        old = self.output / 'low_row.glb'
        old.write_bytes(b'old production export')
        a = options.prepare_output(self.parse('--preview-only'))
        b = options.prepare_output(self.parse('--preview-only'))
        self.assertNotEqual(a, b)
        self.assertEqual(list(a.iterdir()), [])
        self.assertEqual(old.read_bytes(), b'old production export')

    def run_author(self, preview_only, preview=False, fail_motion=False, missing_image=False):
        opt = argparse.Namespace(output=self.output, preview_only=preview_only, preview=preview)
        options.prepare_output(opt)
        bpy = MagicMock()
        def export(**kwargs):
            Path(kwargs['filepath']).write_bytes(b'mocked GLB export')
        bpy.ops.export_scene.gltf.side_effect = export
        bpy.ops.wm.save_as_mainfile.side_effect = lambda **kw: Path(kw['filepath']).write_bytes(b'mocked blend')
        ns = {'opt': opt, 'bpy': bpy, 'json': json, 'FRAMES': 96,
              'phase': lambda x: x, 'key': Mock()}
        scene = types.SimpleNamespace(frame_set=Mock())
        rig = types.SimpleNamespace(pose=types.SimpleNamespace(bones=[object(), object()]),
                                    animation_data=None)
        obj = types.SimpleNamespace(id='low_row', family='lever_row', equipment='lever',
                                    spec={'rangeOfMotion': 1}, metrics=[], moving=[], rig=rig,
                                    scene=scene, setup_lever_row=Mock(),
                                    animate_lever_row=Mock(return_value=0.001))
        def camera():
            (opt.output / 'low_row.camera.json').write_text('{}')
        obj.fit_camera = Mock(side_effect=camera)
        def images(draft=False):
            labels = ('start', 'mid', 'end') if draft else ('top', 'bottom')
            for label in labels:
                if not (missing_image and label == 'mid'):
                    (opt.output / ('low_row_' + label + '.png')).write_bytes(b'mocked image')
        obj.preview = Mock(side_effect=images)
        if fail_motion:
            obj.animate_lever_row.side_effect = ValueError('Unreachable joint')
        run = method('run', ns)
        stdout = io.StringIO()
        try:
            with contextlib.redirect_stdout(stdout):
                run(obj)
        except Exception as error:
            return obj, opt, bpy, stdout.getvalue(), error
        return obj, opt, bpy, stdout.getvalue(), None

    def test_draft_keeps_97_motion_checks_but_never_exports(self):
        obj, opt, bpy, output, error = self.run_author(True)
        self.assertIsNone(error)
        self.assertEqual(obj.animate_lever_row.call_count, 97)
        obj.preview.assert_called_once_with(draft=True)
        bpy.ops.export_scene.gltf.assert_not_called()
        bpy.ops.wm.save_as_mainfile.assert_not_called()
        self.assertFalse(list(opt.output.glob('*.glb')))
        self.assertFalse(list(opt.output.glob('*.blend')))
        report = json.loads((opt.output / 'low_row.preview.json').read_text())
        self.assertFalse(report['reviewApproved'])
        self.assertFalse(report['productionExport'])
        self.assertEqual(report['frames'], [1, 24, 47])
        self.assertIn('motion loop', report['unchecked'])
        self.assertIn('PREVIEW_ONLY', output)
        self.assertNotIn('AUTHORED', output)

    def test_normal_export_retains_export_and_optional_blend(self):
        obj, opt, bpy, output, error = self.run_author(False, preview=True)
        self.assertIsNone(error)
        self.assertEqual(obj.animate_lever_row.call_count, 97)
        self.assertTrue((opt.output / 'low_row.glb').exists())
        self.assertTrue((opt.output / 'low_row.blend').exists())
        self.assertFalse((opt.output / 'low_row.preview.json').exists())
        obj.preview.assert_called_once_with()
        self.assertTrue(bpy.ops.export_scene.gltf.call_args.kwargs['export_force_sampling'])
        self.assertIn('AUTHORED', output)

    def test_normal_export_without_preview_does_not_render(self):
        obj, opt, bpy, _, error = self.run_author(False)
        self.assertIsNone(error)
        obj.preview.assert_not_called()
        bpy.ops.wm.save_as_mainfile.assert_not_called()
        self.assertTrue((opt.output / 'low_row.glb').exists())

    def test_motion_failure_never_writes_success_report(self):
        _, opt, bpy, output, error = self.run_author(True, fail_motion=True)
        self.assertIsInstance(error, ValueError)
        self.assertFalse((opt.output / 'low_row.preview.json').exists())
        bpy.ops.export_scene.gltf.assert_not_called()
        self.assertEqual(output, '')

    def test_incomplete_render_never_writes_success_report(self):
        _, opt, bpy, output, error = self.run_author(True, missing_image=True)
        self.assertIsInstance(error, RuntimeError)
        self.assertFalse((opt.output / 'low_row.preview.json').exists())
        self.assertEqual(output, '')

    def test_actual_preview_method_selects_draft_or_legacy_frames(self):
        for draft, expected_frames, pixels, samples in ((True, [1, 24, 47], 420, 6),
                                                       (False, [1, 47], 700, 12)):
            with self.subTest(draft=draft):
                scene = MagicMock()
                ns = {'bpy': MagicMock(), 'opt': types.SimpleNamespace(output=self.output),
                      'aim': Mock()}
                obj = types.SimpleNamespace(id='low_row', scene=scene,
                    spec={'cameraAngle': [1, 2, 3], 'cameraTarget': [0, 0, 0], 'cameraScale': 2})
                method('preview', ns)(obj, draft=draft)
                self.assertEqual([call.args[0] for call in scene.frame_set.call_args_list], expected_frames)
                self.assertEqual(scene.render.resolution_x, pixels)
                self.assertEqual(scene.cycles.samples, samples)
                self.assertEqual(ns['bpy'].ops.render.render.call_count, len(expected_frames))

    def test_all_reference_checks_happen_before_output_or_authoring(self):
        start = next(i for i, n in enumerate(SOURCE.body)
                     if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
                     and n.targets[0].id == 'unknown')
        tail = ast.Module(body=copy.deepcopy(SOURCE.body[start:]), type_ignores=[])
        for ids in ('missing', 'low_row,dy_row'):
            prepare, author = Mock(), Mock()
            ns = {'opt': types.SimpleNamespace(ids=ids), 'prepare_output': prepare,
                  'Author': author, 'catalog': [
                      {'exerciseId': 'low_row', 'references': ['recorded'], 'review': {'equipmentReference': True}},
                      {'exerciseId': 'dy_row', 'references': [], 'review': {}},
                  ]}
            with self.assertRaises(ValueError):
                exec(compile(ast.fix_missing_locations(tail), 'preflight', 'exec'), ns)
            prepare.assert_not_called()
            author.assert_not_called()


if __name__ == '__main__':
    unittest.main()
