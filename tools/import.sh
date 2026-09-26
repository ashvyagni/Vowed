#!/usr/bin/env bash
# Build Godot's import cache and global class-name registry.
#
# WHY THIS IS NEEDED
#
# Godot registers `class_name` declarations during an editor filesystem scan and
# caches the result in .godot/global_script_class_cache.cfg. That directory is
# machine-local and gitignored, so a FRESH CLONE has no registry — and every
# script that references a project class by name fails to parse with
# "Could not find type X in the current scope".
#
# The error looks like a code bug and is not one. Run this once after cloning,
# and again after adding a new `class_name`, before any headless run.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v godot >/dev/null 2>&1; then
    echo "error: 'godot' not on PATH. Install Godot 4.7.2+ (brew install --cask godot)." >&2
    exit 1
fi

echo "Importing assets and registering global classes..."
godot --headless --editor --quit >/dev/null 2>&1 || true

if [ ! -f .godot/global_script_class_cache.cfg ]; then
    echo "error: class cache was not created. Run 'godot --headless --editor --quit' to see why." >&2
    exit 1
fi

count=$(grep -c 'class=' .godot/global_script_class_cache.cfg || true)
echo "OK — ${count} global class(es) registered."
