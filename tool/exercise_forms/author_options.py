"""CLI/output isolation for author_forms; importable without Blender."""
import argparse
from pathlib import Path
import re
import tempfile


def parse_options(argv, root):
    parser = argparse.ArgumentParser()
    parser.add_argument('--ids', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--continue-on-error', action='store_true',
                        help='Record failures and continue other selected scenes; exit nonzero if incomplete')
    parser.add_argument('--workspace-preview', action='store_true',
                        help='Allow previews only under ignored build/exercise_forms inside this workspace')
    parser.add_argument('--unreviewed-draft', action='store_true',
                        help='Generate offline drafts without equipment evidence; never marks any review as passed')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--preview', action='store_true')
    modes.add_argument('--preview-only', action='store_true',
                       help='Draft images only, in a fresh folder outside the repository')
    opt = parser.parse_args(argv)
    if opt.workspace_preview and not opt.preview_only:
        parser.error('--workspace-preview requires --preview-only')
    if opt.preview_only:
        names = [name.strip() for name in opt.ids.split(',')]
        if any(not re.fullmatch(r'[A-Za-z0-9_-]+', name) for name in names):
            parser.error('--ids requires comma-separated exercise IDs, not paths')
        if len(names) != len(set(names)):
            parser.error('--ids must not contain duplicates')
        opt.ids = ','.join(names)
        output, root = opt.output.resolve(), Path(root).resolve()
        if opt.workspace_preview:
            allowed = root / 'build' / 'exercise_forms'
            if allowed.resolve() != allowed or not (output == allowed or allowed in output.parents):
                parser.error('--workspace-preview output must be inside build/exercise_forms without escaping symlinks')
        elif output == root or root in output.parents:
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
