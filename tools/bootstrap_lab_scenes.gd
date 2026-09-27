# VOWED — one-time bootstrap of the Combat Lab and its actor scenes.
#
#     godot --headless --path . -s tools/bootstrap_lab_scenes.gd
#
# Like tools/bootstrap_player_moveset.gd this is a BOOTSTRAP, not a build step.
# It writes the initial .tscn files in a guaranteed-valid form; after that the
# scenes are edited in the Godot editor and ARE the source of truth. Re-running
# overwrites editor changes.
#
# THE COMBAT LAB
#
# An isolated arena with a training dummy, frame-data overlay and instant reset.
# It exists BEFORE any real level, deliberately. Tuning combat inside a real
# environment is slow and confounded: terrain, props, lighting and enemy placement
# all affect what a hit feels like, so a change cannot be attributed. The Lab
# removes every variable except the combat itself.
#
# Collision layer values follow docs/TECH_STACK.md §5.3. They are computed from
# bit positions rather than written as magic numbers, so a layer reassignment
# cannot silently desynchronise from the documented allocation.

extends SceneTree

## THIN LAUNCHER — the real work is in tools/lab_builder.gd.
##
## WHY THE INDIRECTION (this is a real Godot constraint, not a preference)
##
## A script run with `-s` is compiled BEFORE the project's autoload singletons are
## registered as global identifiers. Any class it references statically is
## compiled at that same moment — so referencing `Actor` here fails with
## "Identifier not found: GameEvents", because Actor.gd legitimately uses the
## GameEvents autoload and that name does not exist yet.
##
## Loading the builder with `load()` defers its compilation to RUNTIME, by which
## point the autoloads are present and every project class resolves normally. The
## same reason the test runner loads test files dynamically rather than importing
## them.
##
## Any future `-s` tool that needs to touch Actor, CombatComponent or Hurtbox
## must use this two-file shape.


func _initialize() -> void:
	var builder_script: GDScript = load("res://tools/lab_builder.gd") as GDScript
	if builder_script == null:
		printerr("could not load tools/lab_builder.gd")
		quit(1)
		return

	var builder: RefCounted = builder_script.new()
	var written: int = builder.call("run")

	print("\nWrote %d scene(s)." % written)
	quit(0 if written > 0 else 1)
