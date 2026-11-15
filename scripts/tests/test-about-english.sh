#!/usr/bin/env bash
# D-35: fail closed on changes to the reviewed About source closure.
set -euo pipefail
python3 -B - "$(dirname "$0")/../.." <<'PY'
from pathlib import Path
import hashlib
import sys

# Reviewed D-35 source closure at 76a24e9. Do not regenerate automatically:
# changing any digest requires reviewing the entire About text path again.
EXPECTED = {
    "Sources/TopNV/AboutTitleFont.swift":
        "2f5d9ad11f78953ff4fb76929d1b71b42d0c61a93489d4f64eb00759c7aafc27",
    "Sources/TopNV/AboutView.swift":
        "5147c6a2346d4d5616dc89d6956168b8eb3eb894655b858c70c2310ef5d2098e",
    "Sources/TopNV/AboutWindowController.swift":
        "12625a3cb72d7ae1aa04d581ffcf4a628e848ea0a8b70e797572987caa0ec932",
    "Sources/TopNVCore/AboutInformation.swift":
        "5ba62e31e18ce5b5b7162e21f1c1d8f0b2a036b8a846a431084f98bf039f213c",
    "Sources/TopNVCore/AboutText.swift":
        "d9f8dfca130fd711430f5763e06e2207334f5b34526bc856b387b08bee7c859e",
    "Sources/TopNVCore/AppVersion.swift":
        "a67e0af60c4b3840d5914d55c2d172e931e50df3e9670d9779f35205b3401697",
    "Sources/TopNVCore/Localization.swift":
        "0cfae3aa7a65807f0277f4e23c025d2b3b7dd5fd697382de426486ef83b2d226",
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
