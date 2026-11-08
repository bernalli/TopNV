#!/usr/bin/env bash
# Check workflow properties that the publisher simulation cannot observe.
set -euo pipefail
python3 - "$(cd "$(dirname "$0")/../.." && pwd)" <<'PY'
from pathlib import Path
import json, re, sys
root=Path(sys.argv[1])
release=(root/'.github/workflows/release.yml').read_text()
ci=(root/'.github/workflows/ci.yml').read_text()
steps=re.split(r'\n      - ',release)[1:]
def named(fragment):
    found=[i for i,s in enumerate(steps) if fragment in s]
    assert len(found)==1,fragment
    return found[0]
resolve=named('publish-release.sh resolve'); guard=named('run: scripts/require-signing-key.sh')
sign=named('run: scripts/sign-release.sh'); publish=named('publish-release.sh publish'); recover=named('publish-release.sh recover')
assert resolve<guard<sign<publish<recover
assert [i for i,s in enumerate(steps) if 'secrets.' in s]==[guard,sign]
assert release.count('secrets.')==2 and 'secrets.' not in ci
assert [i for i,s in enumerate(steps) if re.search(r'^\s+if:',s,re.M)]==[recover]
assert 'failure() || cancelled()' in steps[recover]
# Parse only the block-mapping/step-list YAML subset used by these workflows.
# Unsupported syntax fails closed; no optional YAML dependency is needed.
def workflow(text):
    def scalar(value):
        if value.startswith("'"):
            assert re.fullmatch(r"'(?:[^']|'')*'", value), 'unsupported quoted scalar'
            return value[1:-1].replace("''", "'")
        if value.startswith('"'):
            decoded = json.loads(value)
            assert isinstance(decoded, str), 'expected string'
            return decoded
        if value.startswith('['):
            assert value.endswith(']'), 'unsupported flow sequence'
            body = value[1:-1].strip()
            return [scalar(v.strip()) for v in body.split(',')] if body else []
        assert not value.startswith(('{', '}', ']', '&', '*', '!', '%', '@', '`'))
        assert not re.search(r':\s|\s#', value), 'unsupported plain scalar'
        return value

    lines = text.splitlines()
    tokens = []
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        assert '\t' not in line, 'unsupported YAML tab'
        indent = len(line) - len(line.lstrip(' '))
        body = line[indent:]
        if body.startswith('- '):
            tokens.append((indent, '-', None))
            indent += 2
            body = body[2:]
        match = re.fullmatch(r'([A-Za-z_][A-Za-z0-9_-]*):(?: +(.*))?', body)
        assert match, 'unsupported YAML structure: ' + body
        key, value = match.groups()
        if value and value.startswith(('|', '>')):
            assert re.fullmatch(r'[|>][+-]?', value), 'unsupported block header'
            content = []
            while i < len(lines):
                following = lines[i]
                if following.strip():
                    leading = following[:len(following) - len(following.lstrip())]
                    assert '\t' not in leading, 'unsupported YAML indentation'
                    if len(following) - len(following.lstrip(' ')) <= indent:
                        break
                content.append(following)
                i += 1
            # Folding/chomping cannot create a contiguous "${{" delimiter.
            # Keep the source text so every block style is checked identically.
            value = '\n'.join(content)
        elif value:
            value = scalar(value)
        else:
            value = None
        tokens.append((indent, key, value))

    def block(pos, indent):
        sequence = tokens[pos][1] == '-'
        result = [] if sequence else {}
        while pos < len(tokens) and tokens[pos][0] == indent:
            _, key, value = tokens[pos]
            pos += 1
            assert (key == '-') == sequence, 'mixed YAML collection'
            if value is None and pos < len(tokens) and tokens[pos][0] > indent:
                value, pos = block(pos, tokens[pos][0])
            assert pos == len(tokens) or tokens[pos][0] <= indent, 'unexpected YAML indentation'
            if sequence:
                result.append(value)
            else:
                assert key not in result, 'duplicate YAML key: ' + key
                result[key] = value
        return result, pos

    assert tokens and tokens[0][0] == 0, 'expected workflow mapping'
    document, end = block(0, 0)
    assert end == len(tokens) and isinstance(document, dict), 'invalid workflow'
    return document

def check_workflow(text, contents):
    document = workflow(text)
    assert document.get('permissions') == {'contents': contents}, 'workflow permissions'
    jobs = document.get('jobs')
    assert isinstance(jobs, dict) and jobs, 'expected jobs'
    for name, job in jobs.items():
        assert isinstance(job, dict), 'unsupported job: ' + name
        effective = job.get('permissions', document['permissions'])
        assert isinstance(effective, dict), 'permissions must be a mapping: ' + name
        if contents == 'read':
            assert all(v in ('read', 'none') for v in effective.values()), 'CI write permission: ' + name
        else:
            assert effective == {'contents': 'write'}, 'release permissions: ' + name
        job_steps = job.get('steps')
        assert isinstance(job_steps, list), 'expected job steps: ' + name
        for step in job_steps:
            assert isinstance(step, dict), 'expected step mapping'
            if 'run' in step:
                assert isinstance(step['run'], str), 'expected run string'
                assert '${{' not in step['run'], 'expression in shell text'

check_workflow(release, 'write')
check_workflow(ci, 'read')
assert 'cancel-in-progress: false' in release and 'pull_request_target' not in ci
for text in (release,ci):
    for action in re.findall(r'uses: (\S+)',text): assert re.fullmatch(r'[^@]+@[0-9a-f]{40}',action),action
print('PASS workflow guard order and secret scope')
PY
