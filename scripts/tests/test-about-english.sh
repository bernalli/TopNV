#!/usr/bin/env bash
# D-35: fail closed on changes to the reviewed About source closure.
set -euo pipefail
python3 -B - "$(dirname "$0")/../.." <<'PY'
from pathlib import Path
import hashlib
import sys

# Reviewed D-35 source closure at 76a24e9, plus the D-36 version and sponsor
# button changes. Do not regenerate automatically: changing any digest
# requires reviewing the entire About text path again.
EXPECTED = {
    "Sources/TopNV/AboutTitleFont.swift":
        "2f5d9ad11f78953ff4fb76929d1b71b42d0c61a93489d4f64eb00759c7aafc27",
    "Sources/TopNV/AboutView.swift":
        "9bc2c6765ecc88ddcc7c78812d169ab24dd7bc44318b080d531a66b678a76286",
    "Sources/TopNV/AboutWindowController.swift":
        "12625a3cb72d7ae1aa04d581ffcf4a628e848ea0a8b70e797572987caa0ec932",
    # Not matched by the About* globs below, so listed here: the sponsor
    # button style, MonoPods' CoffeeButtonStyle.swift at d5517ff verbatim.
    "Sources/TopNV/CoffeeButtonStyle.swift":
        "be5c7fe2991986468abadd9ac1696b4d10be8200c4e4e504ed74997d3c67a741",
    "Sources/TopNVCore/AboutInformation.swift":
        "718a46794d2c9c649705b3ae6a9e679ebb72ea339872ae5e3b0cb8d0a20f4710",
    "Sources/TopNVCore/AboutText.swift":
        "d9f8dfca130fd711430f5763e06e2207334f5b34526bc856b387b08bee7c859e",
    "Sources/TopNVCore/AppVersion.swift":
        "38d6dad93ff0f741f228733f0f02ffdb0abed5bb4429b3641383095b9d1f4e70",
    "Sources/TopNVCore/Localization.swift":
        "aa7c7beb825b7ae2552325fd94309be15ed4463213257709e2f2e6f9bafffa89",
}


def violations(sources):
    changed = set(EXPECTED) ^ set(sources)
    for name in set(EXPECTED) & set(sources):
        if hashlib.sha256(sources[name]).hexdigest() != EXPECTED[name]:
            changed.add(name)
    return sorted(changed)


root = Path(sys.argv[1]).resolve()
names = set(EXPECTED)
for pattern in ("Sources/TopNV/About*.swift", "Sources/TopNVCore/About*.swift"):
    names.update(str(path.relative_to(root)) for path in root.glob(pattern))
sources = {
    name: (root / name).read_bytes()
    for name in names if (root / name).is_file()
}
problems = violations(sources)
if problems:
    sys.exit("D-35: review About text paths before updating the baseline:\n"
             + "\n".join(problems))

# Positive case: the reviewed sources, including Text(verbatim:), pass unchanged.
if violations(dict(sources)):
    raise RuntimeError("D-35 positive case rejected")

# Negative cases are source mutations in memory; no fixture files or app launch.
lookups = (
    'Bundle.main.localizedString(forKey: "About %@", value: nil, table: nil)',
    'bundle.localizedString(forKey: "About %@", value: nil, table: nil)',
    'NSLocalizedString("About %@", comment: "")',
    'String(localized: "About TopNV")',
    'Text("About TopNV")',
    'SwiftUI.Text("About TopNV")',
    'Text(LocalizedStringKey("About TopNV"))',
    'Localizer.main(.about, "TopNV")',
    'translatedAboutTitle()',
)
for name in EXPECTED:
    for lookup in lookups:
        mutated = dict(sources)
        mutated[name] += ("\nprivate let d35Regression = " + lookup + "\n").encode()
        if violations(mutated) != [name]:
            raise RuntimeError(f"D-35 missed {lookup} in {name}")
    missing = dict(sources)
    del missing[name]
    if violations(missing) != [name]:
        raise RuntimeError(f"D-35 missed removed source {name}")

extra = "Sources/TopNV/AboutExtra.swift"
if violations({**sources, extra: b"let title = translatedAboutTitle()\n"}) != [extra]:
    raise RuntimeError("D-35 missed an added About source")

print(f"PASS D-35: {len(EXPECTED)} sources; positive, "
      f"{len(EXPECTED) * len(lookups)} lookup mutations, missing/extra cases")
PY
