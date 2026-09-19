"""CLI/output isolation for author_forms; importable without Blender."""
import argparse
from pathlib import Path
import re
import tempfile


def parse_options(argv, root):
    parser = argparse.ArgumentParser()
    parser.add_argument('--ids', required=True)
    parser.add_argument('--output', type=Path, required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--preview', action='store_true')
    modes.add_argument('--preview-only', action='store_true',
                       help='Draft images only, in a fresh folder outside the repository')
    opt = parser.parse_args(argv)
    if opt.preview_only:
        names = [name.strip() for name in opt.ids.split(',')]
        if any(not re.fullmatch(r'[A-Za-z0-9_-]+', name) for name in names):
            parser.error('--ids requires comma-separated exercise IDs, not paths')
        if len(names) != len(set(names)):
            parser.error('--ids must not contain duplicates')
        opt.ids = ','.join(names)
        output, root = opt.output.resolve(), Path(root).resolve()
        if output == root or root in output.parents:
            parser.error('--preview-only output must be outside the repository')
        opt.output = output
    return opt


def prepare_output(opt):
    """Call only after validating every requested catalog entry."""
    opt.output.mkdir(parents=True, exist_ok=True)
    if opt.preview_only:
        # Unique per invocation: failures cannot leave stale images/exports
        # that a later run silently treats as fresh evidence.
        opt.output = Path(tempfile.mkdtemp(prefix='preview-', dir=opt.output))
    return opt.output
