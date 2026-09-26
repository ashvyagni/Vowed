class_name Bootstrap
extends Node

## Entry point and configuration self-check.
##
## This is not a placeholder scene. It asserts that the locked technical
## decisions in docs/TECH_STACK.md are actually in force at runtime, and fails
## loudly if they are not.
##
## The reason this exists at M0, before any gameplay: several of those decisions
## are silent when broken. A project that quietly falls back to a 30 Hz physics
## tick, or loses a collision-layer assignment during a merge, produces combat
## bugs that look like gameplay problems and get debugged as gameplay problems
## for days. Checking them on boot converts a week of confusion into one clear
## error line.
##
## Replaced as the main scene once the Combat Lab exists (M1); the checks move
## into the debug service and the test suite rather than being deleted.

# Locked in docs/TECH_STACK.md §5.1 — all authored frame data assumes this.
const REQUIRED_PHYSICS_TICK: int = 60
const REQUIRED_RENDERER: String = "forward_plus"

# Every gameplay action the project commits to. Checked for existence so a
# binding lost in a merge is caught on boot instead of mid-combat.
const REQUIRED_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"kick", "punch", "jump", "dash", "guard", "soul_technique", "manifestation",
	"interact", "lock_on", "menu", "map",
]

# Fixed allocation from docs/TECH_STACK.md §5.3, bit -> name.
const REQUIRED_LAYERS: Dictionary = {
	1: "world_static",
	2: "world_dynamic",
	3: "player_body",
	4: "enemy_body",
	5: "player_hurtbox",
	6: "enemy_hurtbox",
	7: "hitbox",
	8: "projectile",
	9: "interaction",
	10: "camera_collide",
	11: "nav_obstacle",
	12: "water",
}

var _failures: PackedStringArray = []
var _notes: PackedStringArray = []


func _ready() -> void:
	print_rich("[b]VOWED[/b] — boot self-check")
	print("  engine        : %s" % Engine.get_version_info().get("string", "unknown"))
	print("  project       : %s v%s" % [
		ProjectSettings.get_setting("application/config/name", "?"),
		ProjectSettings.get_setting("application/config/version", "?"),
	])
	print("  platform      : %s (%s)" % [OS.get_name(), Engine.get_architecture_name()])

	_check_physics_tick()
	_check_renderer()
	_check_physics_engine()
	_check_input_map()
	_check_collision_layers()

	_report()


# --- checks -----------------------------------------------------------------

func _check_physics_tick() -> void:
	var tick: int = Engine.physics_ticks_per_second
	print("  physics tick  : %d Hz" % tick)
	if tick != REQUIRED_PHYSICS_TICK:
		_failures.append(
			"Physics tick is %d Hz, must be %d Hz. Every authored attack's frame data "
			% [tick, REQUIRED_PHYSICS_TICK]
			+ "is expressed in these ticks, so combat timing is now wrong project-wide.")


func _check_renderer() -> void:
	var method: String = str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", ""))
	print("  renderer      : %s" % method)
	if method != REQUIRED_RENDERER:
		_failures.append(
			"Renderer is '%s', must be '%s'. The visual direction requires Forward+."
			% [method, REQUIRED_RENDERER])


func _check_physics_engine() -> void:
	var engine_name: String = str(ProjectSettings.get_setting(
		"physics/3d/physics_engine", "?"))
	print("  3d physics    : %s" % engine_name)
	if not engine_name.containsn("jolt"):
		_notes.append(
			"3D physics backend is '%s', expected Jolt. Character-controller edge "
			% engine_name
			+ "cases in the legacy backend are a poor fit for a precision action game.")


func _check_input_map() -> void:
	var missing: PackedStringArray = []
	for action: String in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(action)

	var unbound: PackedStringArray = []
	for action: String in REQUIRED_ACTIONS:
		if InputMap.has_action(action) and InputMap.action_get_events(action).is_empty():
			unbound.append(action)

	print("  input actions : %d/%d present" % [
		REQUIRED_ACTIONS.size() - missing.size(), REQUIRED_ACTIONS.size()])

	if not missing.is_empty():
		_failures.append("Input actions missing: %s. Regenerate with: " % ", ".join(missing)
			+ "godot --headless --path . -s tools/generate_input_map.gd")
	if not unbound.is_empty():
		_failures.append("Input actions exist but have no bound events: %s"
			% ", ".join(unbound))


func _check_collision_layers() -> void:
	var wrong: PackedStringArray = []
	for bit: int in REQUIRED_LAYERS:
		var expected: String = str(REQUIRED_LAYERS[bit])
		var actual: String = str(ProjectSettings.get_setting(
			"layer_names/3d_physics/layer_%d" % bit, ""))
		if actual != expected:
			wrong.append("bit %d is '%s', expected '%s'" % [bit, actual, expected])

	print("  layers        : %d/%d correct" % [
		REQUIRED_LAYERS.size() - wrong.size(), REQUIRED_LAYERS.size()])

	if not wrong.is_empty():
		_failures.append(
			"Collision layer allocation drifted (%s). " % "; ".join(wrong)
			+ "Layer bits are fixed for the project's lifetime — never reassign an "
			+ "existing bit, allocate from the reserved range instead.")


# --- reporting --------------------------------------------------------------

func _report() -> void:
	for note: String in _notes:
		push_warning("[boot] %s" % note)
		print_rich("  [color=yellow]note:[/color] %s" % note)

	if _failures.is_empty():
		print_rich("  [color=green]configuration OK[/color] — %d checks passed" % 5)
		return

	print_rich("  [color=red]CONFIGURATION FAILED[/color] — %d problem(s):"
		% _failures.size())
	for i: int in _failures.size():
		print_rich("    [color=red]%d.[/color] %s" % [i + 1, _failures[i]])
		push_error("[boot] %s" % _failures[i])
