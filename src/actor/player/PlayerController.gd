class_name PlayerController
extends Actor

## The player. An `Actor` whose intent comes from a device, plus the two things
## only the player owns: a camera and lock-on.
##
## Deliberately thin. Everything about fighting lives in `Actor` and
## `CombatComponent`, which is what guarantees the player and every enemy run the
## identical combat model (docs/ARCHITECTURE.md §4). A thick player class is how
## that guarantee quietly erodes — a special case here, another there, and enemies
## end up fighting by different rules.

@export var camera_rig: PlayerCamera

## Maximum distance a lock-on target may be acquired at.
@export_range(1.0, 60.0, 0.5) var lock_on_range: float = 22.0

## Capture the mouse on start. Off in the Combat Lab so the editor stays usable
## while iterating.
@export var capture_mouse: bool = true


func _ready() -> void:
	super._ready()
	if camera_rig != null and camera_rig.target == null:
		camera_rig.target = self
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func phase_intent() -> void:
	_handle_lock_on()
	super.phase_intent()

	# Keep the camera's notion of the target and this actor's in sync: routing
	# conditions resolve "forward" against the target, so a disagreement between
	# camera and combat would make directional inputs feel wrong.
	if _intent != null:
		_intent.locked_on = target != null


func _handle_lock_on() -> void:
	if intent_source == null:
		return
	if not intent_source.buffer.consume(CombatAction.Id.LOCK_ON,
			CombatClock.frame):
		return

	if target != null:
		target = null
	else:
		target = CombatDirector.nearest_actor(self, lock_on_range)

	if camera_rig != null:
		camera_rig.set_lock_on(target)


func _unhandled_input(event: InputEvent) -> void:
	# Escape releases the mouse so the editor and the game can be swapped between
	# without killing the process — small, but it is used constantly while tuning.
	if event.is_action_pressed(&"menu") \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and capture_mouse \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
