class_name PlayerCamera
extends Node3D

## Third-person camera for exploration and precision combat.
##
## Two behaviours from one rig (docs/MILESTONES.md M1, master directive §8):
##
##   EXPLORATION — further back, readable environment, free look.
##   COMBAT      — closer, framed so the player AND the relevant enemy are both
##                 visible, because an attack the player cannot see is an attack
##                 they cannot react to.
##
## Design constraints deliberately enforced here:
##   * Camera shake is capped. Heavy shake destroys attack readability, and in a
##     game built on reading tells, readability outranks impact.
##   * Cinematic framing never costs gameplay clarity.
##   * Collision pulls in smoothly rather than snapping, because a snapping
##     camera is its own readability failure.

@export var target: Node3D

@export_group("Framing")
@export_range(1.0, 15.0, 0.1) var exploration_distance: float = 6.5
@export_range(1.0, 15.0, 0.1) var combat_distance: float = 4.8
@export_range(0.0, 4.0, 0.05) var height_offset: float = 1.55

## How quickly the rig follows the target. Not 1.0: a camera welded to the
## character transmits every movement jitter to the player's eye.
@export_range(0.01, 1.0, 0.01) var follow_smoothing: float = 0.22

@export_range(0.01, 1.0, 0.01) var distance_smoothing: float = 0.10

@export_group("Look")
@export_range(0.01, 1.0, 0.01) var mouse_sensitivity: float = 0.14
@export_range(0.5, 10.0, 0.1) var stick_sensitivity: float = 2.6
@export_range(-80.0, 0.0, 1.0) var min_pitch: float = -62.0
@export_range(0.0, 80.0, 1.0) var max_pitch: float = 48.0

@export_group("Lock-on")
## Extra height the camera looks toward when locked on, so both actors frame well.
@export_range(0.0, 3.0, 0.05) var lock_on_look_height: float = 1.15
@export_range(0.01, 1.0, 0.01) var lock_on_smoothing: float = 0.18

@export_group("Shake")
## Hard ceiling on shake magnitude in metres. Capped by direction, not taste.
@export_range(0.0, 0.5, 0.01) var max_shake: float = 0.11
@export_range(0.5, 20.0, 0.5) var shake_decay: float = 7.0

var camera: Camera3D
var locked_target: Node3D = null

var _yaw: float = 0.0
var _pitch: float = -8.0
var _distance: float = 6.5
var _shake: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO
var _spring: SpringArm3D


func _ready() -> void:
	_spring = SpringArm3D.new()
	# Collide only against the camera proxy layer, so the camera is never pushed
	# around by hurtboxes or props that should not affect framing.
	_spring.collision_mask = 1 | (1 << 9)   # world_static + camera_collide
	_spring.spring_length = exploration_distance
	_spring.margin = 0.35
	add_child(_spring)

	camera = Camera3D.new()
	camera.fov = 68.0
	_spring.add_child(camera)

	_distance = exploration_distance
	GameEvents.hit_landed.connect(_on_hit_landed)
	GameEvents.parry_succeeded.connect(_on_parry)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity,
			min_pitch, max_pitch)


func _process(delta: float) -> void:
	if target == null:
		return

	_apply_stick_look(delta)
	_follow_target(delta)
	_apply_lock_on(delta)
	_apply_distance(delta)
	_apply_shake(delta)


func _apply_stick_look(delta: float) -> void:
	# Right stick is read directly rather than through the buffered intent path:
	# camera look is continuous and must not queue.
	var look_x: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var look_y: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(look_x) < 0.15:
		look_x = 0.0
	if absf(look_y) < 0.15:
		look_y = 0.0
	if look_x == 0.0 and look_y == 0.0:
		return
	_yaw -= look_x * stick_sensitivity * 60.0 * delta
	_pitch = clampf(_pitch - look_y * stick_sensitivity * 60.0 * delta,
		min_pitch, max_pitch)


func _follow_target(delta: float) -> void:
	var desired: Vector3 = target.global_position + Vector3.UP * height_offset
	var weight: float = 1.0 - pow(1.0 - follow_smoothing, delta * 60.0)
	global_position = global_position.lerp(desired, weight)


func _apply_lock_on(delta: float) -> void:
	if locked_target == null:
		rotation_degrees = Vector3(_pitch, _yaw, 0.0)
		return

	# Frame BOTH actors: aim between the player and the target rather than at the
	# target. Aiming straight at the enemy pushes the player off-centre, and a
	# player who cannot see themselves cannot judge spacing.
	var midpoint: Vector3 = (target.global_position
		+ locked_target.global_position) * 0.5
	var to_midpoint: Vector3 = midpoint - global_position
	to_midpoint.y = 0.0
	if to_midpoint.length_squared() < 0.01:
		return

	var desired_yaw: float = rad_to_deg(atan2(-to_midpoint.x, -to_midpoint.z))
	var weight: float = 1.0 - pow(1.0 - lock_on_smoothing, delta * 60.0)
	_yaw = rad_to_deg(lerp_angle(deg_to_rad(_yaw), deg_to_rad(desired_yaw), weight))

	var height_difference: float = locked_target.global_position.y \
		- target.global_position.y
	var desired_pitch: float = clampf(
		_pitch + (height_difference - lock_on_look_height) * 1.2,
		min_pitch, max_pitch)
	_pitch = lerpf(_pitch, desired_pitch, weight * 0.35)

	rotation_degrees = Vector3(_pitch, _yaw, 0.0)


func _apply_distance(delta: float) -> void:
	var desired: float = combat_distance if locked_target != null \
		else exploration_distance
	var weight: float = 1.0 - pow(1.0 - distance_smoothing, delta * 60.0)
	_distance = lerpf(_distance, desired, weight)
	_spring.spring_length = _distance


func _apply_shake(delta: float) -> void:
	if _shake <= 0.0:
		if _shake_offset != Vector3.ZERO:
			camera.position = Vector3.ZERO
			_shake_offset = Vector3.ZERO
		return

	_shake = maxf(0.0, _shake - shake_decay * delta)
	var magnitude: float = minf(_shake, max_shake)
	_shake_offset = Vector3(
		randf_range(-magnitude, magnitude),
		randf_range(-magnitude, magnitude),
		0.0)
	camera.position = _shake_offset


func add_shake(amount: float) -> void:
	# Clamped on the way in as well as on application, so no caller can exceed
	# the readability ceiling even by accident.
	_shake = minf(max_shake, maxf(_shake, amount * max_shake))


func set_lock_on(new_target: Node3D) -> void:
	locked_target = new_target


func toggle_lock_on(candidate: Node3D) -> void:
	locked_target = null if locked_target != null else candidate


func _on_hit_landed(_attacker: Node, _victim: Node, hit: HitResult) -> void:
	if hit.reaction != null:
		add_shake(hit.reaction.camera_shake)


func _on_parry(_defender: Node, _attacker: Node, _hit: HitResult) -> void:
	# A parry is the highest-skill defensive action, so its feedback is
	# deliberately the most emphatic the shake ceiling allows.
	add_shake(1.0)
