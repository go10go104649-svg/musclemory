"""Packer regression tests. All assets are synthetic and stored in temp dirs."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / 'pack_assets.py'
SPEC = importlib.util.spec_from_file_location('form_packer', MODULE_PATH)
packer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packer)


def make_glb(path, parts=(b'ABCD',)):
    """Create a minimal single-buffer GLB, with correctly aligned chunks."""
    binary = b''
    views = []
    for part in parts:
        views.append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(part)})
        binary += part + b'\0' * (-len(part) % 4)
    doc = {
        'asset': {'version': '2.0'},
        'buffers': [{'byteLength': len(binary)}],
        'bufferViews': views,
        'extras': {'label': 'テスト種目'},
    }
    text = json.dumps(doc, ensure_ascii=False).encode('utf-8')
    text += b' ' * (-len(text) % 4)
    body = struct.pack('<II', len(text), 0x4e4f534a) + text
    body += struct.pack('<II', len(binary), 0x004e4942) + binary
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 12 + len(body)) + body)
    return doc


class PackAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'exports'
        self.source.mkdir()
        self.dest = self.root / 'assets/models/forms'
        self.chunks = self.root / 'assets/models/form_chunks'
        patch = mock.patch.multiple(packer, DEST=self.dest, CHUNKS=self.chunks)
        patch.start()
        self.addCleanup(patch.stop)

    def run_pack(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            packer.main([str(self.source), *args])
        return json.loads(output.getvalue())

    def recipe(self, name):
        return self.dest / (name + '.form.json')

    def chunk(self, data):
        return self.chunks / (hashlib.sha256(data).hexdigest() + '.bin')

    def reject_selection(self, selection):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit) as error:
                self.run_pack('--ids', selection, '--prune')
        self.assertEqual(error.exception.code, 2)
        self.assertFalse(self.dest.exists())
        self.assertFalse(self.chunks.exists())
        return stderr.getvalue()

    def test_default_still_packs_all_sources(self):
        make_glb(self.source / 'alpha.glb')
        make_glb(self.source / 'beta.glb', (b'BBBB',))
        report = self.run_pack()
        self.assertEqual(report['updated_recipes'], ['alpha', 'beta'])
        self.assertEqual(report['selected_recipes'], 2)
        self.assertEqual(report['recipes'], 2)
        self.assertEqual(report['unchanged_recipes'], 0)
        self.assertFalse(report['pruned'])

    def test_explicit_ids_do_not_read_unselected_source(self):
        make_glb(self.source / 'alpha.glb')
        (self.source / 'broken.glb').write_bytes(b'not a GLB')
        report = self.run_pack('--ids', 'alpha')
        self.assertEqual(report['selected_recipes'], 1)
        self.assertTrue(self.recipe('alpha').exists())
        self.assertFalse(self.recipe('broken').exists())

    def test_multiple_ids_accept_whitespace(self):
        for name in ('alpha', 'beta', 'gamma'):
            make_glb(self.source / (name + '.glb'))
        report = self.run_pack('--ids', ' beta, alpha ')
        self.assertEqual(report['updated_recipes'], ['beta', 'alpha'])
        self.assertFalse(self.recipe('gamma').exists())

    def test_missing_ids_fail_before_any_output(self):
        make_glb(self.source / 'alpha.glb')
        self.assertIn('missing.glb', self.reject_selection('alpha,missing'))

    def test_bad_selection_does_not_modify_existing_assets(self):
        make_glb(self.source / 'alpha.glb')
        self.run_pack()
        orphan = self.chunk(b'orphan')
        orphan.write_bytes(b'orphan')
        before = {p: p.read_bytes() for p in (self.root / 'assets').rglob('*') if p.is_file()}
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                self.run_pack('--ids', 'alpha,missing', '--prune')
        after = {p: p.read_bytes() for p in (self.root / 'assets').rglob('*') if p.is_file()}
        self.assertEqual(after, before)

    def test_empty_or_path_like_ids_are_rejected(self):
        for selection in ('', ' ', 'alpha,', '../alpha', '/tmp/alpha', 'alpha.glb'):
            with self.subTest(selection=selection):
                self.reject_selection(selection)

    def test_duplicate_ids_are_rejected(self):
        make_glb(self.source / 'alpha.glb')
        self.assertIn('duplicate', self.reject_selection('alpha,alpha'))

    def test_missing_source_directory_is_an_error(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                packer.main([str(self.source / 'missing'), '--prune'])
        self.assertEqual(error.exception.code, 2)
        self.assertFalse(self.dest.exists())

    def test_unchanged_recipes_and_chunks_are_not_rewritten(self):
        make_glb(self.source / 'alpha.glb')
        self.run_pack('--ids', 'alpha')
        files = [self.recipe('alpha'), self.chunk(b'ABCD')]
        for path in files:
            os.utime(path, ns=(1000000000, 1000000000))
        before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in files}
        report = self.run_pack('--ids', 'alpha')
        self.assertEqual(report['updated_recipes'], [])
        self.assertEqual(report['unchanged_recipes'], 1)
        for path, state in before.items():
            self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), state)

    def test_changed_source_updates_only_selected_recipe(self):
        for name in ('alpha', 'beta'):
            make_glb(self.source / (name + '.glb'))
        self.run_pack()
        beta = self.recipe('beta').read_bytes()
        make_glb(self.source / 'alpha.glb', (b'CCCC',))
        report = self.run_pack('--ids', 'alpha')
        self.assertEqual(report['updated_recipes'], ['alpha'])
        self.assertEqual(self.recipe('beta').read_bytes(), beta)
        self.assertEqual(self.chunk(b'CCCC').read_bytes(), b'CCCC')

    def test_recipe_bytes_and_binary_views_keep_the_legacy_format(self):
        parts = (b'abc', b'12345678', b'abc')
        doc = make_glb(self.source / 'alpha.glb', parts)
        report = self.run_pack()
        expected_doc = copy.deepcopy(doc)
        for view in expected_doc['bufferViews']:
            view.pop('byteOffset')
        expected_doc['buffers'] = [{'byteLength': 0}]
        refs = [{'path': 'assets/models/form_chunks/' + self.chunk(part).name,
                 'length': len(part)} for part in parts]
        expected = {'schemaVersion': 1, 'exerciseId': 'alpha',
                    'gltf': expected_doc, 'chunks': refs}
        self.assertEqual(self.recipe('alpha').read_text(encoding='utf-8'),
                         json.dumps(expected, ensure_ascii=False, separators=(',', ':')))
        self.assertEqual([self.chunk(part).read_bytes() for part in parts], list(parts))
        self.assertEqual(report['unique_chunks'], 2)

    def test_prune_preserves_unselected_references_and_non_hash_files(self):
        make_glb(self.source / 'alpha.glb', (b'COMMON00', b'AAAA'))
        make_glb(self.source / 'beta.glb', (b'COMMON00', b'BBBB'))
        self.run_pack()
        beta_before = self.recipe('beta').read_bytes()
        note = self.chunks / 'manual.bin'
        note.write_bytes(b'do not delete')
        orphan = self.chunk(b'orphan')
        orphan.write_bytes(b'orphan')
        make_glb(self.source / 'alpha.glb', (b'CCCC',))
        report = self.run_pack('--ids', 'alpha', '--prune')
        self.assertEqual(report['orphan_bytes'], len(b'AAAA') + len(b'orphan'))
        self.assertEqual(self.recipe('beta').read_bytes(), beta_before)
        for data in (b'COMMON00', b'BBBB', b'CCCC'):
            self.assertEqual(self.chunk(data).read_bytes(), data)
        self.assertFalse(self.chunk(b'AAAA').exists())
        self.assertFalse(orphan.exists())
        self.assertTrue(note.exists())

    def test_orphans_remain_without_prune(self):
        make_glb(self.source / 'alpha.glb')
        self.run_pack()
        orphan = self.chunk(b'orphan')
        orphan.write_bytes(b'orphan')
        report = self.run_pack('--ids', 'alpha')
        self.assertEqual(report['orphan_bytes'], 6)
        self.assertTrue(orphan.exists())

    def test_corrupt_selected_chunk_still_fails(self):
        make_glb(self.source / 'alpha.glb')
        self.run_pack()
        self.chunk(b'ABCD').write_bytes(b'FAIL')
        with self.assertRaisesRegex(AssertionError, 'Corrupt shared chunk'):
            self.run_pack('--ids', 'alpha')

    def test_corrupt_unselected_chunk_blocks_pruning(self):
        make_glb(self.source / 'alpha.glb')
        make_glb(self.source / 'beta.glb', (b'BBBB',))
        self.run_pack()
        self.chunk(b'BBBB').write_bytes(b'FAIL')
        orphan = self.chunk(b'orphan')
        orphan.write_bytes(b'orphan')
        with self.assertRaisesRegex(AssertionError, 'Corrupt bundle chunk'):
            self.run_pack('--ids', 'alpha', '--prune')
        self.assertTrue(orphan.exists())

    def test_empty_existing_source_can_validate_bundle_without_packing(self):
        make_glb(self.source / 'alpha.glb')
        self.run_pack()
        (self.source / 'alpha.glb').unlink()
        report = self.run_pack()
        self.assertEqual(report['selected_recipes'], 0)
        self.assertEqual(report['recipes'], 1)
        self.assertEqual(report['updated_recipes'], [])

    def test_pack_keeps_its_original_size_return_value(self):
        path = self.source / 'alpha.glb'
        make_glb(path)
        self.dest.mkdir(parents=True)
        self.chunks.mkdir(parents=True)
        self.assertEqual(packer.pack(path, 'alpha'), path.stat().st_size)

    def test_command_line_works_in_an_isolated_project(self):
        script = self.root / 'tool/exercise_forms/pack_assets.py'
        script.parent.mkdir(parents=True)
        script.write_bytes(MODULE_PATH.read_bytes())
        make_glb(self.source / 'alpha.glb')
        result = subprocess.run(
            [sys.executable, str(script), str(self.source), '--ids', 'alpha'],
            capture_output=True, text=True, check=True,
        )
        self.assertEqual(json.loads(result.stdout)['updated_recipes'], ['alpha'])
        self.assertEqual(result.stderr, '')


if __name__ == '__main__':
    unittest.main()
