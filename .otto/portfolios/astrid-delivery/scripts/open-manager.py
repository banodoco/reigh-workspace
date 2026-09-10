"""Prepare one visible manager window. No launch unless --execute is supplied."""
import argparse
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time

PACKAGE = Path(__file__).resolve().parents[1]
ROOTS = {
    'database': 'Astrid/.otto/runs/runtime-database-clean-break-20260910',
    'generation': '.otto/runs/astrid-generation-path-alignment-20260910',
    'visualization': 'Astrid/.otto/runs/timeline-visualization-fixes-20260910',
    'render': 'Astrid/.otto/runs/runtime-render-path-reliability-20260910',
    'ephemeral': 'Astrid/.otto/runs/ephemeral-derived-artifact-lifecycle-20260910',
    'integration': '.otto/runs/astrid-integration-e2e-20260910',
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', choices=ROOTS)
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    workspace = args.workspace.resolve(strict=True)
    active_package = workspace / '.otto/portfolios/astrid-delivery'
    if args.execute and PACKAGE.resolve() != active_package.resolve():
        parser.error('Launch only from the canonical active portfolio root under --workspace; downloaded copies are reference inputs, not launch owners')
    if args.execute and not (active_package / 'run.yaml').is_file():
        parser.error('Initialize/recover the single active portfolio root before launch')
    root = workspace / ROOTS[args.project]
    if args.execute and not (root / 'run.yaml').is_file():
        parser.error('Initialize/recover the existing project run before launch; snapshot fallback is dry-run only')
    config = root / 'run.yaml'
    if not config.is_file():
        config = PACKAGE / 'handovers' / args.project / 'run.yaml'
    try:
        import yaml
    except ImportError:
        parser.error('PyYAML is needed to read run.yaml; use the manual CLI recipe without changing its configured role.')
    binding = yaml.safe_load(config.read_text())['roles']['coordinator']
    approved = yaml.safe_load((PACKAGE / 'handovers' / args.project / 'run.yaml').read_text())['roles']['coordinator']
    if binding != approved:
        message = 'Active manager binding differs from approved portable binding; delegate safe configuration reconciliation before launching (do not replace a live owner).'
        if args.execute:
            parser.error(message)
        print('WARNING: ' + message, file=sys.stderr)
    codex = shutil.which('codex')
    if not codex:
        parser.error('codex is not on PATH')
    prompt = (f'You are the {args.project} project manager. Read {PACKAGE / "START-HERE.md"}, '
              f'{PACKAGE / "assets/project-manager-message.md"}, and the {args.project} row in '
              f'{PACKAGE / "projects.md"}. Your intended existing run root is {root}. '
              'First report readiness and exact source in this same thread. Do not duplicate an existing owner. '
              'Honor the P7 integration gate and project role/review budgets; delegate only ready authorized work.')
    command = shlex.join([codex, '--no-alt-screen', '-C', str(workspace), '-m', binding['model'],
                          '-c', f'model_reasoning_effort={binding["reasoning"]}', prompt])
    print(command)
    if not args.execute:
        return
    if not shutil.which('osascript'):
        parser.error('Terminal AppleScript is unavailable; no launch performed')
    local = PACKAGE / 'local'
    local.mkdir(exist_ok=True)
    marker = local / f'{args.project}.launch.json'
    # O_EXCL via x mode: do not silently create a second owner after uncertainty.
    with marker.open('x') as out:
        json.dump({'project':args.project, 'root':str(root), 'launched_at':time.time(),
                   'state':'launch_requested', 'session_id':None}, out)
    script = '''on run argv
tell application "Terminal"
activate
set newTab to do script (item 1 of argv)
set custom title of newTab to (item 2 of argv)
end tell
end run'''
    subprocess.run(['osascript','-',command,f'Astrid portfolio — {args.project}'],
                   input=script, text=True, check=True)
    print('Window launch requested. Record actual thread UUID in local/managers.json after manager readiness; do not infer acceptance.')

if __name__ == '__main__':
    main()
