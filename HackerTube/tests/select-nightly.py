import json
import os
import re
import subprocess
from datetime import datetime


def api(path, **parameters):
    command = ['gh', 'api', '--method', 'GET', path]
    for name, value in parameters.items():
        command.extend(['--raw-field', f'{name}={value}'])
    return json.loads(subprocess.check_output(command, timeout=30))


def previous_nightly(current, actions):
    cutoff = datetime.fromisoformat(current['created_at'])
    workflow = current['workflow_id']
    branch = current['head_branch']
    history = api(f'{actions}/workflows/{workflow}/runs', branch=branch, event='schedule',
                  status='completed', created=f"<{current['created_at']}", per_page=20)['workflow_runs']
    if not isinstance(history, list):
        raise SystemExit('Invalid nightly workflow history')
    for run in sorted(history, key=lambda run: run['run_number'], reverse=True):
        if (run['id'] == current['id'] or run['run_number'] >= current['run_number']
                or run['workflow_id'] != workflow or run['event'] != 'schedule'
                or run['head_branch'] != branch or run['status'] != 'completed'
                or datetime.fromisoformat(run['updated_at']) >= cutoff):
            continue
        # A successful preflight-only run inherits proof of completion at the same SHA.
        if run['conclusion'] == 'success':
            return run
        if run['conclusion'] == 'failure':
            jobs = api(f"{actions}/runs/{run['id']}/attempts/{run['run_attempt']}/jobs")['jobs']
            if not isinstance(jobs, list):
                raise SystemExit('Invalid jobs for the earlier nightly run')
            if any(step['name'] == 'Both full fixture launches reached a result'
                   and step['conclusion'] == 'success' for job in jobs for step in (job['steps'] or [])):
                return run
    return None


def main():
    sha = os.environ['GITHUB_SHA']
    branch = os.environ['GITHUB_REF_NAME']
    run_id = int(os.environ['GITHUB_RUN_ID'])
    actions = f"repos/{os.environ['GITHUB_REPOSITORY']}/actions"
    current = api(f'{actions}/runs/{run_id}')
    if (not re.fullmatch('[0-9a-f]{40}', sha) or current['id'] != run_id
            or current['head_sha'] != sha or current['head_branch'] != branch
            or current['event'] != 'schedule'):
        raise SystemExit('Scheduled run metadata does not match this job')

    previous = previous_nightly(current, actions)
    if previous and not re.fullmatch('[0-9a-f]{40}', previous['head_sha']):
        raise SystemExit('Invalid SHA for the earlier nightly run')
    changed = previous is None or previous['head_sha'] != sha
    print('Run the full fixture' if changed else 'Skip the full fixture: commit already checked')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'run={str(changed).lower()}\n')


if __name__ == '__main__':
    main()
