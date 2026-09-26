#!/usr/bin/env bash
# Full local verification gate. Run before every commit.
#
#   1. Import / class registry
#   2. Boot self-check  — are the locked technical decisions still in force?
#   3. Test suite
#   4. Asset licence register — both directions
#
# Any failure exits non-zero. This is the closest thing the project has to CI,
# and per docs/TECH_STACK.md §10 it is deliberately sufficient for a solo
# developer until M16.
set -uo pipefail

cd "$(dirname "$0")/.."
failed=0

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Import and class registry"
godot --headless --editor --quit >/dev/null 2>&1 || true
if [ -f .godot/global_script_class_cache.cfg ]; then
    echo "OK — $(grep -c 'class=' .godot/global_script_class_cache.cfg || echo 0) class(es)"
else
    echo "FAIL — class cache missing"; failed=1
fi

step "Boot self-check"
boot_output=$(godot --headless --path . --quit-after 60 2>&1)
echo "$boot_output" | sed 's/^/    /'
if echo "$boot_output" | grep -q "CONFIGURATION FAILED"; then
    echo "FAIL — a locked technical decision has drifted"; failed=1
fi
if echo "$boot_output" | grep -qE "SCRIPT ERROR|Parse Error"; then
    echo "FAIL — script errors during boot"; failed=1
fi

step "Test suite"
godot --headless --path . -s tests/framework/TestRunner.gd || failed=1

step "Asset licence register"
python3 tools/validate_assets.py || failed=1

printf '\n'
if [ "$failed" -eq 0 ]; then
    printf '\033[32mALL CHECKS PASSED\033[0m\n'
else
    printf '\033[31mCHECKS FAILED\033[0m\n'
fi
exit "$failed"
