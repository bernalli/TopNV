#!/usr/bin/env bash
# Fails when a string literal reaches a visible-text API in the app sources: every visible
# text must come from the Localizer. The only literal allowed is the app name.
set -euo pipefail
python3 - "$(dirname "$0")/../.." <<'PY'
from pathlib import Path
import re
import sys

CALLS = re.compile(
    r'(?<![\w.])(?:Text|Label|Button|Toggle|Picker|Section|Menu|info)\s*\(|'
    r'\.(?:help|accessibilityLabel)\s*\(|'
    r'\b(?:messageText|informativeText)\s*=|'
    r'\baddButton\s*\(\s*withTitle\s*:|'
    r'(?<![\w.])title\s*:|'
    r'\.title\s*=(?!=)')
LABEL = re.compile(r'\s*[A-Za-z_]\w*\s*:(?!:)')
# The app name, and the empty title of a separator row.
ALLOWED = re.compile(r'\(*\s*(?:"TopNV"|"")\s*\)*')


def strip_comments(source):
    """Blank out comments, keeping strings and line numbers intact."""
    out, i, n = [], 0, len(source)
    while i < n:
        if source.startswith('"""', i):
            end = source.find('"""', i + 3)
            end = n if end < 0 else end + 3
            out.append(source[i:end]); i = end
        elif source[i] == '"':
            j = i + 1
            while j < n and source[j] not in '"\n':
                j += 2 if source[j] == '\\' else 1
            out.append(source[i:j + 1]); i = j + 1
        elif source.startswith('//', i):
            end = source.find('\n', i)
            end = n if end < 0 else end
            i = end
        elif source.startswith('/*', i):
            end = source.find('*/', i + 2)
            end = n if end < 0 else end + 2
            out.append(re.sub(r'[^\n]', ' ', source[i:end])); i = end
        else:
            out.append(source[i]); i += 1
    return ''.join(out)


def read_string(code, i):
    """End index of the string literal that starts at i (plain, multi-line or raw)."""
    if code.startswith('"""', i):
        end = code.find('"""', i + 3)
        return len(code) if end < 0 else end + 3
    if code.startswith('#"', i):
        end = code.find('"#', i + 2)
        return len(code) if end < 0 else end + 2
    j = i + 1
    while j < len(code) and code[j] not in '"\n':
        j += 2 if code[j] == '\\' else 1
    return j + 1


def argument(code, start, assignment):
    """The first argument/value and literals outside nested function calls."""
    label = LABEL.match(code, start)
    i = label.end() if label and not assignment else start
    while i < len(code) and code[i].isspace():
        i += 1
    begin, nesting, literals = i, [], []
    while i < len(code):
        c = code[i]
        if c == '"' or code.startswith('#"', i):
            end = read_string(code, i)
            if not any(nesting):
                literals.append(code[i:end])
            i = end
            continue
        if c in '([{':
            prefix = code[begin:i].rstrip()
            nesting.append(c == '(' and bool(re.search(r'[\w.)\]]$', prefix)))
        elif c in ')]}':
            if not nesting:
                break
            nesting.pop()
        elif not nesting and (c == ',' or (assignment and c in '\n;')):
            break
        i += 1
    return code[begin:i].strip(), literals


def violations(source):
    code = strip_comments(source)
    found = []
    for match in CALLS.finditer(code):
        text, literals = argument(code, match.end(), match.group(0).endswith('='))
        allowed_name = ALLOWED.fullmatch(text) is not None
        if literals and not allowed_name:
            found.append((code.count('\n', 0, match.start()) + 1, match.group(0), text))
    return found


cases = [
    ('Text("Hello")', True),
    ('Text ( "Hello" )', True),
    ('Text(("Hello"))', True),
    ('Text( ( "Hello" ) )', True),
    ('info(flag ? ("All") : ("Built-in"))', True),
    ('view.help ("Hello")', True),
    ('alert.addButton (withTitle: "Hello")', True),
    ('alert.messageText =\n  "Hello"', True),
    ('Label("Hide Notch", systemImage: "rectangle")', True),
    ('Button("Quit") { }', True),
    ('Toggle("Flag", isOn: $x)', True),
    ('Picker("Radius", selection: $r) {}', True),
    ('Section("Settings") {}', True),
    ('Menu("More") {}', True),
    ('info("Requires macOS 14 or Later")', True),
    ('view.help("Hint")', True),
    ('view.accessibilityLabel("Icon")', True),
    ('alert.messageText = "Title"', True),
    ('alert.informativeText="Body"', True),
    ('alert.addButton(withTitle: "OK")', True),
    ('Text(verbatim: "Hello")', True),
    ('Text(\n  "Hello")', True),
    ('Text("""\nHello\n""")', True),
    ('Text("Corner Radius: \\(value)")', True),
    ('Text("TopNV" + suffix)', True),
    ('Text(#"raw"#)', True),
    ('info(flag ? "All" : "Built-in")', True),
    ('Text(\n  verbatim:\n  "Hello")', True),
    ('Text(localizer(.hideNotch))', False),
    ('Text((localizer(.hideNotch)))', False),
    ('Text(("TopNV"))', False),
    ('Label(localizer(.details), systemImage: "info.circle")', False),
    ('alert.messageText = localizer(.updateQuestionTitle)', False),
    ('alert.addButton(withTitle: localizer(.dontCheck))', False),
    ('Section("TopNV") {}', False),
    ('Image(nsImage: icon).accessibilityLabel("TopNV")', False),
    ('Toggle(isOn: $settings.hideNotch) { Label(text, systemImage: "x") }', False),
    ('Image(systemName: "link")', False),
    ('// Text("comment")', False),
    ('/* Button("comment") */', False),
    ('MenuBarLabel(); myText("x")', False),
    ('NSMenu(title: "x")', True),
    ('MenuRow(id: "x", title: "Hello", symbol: nil, kind: .info)', True),
    ('item.title = "Hello"', True),
    ('item.title="Hello"', True),
    ('MenuRow(id: "x", title: localizer(.details), symbol: "info.circle", kind: .info)', False),
    ('title: localizer(.details)', False),
    ('menu.addItem(withTitle: title, action: nil, keyEquivalent: "")', False),
    ('MenuRow(id: "s", title: "", symbol: nil, kind: .separator)', False),
    ('if item.title == "Hello" { }', False),
    ('NSMenu(title: row.title)', False),
]
for fragment, red in cases:
    assert bool(violations(fragment)) == red, (fragment, violations(fragment))

# Direct title literals remain violations when truncated, duplicated or reordered.
from itertools import permutations

for prefix in ('item.title = ', 'NSMenu(title: ', 'MenuRow(id: "x", title: '):
    value = prefix + '"Unlocalized text"'
    for end in range(len(prefix) + 1, len(value)):
        assert violations(value[:end]), value[:end]

fragments = [
    'item.title = "Hello"',
    'item.title = localizer(.details)',
    'item.title = ""',
]
for order in permutations(fragments):
    assert len(violations("\n".join(order))) == 1, order
assert len(violations("\n".join([fragments[0]] * 3))) == 3

root = Path(sys.argv[1])
problems = []
sources = sorted((root / 'Sources/TopNV').glob('*.swift')) + [root / 'Sources/TopNVCore/MenuLayout.swift']
for path in sources:
    for line, call, literal in violations(path.read_text()):
        problems.append(f'{path.relative_to(root)}:{line}: literal {literal} reaches {call}')
if problems:
    print('\n'.join(problems), file=sys.stderr)
    sys.exit(1)
print('PASS visible texts come from the Localizer')
PY
