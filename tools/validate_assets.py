#!/usr/bin/env python3
"""Validate VOWED's asset licence register.

Enforces the rule from docs/ASSET_LICENSES.md:

    An asset with no licence record is treated as absent.

Two directions are checked, because either one alone is insufficient:

  1. Every entry in assets/licenses/assets.json is complete, well-formed, uses
     an allowed licence, is cleared for commercial use, and points at files
     that actually exist.
  2. Every asset file present under assets/ is claimed by some entry. This is
     the direction that catches the real failure — a file dropped into the
     project and forgotten, which is exactly what makes a finished game
     unshippable at release time.

Run:  python3 tools/validate_assets.py
Exit: 0 clean, 1 problems found.
"""

from __future__ import annotations

import json
import sys
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REGISTER = REPO / "assets" / "licenses" / "assets.json"
ASSET_ROOT = REPO / "assets"

# Licences cleared for a commercial proprietary release.
ALLOWED_LICENSES = {
    "CC0-1.0", "CC0", "Public Domain", "Unlicense",
    "CC-BY-4.0", "CC-BY-3.0",
    "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause",
    "OFL-1.1",
}

# Explicitly incompatible — named so the failure message can say *why*.
REJECTED_LICENSES = {
    "CC-BY-SA-4.0": "share-alike is incompatible with a proprietary game",
    "CC-BY-SA-3.0": "share-alike is incompatible with a proprietary game",
    "CC-BY-NC-4.0": "non-commercial is incompatible with a commercial release",
    "CC-BY-NC-SA-4.0": "non-commercial and share-alike",
    "GPL-3.0": "copyleft is incompatible with a proprietary game",
    "GPL-2.0": "copyleft is incompatible with a proprietary game",
}

REQUIRED_FIELDS = [
    "id", "name", "creator", "source", "url", "license", "license_url",
    "acquired", "files", "modifications", "attribution_required",
    "commercial_use",
]

# Files under assets/ that are not themselves licensable assets.
IGNORED_NAMES = {".gitkeep", ".DS_Store", "assets.json", "README.md"}
IGNORED_SUFFIXES = {".md", ".json", ".import"}


def fail(problems: list[str], msg: str) -> None:
    problems.append(msg)


def validate_entries(data: dict, problems: list[str]) -> set[Path]:
    """Check each register entry. Returns the set of claimed files."""
    claimed: set[Path] = set()
    seen_ids: set[str] = set()

    entries = data.get("assets")
    if entries is None:
        fail(problems, "register has no 'assets' key")
        return claimed
    if not isinstance(entries, list):
        fail(problems, "'assets' must be a list")
        return claimed

    for i, entry in enumerate(entries):
        label = f"entry[{i}]"
        if not isinstance(entry, dict):
            fail(problems, f"{label}: not an object")
            continue

        aid = entry.get("id", "")
        if aid:
            label = f"asset '{aid}'"

        for field in REQUIRED_FIELDS:
            if field not in entry:
                fail(problems, f"{label}: missing required field '{field}'")

        if aid:
            if aid in seen_ids:
                fail(problems, f"{label}: duplicate id")
            seen_ids.add(aid)

        lic = str(entry.get("license", ""))
        if lic in REJECTED_LICENSES:
            fail(problems, f"{label}: licence '{lic}' is rejected — "
                           f"{REJECTED_LICENSES[lic]}")
        elif lic and lic not in ALLOWED_LICENSES:
            fail(problems, f"{label}: licence '{lic}' is not on the allowed "
                           f"list. Verify it, then add it to ALLOWED_LICENSES "
                           f"in this script if it is genuinely compatible.")

        if entry.get("commercial_use") is not True:
            fail(problems, f"{label}: commercial_use is not true — cannot ship")

        if entry.get("attribution_required") is True:
            if not str(entry.get("attribution_text", "")).strip():
                fail(problems, f"{label}: attribution_required is true but "
                               f"attribution_text is empty, so the credits "
                               f"screen would render a blank credit")

        for key in ("url", "license_url"):
            val = str(entry.get(key, ""))
            if val and not val.startswith(("http://", "https://")):
                fail(problems, f"{label}: '{key}' is not a URL: {val!r}")

        acquired = str(entry.get("acquired", ""))
        if acquired:
            try:
                date.fromisoformat(acquired)
            except ValueError:
                fail(problems, f"{label}: 'acquired' is not ISO-8601: "
                               f"{acquired!r}")

        files = entry.get("files", [])
        if not isinstance(files, list) or not files:
            fail(problems, f"{label}: 'files' must be a non-empty list")
            continue
        for rel in files:
            path = REPO / str(rel)
            if not path.exists():
                fail(problems, f"{label}: registered file does not exist: {rel}")
            else:
                claimed.add(path.resolve())

    return claimed


def find_unclaimed(claimed: set[Path], problems: list[str]) -> None:
    """Every real asset file must be claimed by a register entry."""
    if not ASSET_ROOT.exists():
        return
    for path in sorted(ASSET_ROOT.rglob("*")):
        if not path.is_file():
            continue
        if path.name in IGNORED_NAMES or path.suffix in IGNORED_SUFFIXES:
            continue
        if "licenses" in path.relative_to(ASSET_ROOT).parts:
            continue
        if path.resolve() not in claimed:
            rel = path.relative_to(REPO)
            fail(problems, f"UNREGISTERED asset file: {rel} — no licence "
                           f"record, so it must not ship. Add it to "
                           f"assets/licenses/assets.json or remove it.")


def main() -> int:
    problems: list[str] = []

    if not REGISTER.exists():
        print(f"FAIL: register not found at {REGISTER.relative_to(REPO)}")
        return 1

    try:
        data = json.loads(REGISTER.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"FAIL: {REGISTER.relative_to(REPO)} is not valid JSON: {exc}")
        return 1

    claimed = validate_entries(data, problems)
    find_unclaimed(claimed, problems)

    count = len(data.get("assets", []) or [])

    if problems:
        print(f"asset register: {len(problems)} problem(s) across "
              f"{count} registered asset(s)\n")
        for p in problems:
            print(f"  - {p}")
        return 1

    print(f"asset register: OK — {count} asset(s) registered, "
          f"all licensed for commercial use, no unregistered files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
