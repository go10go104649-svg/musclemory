"""Deduplicate GLB buffer views; keep source GLBs outside Flutter's asset bundle.

Each .form.json is a complete glTF document plus references to shared immutable
binary chunks. Runtime reassembles only the chosen scene as a normal GLB.
"""
import argparse, hashlib, json, struct, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/models/forms'
CHUNKS = ROOT / 'assets/models/form_chunks'

def unpack(data):
    magic, version, total = struct.unpack_from('<III', data)
    assert (magic, version, total) == (0x46546c67, 2, len(data))
    n, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4e4f534a
    doc = json.loads(data[20:20+n])
    size, kind = struct.unpack_from('<II', data, 20+n)
    assert kind == 0x004e4942
    return doc, data[28+n:28+n+size]

def pack(path, exercise_id, changed_ids=None):
    doc, binary = unpack(path.read_bytes())
    assert len(doc['buffers']) == 1 and 'uri' not in doc['buffers'][0]
    refs = []
    for view in doc['bufferViews']:
        offset = view.get('byteOffset', 0)
        chunk = binary[offset:offset + view['byteLength']]
        assert len(chunk) == view['byteLength']
        digest = hashlib.sha256(chunk).hexdigest()
        dest = CHUNKS / (digest + '.bin')
        if not dest.exists(): dest.write_bytes(chunk)
        else: assert dest.read_bytes() == chunk, f'Corrupt shared chunk: {dest.name}'
        refs.append({'path': f'assets/models/form_chunks/{digest}.bin', 'length': len(chunk)})
        view['buffer'] = 0
        view.pop('byteOffset', None)
    doc['buffers'] = [{'byteLength': 0}]
    result = {'schemaVersion': 1, 'exerciseId': exercise_id, 'gltf': doc, 'chunks': refs}
    target = DEST / (exercise_id + '.form.json')
    text = json.dumps(result, ensure_ascii=False, separators=(',', ':'))
    # Validate source/chunks every time, but do not rewrite an identical recipe.
    if not target.exists() or target.read_text(encoding='utf-8') != text:
        target.write_text(text, encoding='utf-8')
        if changed_ids is not None:
            changed_ids.append(exercise_id)
    return path.stat().st_size

def select_sources(source, ids=None):
    """Validate an explicit selection before creating or modifying outputs."""
    if not source.is_dir():
        raise ValueError(f'Source directory does not exist: {source}')
    if ids is None:
        return sorted(source.glob('*.glb'))
    names = [name.strip() for name in ids.split(',')]
    if not names or any(not re.fullmatch(r'[A-Za-z0-9_-]+', name) for name in names):
        raise ValueError('--ids requires comma-separated exercise IDs, not paths')
    if len(names) != len(set(names)):
        raise ValueError('--ids must not contain duplicate exercise IDs')
    paths = [source / (name + '.glb') for name in names]
    missing = [path.name for path in paths if not path.is_file()]
    if missing:
        raise ValueError('Missing selected GLBs: ' + ', '.join(missing))
    return paths


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--ids', help='Pack only these comma-separated exercise IDs')
    parser.add_argument('--prune', action='store_true')
    args = parser.parse_args(argv)
    try:
        sources = select_sources(args.source, args.ids)
    except ValueError as error:
        parser.error(str(error))
    DEST.mkdir(parents=True, exist_ok=True)
    CHUNKS.mkdir(parents=True, exist_ok=True)
    changed_ids = []
    raw = sum(pack(source, source.stem, changed_ids) for source in sources)
    # Always include ALL recipes: unselected scenes may share these chunks.
    referenced={r['path'].split('/')[-1] for p in DEST.glob('*.form.json') for r in json.loads(p.read_text())['chunks']}
    for name in referenced:
        assert hashlib.sha256((CHUNKS/name).read_bytes()).hexdigest()+'.bin' == name, f'Corrupt bundle chunk: {name}'
    # Only generated, unreferenced content-addressed chunks can be pruned.
    orphaned=[p for p in CHUNKS.glob('*.bin') if re.fullmatch(r'[0-9a-f]{64}\.bin', p.name) and p.name not in referenced]
    orphan_bytes=sum(p.stat().st_size for p in orphaned)
    if args.prune:
        for p in orphaned:p.unlink()
    packed=sum((CHUNKS/p).stat().st_size for p in referenced)+sum(p.stat().st_size for p in DEST.glob('*.form.json'))
    print(json.dumps({
        'unpacked_source_bytes': raw,
        'packed_bundle_bytes': packed,
        'unique_chunks': len(referenced),
        'recipes': len(list(DEST.glob('*.form.json'))),
        'orphan_bytes': orphan_bytes,
        'pruned': args.prune,
        'selected_recipes': len(sources),
        'updated_recipes': changed_ids,
        'unchanged_recipes': len(sources) - len(changed_ids),
    }, indent=2))


if __name__ == '__main__':
    main()
