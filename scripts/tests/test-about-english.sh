#!/usr/bin/env bash
# Fail closed on changes to the reviewed About source closure.
set -euo pipefail
python3 -B - "$(dirname "$0")/../.." <<'PY'
from pathlib import Path
import hashlib
import sys

# Reviewed English About source closure at 76a24e9, plus the version and sponsor
# button changes and the menu texts of 1.2.1, with the grey menu bar notice keys
# removed (only the TextKey enum of Localization.swift changes; the Localizer and
# the English About path stay the same). Do not regenerate automatically:
# changing any digest requires reviewing the entire About text path again.
EXPECTED = {
    "Sources/TopNV/AboutTitleFont.swift":
        "2f5d9ad11f78953ff4fb76929d1b71b42d0c61a93489d4f64eb00759c7aafc27",
    "Sources/TopNV/AboutView.swift":
        "5fdeed5f56f1ff94a4c6293505ed03c42d91fb4b311742fba0aa33127dcb16a0",
    "Sources/TopNV/AboutWindowController.swift":
        "38cece2ee98b7d89ed7a0f94ab5884cb4bdcb2f04d07a11ce1272ffe6359d6a7",
    # Not matched by the About* globs below, so listed here: the sponsor
    # button style, MonoPods' CoffeeButtonStyle.swift at d5517ff verbatim.
    "Sources/TopNV/CoffeeButtonStyle.swift":
        "be5c7fe2991986468abadd9ac1696b4d10be8200c4e4e504ed74997d3c67a741",
    "Sources/TopNVCore/AboutInformation.swift":
        "718a46794d2c9c649705b3ae6a9e679ebb72ea339872ae5e3b0cb8d0a20f4710",
    "Sources/TopNVCore/AboutText.swift":
        "47dc5b453926e3b060e86391e56f2dc68a3e1ff5bb29caf5acaa9f1c73c4433d",
    "Sources/TopNVCore/AppVersion.swift":
        "ace8d64174babf5a40915aa7132bde50dd3f329f92cf38459e204875e2618d1b",
    "Sources/TopNVCore/Localization.swift":
        "9f2324f7aea4fa075c802f6b8980fc7febdd348d56d44de312d803a650ef1ab3",
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
    sys.exit("English About: review About text paths before updating the baseline:\n"
             + "\n".join(problems))

# Positive case: the reviewed sources, including Text(verbatim:), pass unchanged.
if violations(dict(sources)):
    raise RuntimeError("English About positive case rejected")

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
        mutated[name] += ("\nprivate let aboutRegression = " + lookup + "\n").encode()
        if violations(mutated) != [name]:
            raise RuntimeError(f"English About missed {lookup} in {name}")
    missing = dict(sources)
    del missing[name]
    if violations(missing) != [name]:
        raise RuntimeError(f"English About missed removed source {name}")

extra = "Sources/TopNV/AboutExtra.swift"
if violations({**sources, extra: b"let title = translatedAboutTitle()\n"}) != [extra]:
    raise RuntimeError("English About missed an added About source")

print(f"PASS English About: {len(EXPECTED)} sources; positive, "
      f"{len(EXPECTED) * len(lookups)} lookup mutations, missing/extra cases")
PY
