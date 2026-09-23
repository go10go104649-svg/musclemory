"""Offline batch for the requested 17 forms. Default: report, never publish.

All scratch output stays in ignored build/exercise_forms. No downloads, devices,
package operations or Git mutations. Export only missing assets by default.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from batch_support import blockers, family

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'tool/exercise_forms/catalog.json'
TARGETS = (
    'incline_press_machine', 'decline_fly_machine', 'decline_press_machine',
    'mag_narrow', 'mag_medium', 'mag_wide', 'dy_row', 'low_row', 'linear_row',
    'high_row', 'cable_row', 'assisted_chin_up', 'weighted_back_extension',
    'rear_delt', 'military_press', 'ab_wheel', 'incline_fly_machine',
)


def validate_bundle(root=ROOT):
    """Validate ALL recipes, including chunks shared with untouched scenes."""
    checked = set()
    recipes = sorted((root / 'assets/models/forms').glob('*.form.json'))
    for path in recipes:
        recipe = json.loads(path.read_text())
        assert recipe['schemaVersion'] == 1 and path.name == recipe['exerciseId'] + '.form.json', path
        doc, chunks = recipe['gltf'], recipe['chunks']
        assert len(doc['bufferViews']) == len(chunks), path
        assert doc.get('animations') and doc.get('skins') and doc.get('meshes'), path
        for view, chunk in zip(doc['bufferViews'], chunks):
            name = chunk['path']
            target = (root / name).resolve()
            assert target.parent == (root / 'assets/models/form_chunks').resolve(), name
            assert view['byteLength'] == chunk['length'] == target.stat().st_size, name
            if name not in checked:
                assert target.name == hashlib.sha256(target.read_bytes()).hexdigest() + '.bin', name
                checked.add(name)
        for accessor in doc['accessors']:
            if 'bufferView' not in accessor:
                continue
            view = doc['bufferViews'][accessor['bufferView']]
            sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
            counts = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
            element = sizes[accessor['componentType']] * counts[accessor['type']]
            size = max(0, accessor['count'] - 1) * view.get('byteStride', element) + element
            assert accessor.get('byteOffset', 0) + size <= view['byteLength'], path
    return {'recipes': len(recipes), 'uniqueChunks': len(checked),
            'bytes': sum((root / p).stat().st_size for p in checked) + sum(p.stat().st_size for p in recipes)}


def plan(entries, blender):
    return [dict(exerciseId=e['exerciseId'], name=e['exerciseName'], family=family(e),
                 status=e['status'], assetExists=bool(e['assetPath'] and (ROOT / e['assetPath']).is_file()),
                 blockers=blockers(e) + ([] if blender else ['Blender executable unavailable']),
                 unchecked=[k for k in ('staticPose', 'motion', 'android', 'ios', 'productionRoute')
                            if not e.get('review', {}).get(k)]) for e in entries]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=('check', 'preview', 'export'), default='check')
    parser.add_argument('--ids', default=','.join(TARGETS))
    parser.add_argument('--blender', help='Existing installed Blender executable; never downloaded')
    parser.add_argument('--unreviewed-draft', action='store_true', help='Explicit offline drafts; retain failed evidence checks and unpublished status')
    parser.add_argument('--rebuild', action='store_true', help='Explicitly regenerate existing selected assets')
    args = parser.parse_args(argv)
    ids = [value.strip() for value in args.ids.split(',')]
    if not ids or any(not value for value in ids) or len(ids) != len(set(ids)):
        parser.error('--ids must contain unique nonempty IDs')
    catalog_text = CATALOG.read_text()
    catalog = json.loads(catalog_text)
    by_id = {e['exerciseId']: e for e in catalog['exercises']}
    if set(ids) - by_id.keys():
        parser.error('Unknown IDs: ' + ','.join(sorted(set(ids) - by_id.keys())))
    entries = [by_id[eid] for eid in ids]
    blender = shutil.which(args.blender or 'blender') or (shutil.which('Blender') if not args.blender else None)
    scratch = ROOT / 'build/exercise_forms'
    if scratch.resolve() != scratch:
        parser.error('Scratch directory must not escape the repository through symlinks')
    scratch.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='batch-', dir=scratch))
    report = {'mode': args.mode, 'entries': plan(entries, blender), 'bundle': validate_bundle(),
              'results': [], 'output': str(output), 'reviewApproved': False}
    if args.mode != 'check':
        groups = defaultdict(list)
        for e in entries:
            if args.mode == 'export' and not args.rebuild and e['assetPath'] and (ROOT / e['assetPath']).is_file():
                report['results'].append(dict(exerciseId=e['exerciseId'], result='preserved'))
            elif blockers(e, args.unreviewed_draft) or not blender:
                report['results'].append(dict(exerciseId=e['exerciseId'], result='skipped',
                    reasons=blockers(e, args.unreviewed_draft) + ([] if blender else ['Blender executable unavailable'])))
            else:
                groups[family(e)].append(e['exerciseId'])
        for group, selected in groups.items():
            destination = output / group
            command = [blender, '--background', '--factory-startup', '--python-exit-code', '1',
                       '--python', str(ROOT / 'tool/exercise_forms/author_forms.py'), '--',
                       '--ids', ','.join(selected), '--output', str(destination), '--continue-on-error']
            if args.unreviewed_draft:
                command += ['--unreviewed-draft']
            if args.mode == 'preview':
                command += ['--preview-only', '--workspace-preview']
            runtime = output / 'runtime'
            runtime.mkdir(exist_ok=True)
            env = dict(os.environ, TMPDIR=str(runtime), PYTHONDONTWRITEBYTECODE='1',
                       BLENDER_USER_CONFIG=str(runtime / 'config'),
                       BLENDER_USER_EXTENSIONS=str(runtime / 'extensions'))
            try:
                with (output / (group + '.log')).open('w') as log:
                    completed = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
            except OSError as error:
                report['results'].extend(dict(exerciseId=eid, result='failed', reasons=[str(error)]) for eid in selected)
                continue
            reports = list(destination.rglob('batch-results.json')) if destination.exists() else []
            results = json.loads(reports[0].read_text()) if len(reports) == 1 else []
            indexed = {r['exerciseId']: r for r in results}
            for eid in selected:
                report['results'].append(indexed.get(eid, dict(exerciseId=eid, result='failed',
                    reasons=[f'No completion report; Blender exit {completed.returncode}'])))
            successful = [eid for eid in selected if indexed.get(eid, {}).get('result') == 'generated']
            if args.mode == 'export' and successful:
                try:
                    # Only this fresh invocation's successful scenes can be packed.
                    if CATALOG.read_text() != catalog_text:
                        raise RuntimeError('Catalog changed during generation; refusing to overwrite concurrent edits')
                    cameras = {eid: json.loads((destination / (eid + '.camera.json')).read_text()) for eid in successful}
                    subprocess.run([sys.executable, '-B', str(ROOT / 'tool/exercise_forms/pack_assets.py'),
                                    str(destination), '--ids', ','.join(successful)], cwd=ROOT, check=True)
                    for eid in successful:
                        camera = cameras[eid]
                        entry = by_id[eid]
                        entry.update(camera, status='authored', assetPath=f'assets/models/forms/{eid}.form.json')
                        entry.pop('previewEnabled', None)
                        for check in ('staticPose', 'motion', 'android', 'ios', 'productionRoute'):
                            entry['review'][check] = False
                    catalog_text = json.dumps(catalog, ensure_ascii=False, indent=2) + '\n'
                    CATALOG.write_text(catalog_text)
                    subprocess.run([sys.executable, '-B', str(ROOT / 'tool/exercise_forms/generate_catalog.py')], cwd=ROOT, check=True)
                except Exception as error:
                    for row in report['results']:
                        if row['exerciseId'] in successful:
                            row.update(result='failed', reasons=[f'Packaging/catalog update: {error}'])
        report['bundle'] = validate_bundle()
        report['entries'] = plan(entries, blender)
    (output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    incomplete = any(r['result'] in ('failed', 'skipped') for r in report['results'])
    if args.mode == 'check':
        incomplete = any(row['blockers'] or row['unchecked'] or not row['assetExists'] for row in report['entries'])
    return 1 if incomplete else 0


if __name__ == '__main__':
    raise SystemExit(main())
