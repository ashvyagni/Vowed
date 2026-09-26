#!/usr/bin/env bash
# Run the VOWED test suite headlessly.
#
#   tools/test.sh                 # everything
#   tools/test.sh buffer          # only files whose path matches 'buffer'
#
# Re-imports first so a newly added `class_name` is registered — skipping that
# produces "Could not find type X" errors that look like code bugs but are a
# stale cache. See tools/import.sh.
#
# Exits non-zero if any test fails, so this works directly as a pre-commit hook.
set -euo pipefail

cd "$(dirname "$0")/.."

godot --headless --editor --quit >/dev/null 2>&1 || true

args=(--headless --path . -s tests/framework/TestRunner.gd)
if [ $# -gt 0 ]; then
    args+=(-- "--filter=$1")
fi

godot "${args[@]}"
