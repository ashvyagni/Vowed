class_name PlayerIntentSource
extends IntentSource

## Turns real devices into `ActorIntent`.
##
## Presses are captured in `_unhandled_input` rather than polled, for two
## reasons that both matter for combat feel:
##
##   1. Nothing is missed. Polling in `_physics_process` can drop a press that
##      is made and released between two ticks — rare, but it is exactly the
##      kind of "the game ate my input" defect that is impossible to reproduce
##      on demand and destroys trust in the controls.
##   2. UI gets priority for free. `_unhandled_input` only receives events no
##      Control consumed, so an open menu cannot leak a punch into gameplay.
##
## Held state and analog movement ARE polled, because for continuous values only
## the current state matters.
##
## Movement is resolved to camera space here. Combat and movement downstream deal
## in world-space intent and know nothing about cameras — which is what lets the
## same movement code serve an AI with no camera at all.

## Camera used to resolve movement into world space. Without one, input is
## treated as already world-relative (correct for tests and for AI).
@export var camera: Camera3D

## Below this magnitude, stick input is discarded as drift.
@export_range(0.0, 0.5, 0.01) var move_deadzone: float = 0.15

## Emitted on every captured press, so the debug overlay can show raw input
## independently of whether combat consumed it — the difference between the two
## is what makes buffer tuning visible.
signal action_pressed(action: CombatAction.Id, frame: int)

var _enabled: bool = true


func _ready() -> void:
	# Must run before the actor consumes intent, so presses made this frame are
	# already in the buffer.
	process_priority = -100


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event.is_echo():
		return
	for id: CombatAction.Id in CombatAction.all():
		var name: StringName = CombatAction.input_name(id)
		if name == &"":
			continue
		if event.is_action_pressed(name, false, true):
			# Stamped with the ACTIONABLE clock, not the wall clock, so the
			# press does not age while the actor is frozen in hitstop.
			buffer.push(id, frame_now)
			action_pressed.emit(id, frame_now)


func poll(_frame: int) -> ActorIntent:
	if not _enabled:
		_intent.clear()
		return _intent

	# --- held state ---
	_intent.held = 0
	for id: CombatAction.Id in CombatAction.all():
		var name: StringName = CombatAction.input_name(id)
		if name != &"" and Input.is_action_pressed(name):
			_intent.held |= CombatAction.bit(id)

	# --- movement ---
	var raw: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_back", &"move_forward")
	if raw.length() < move_deadzone:
		_intent.move = Vector2.ZERO
	else:
		# Rescale past the deadzone so the first responsive input is a slow walk
		# rather than a sudden jump to deadzone speed.
		var magnitude: float = inverse_lerp(move_deadzone, 1.0,
			minf(raw.length(), 1.0))
		_intent.move = raw.normalized() * clampf(magnitude, 0.0, 1.0)

	return _intent


## World-space direction the player's movement intent points at, resolved
## against the camera. Returns `Vector3.ZERO` when there is no input.
##
## Lives here rather than in the movement system so that movement receives a
## world-space direction it can use identically for a player and for an AI.
func world_move_direction() -> Vector3:
	if not _intent.has_move_input():
		return Vector3.ZERO
	if camera == null:
		# No camera: treat input as already world-relative. Correct for tests
		# and for AI, which has no camera at all.
		return Vector3(_intent.move.x, 0.0, -_intent.move.y).normalized()
	return camera_relative_direction(_intent.move,
		camera.global_transform.basis)


## Resolve movement input against a camera orientation.
##
## PURE FUNCTION of (input, basis) — no node, no scene, no tree. That matters
## for more than tidiness: a `Node3D` parented to a headless root reports an
## identity `global_transform`, so any test that built a real camera to check
## this would silently measure an unrotated one and pass no matter what the
## code did. Taking the basis as an argument is what makes the contract
## genuinely checkable.
##
## `move.x` is strafe (+ right), `move.y` is forward (+ away from the viewer).
static func camera_relative_direction(move: Vector2,
		camera_basis: Basis) -> Vector3:
	# A camera looks down its own -Z; +X is the viewer's right.
	var forward: Vector3 = -camera_basis.z
	var right: Vector3 = camera_basis.x

	# Flatten: camera pitch must never affect ground movement speed or
	# direction, or looking down would slow the player and push them into the
	# floor.
	forward.y = 0.0
	right.y = 0.0

	if forward.length_squared() < 0.0001:
		# Looking straight up or down — the view direction has no horizontal
		# component left, so fall back to the camera's up axis flattened, which
		# still points the way the viewer is oriented.
		forward = camera_basis.y
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			return Vector3.ZERO

	forward = forward.normalized()
	right = right.normalized()

	return (right * move.x + forward * move.y).normalized()


## Suspend input capture (menus, cutscenes, death). Pending presses are
## discarded so nothing fires on resume.
func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	if not value:
		reset()


func is_enabled() -> bool:
	return _enabled
