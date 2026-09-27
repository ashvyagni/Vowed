class_name Actor
extends CharacterBody3D

## Anything that fights or inhabits the world. Player and enemy alike.
##
## The player is *the actor whose intent comes from input*; an enemy is *the actor
## whose intent comes from AI*. Both run the identical `CombatComponent` and the
## identical movement code (docs/ARCHITECTURE.md §4). That is a design
## requirement, not deduplication: enemies must be able to out-play the player
## mechanically, which is impossible if they run a different model. It also means
## a movement or combat bug cannot exist for only one side.
##
## Advanced in PHASES by `CombatDirector`, never from `_physics_process`. The
## phases run across ALL actors in a fixed order, which is what makes hit
## resolution deterministic — every actor's state is settled before any hit is
## resolved.

signal health_changed(current: float, maximum: float)
signal died()

@export_group("Identity")
@export var actor_id: StringName = &""
@export var display_name: String = ""

@export_group("Combat")
@export var max_health: float = 100.0

## Poise. When stagger damage exceeds this, the actor staggers. Separate from
## health so a tough enemy and a hard-to-interrupt enemy are independent axes of
## design rather than the same slider.
@export var max_poise: float = 60.0

## Frames without taking stagger damage before poise begins recovering.
@export_range(0, 300, 1) var poise_recovery_delay: int = 90

## Poise recovered per frame once recovery starts.
@export_range(0.0, 10.0, 0.1) var poise_recovery_rate: float = 0.5

@export_group("Movement")
@export var profile: MotionProfile

@export_group("Nodes")
## Set in the scene. Resolved from children when left empty.
@export var combat: CombatComponent
@export var intent_source: IntentSource
@export var model: Node3D


var health: float = 0.0
var poise: float = 0.0

## World-space direction this actor wants to move. Written during the intent
## phase, consumed during the motion phase.
var move_direction: Vector3 = Vector3.ZERO

## Current lock-on / aggro target.
var target: Actor = null

var _intent: ActorIntent = null
var _context: ComboContext = ComboContext.new()

var _gravity: float = 24.0
var _coyote_frames_left: int = 0
var _jump_buffer_frames_left: int = 0
var _dash_cooldown_left: int = 0
var _air_dashes_left: int = 0
var _dash_direction: Vector3 = Vector3.ZERO

## Combat frame the last dash began on; -1 if never. Gates dash-cancel
## attacks, which cannot be expressed as an attack-relative frame window
## because a dash attack is launched from neutral.
var _last_dash_frame: int = -1
var _frames_since_stagger_damage: int = 0
var _was_grounded: bool = true


func _ready() -> void:
	health = max_health
	poise = max_poise
	_gravity = float(ProjectSettings.get_setting(
		"physics/3d/default_gravity", 24.0))

	if combat == null:
		combat = _find_child_of_type(&"CombatComponent") as CombatComponent
	if intent_source == null:
		intent_source = _find_child_of_type(&"IntentSource") as IntentSource

	if combat == null:
		GameEvents.report_assertion("Actor",
			"'%s' has no CombatComponent and therefore cannot fight" % name)
	else:
		combat.damage_received.connect(_on_damage_received)

	_air_dashes_left = profile.air_dashes if profile != null else 1

	CombatDirector.register_actor(self)


func _exit_tree() -> void:
	CombatDirector.unregister_actor(self)


## Find a child whose script is `type_name`, or inherits from it.
##
## `is_class()` only knows ENGINE classes, so it cannot find a script-defined type
## like CombatComponent. Walking the script inheritance chain means a subclass
## (e.g. PlayerIntentSource for IntentSource) is still matched — without that,
## every actor scene would have to wire these references by hand.
func _find_child_of_type(type_name: StringName) -> Node:
	for child: Node in get_children():
		var script: Script = child.get_script() as Script
		while script != null:
			if script.get_global_name() == type_name:
				return child
			script = script.get_base_script()
	return null


# --- phase 1: intent --------------------------------------------------------

## Gather this frame's intent and act on it. Runs for every actor before any
## combat state advances.
func phase_intent() -> void:
	if intent_source == null or combat == null:
		return

	_intent = intent_source.poll(CombatClock.frame)
	move_direction = _resolve_move_direction()

	_tick_movement_timers()
	_consume_buffered_actions()


func _resolve_move_direction() -> Vector3:
	if intent_source is PlayerIntentSource:
		return (intent_source as PlayerIntentSource).world_move_direction()
	if _intent == null or not _intent.has_move_input():
		return Vector3.ZERO
	return Vector3(_intent.move.x, 0.0, -_intent.move.y).normalized()


func _tick_movement_timers() -> void:
	if is_on_floor():
		_coyote_frames_left = profile.coyote_frames if profile != null else 5
		_air_dashes_left = profile.air_dashes if profile != null else 1
	elif _coyote_frames_left > 0:
		_coyote_frames_left -= 1

	if _jump_buffer_frames_left > 0:
		_jump_buffer_frames_left -= 1
	if _dash_cooldown_left > 0:
		_dash_cooldown_left -= 1

	_frames_since_stagger_damage += 1


## Translate buffered presses into actions, in priority order.
##
## Order matters and is deliberate: defensive options are checked BEFORE offence,
## so a player who panics and presses guard during an attack's cancel window gets
## the guard. Defence losing to offence on a tie would make the game feel like it
## ignores self-preservation.
func _consume_buffered_actions() -> void:
	var buffer: InputBuffer = intent_source.buffer
	var now: int = CombatClock.frame

	# Guard is a HELD state, not a buffered press, so it is read continuously.
	if _intent.is_held(CombatAction.Id.GUARD):
		if combat.state != CombatState.Id.GUARDING \
				and combat.state != CombatState.Id.PARRYING:
			combat.try_action(CombatAction.Id.GUARD, _build_context())
	elif combat.state == CombatState.Id.GUARDING \
			or combat.state == CombatState.Id.PARRYING:
		combat.release_guard()

	# Peek-then-consume throughout: a press is only spent when the action
	# actually starts. Consuming unconditionally would discard input made during
	# an attack's startup or a dash cooldown — precisely the moments buffering
	# exists to cover.
	if buffer.peek(CombatAction.Id.DASH, now) and _try_dash():
		buffer.consume(CombatAction.Id.DASH, now)

	if buffer.consume(CombatAction.Id.JUMP, now):
		_jump_buffer_frames_left = profile.jump_buffer_frames if profile != null else 6
	if _jump_buffer_frames_left > 0 and _can_jump():
		_jump()

	# Attacks last: everything above is either defensive or movement, and both
	# should win a tie against committing to an attack.
	var attack_action: int = buffer.peek_any(
		[CombatAction.Id.PUNCH, CombatAction.Id.KICK,
			CombatAction.Id.SOUL_TECHNIQUE], now)
	if attack_action >= 0:
		if combat.try_action(attack_action as CombatAction.Id, _build_context()):
			buffer.consume(attack_action as CombatAction.Id, now)


func _build_context() -> ComboContext:
	_context.reset()
	_context.direction = _local_direction()
	_context.frame = CombatClock.frame
	_context.frames_since_dash = -1 if _last_dash_frame < 0 \
		else CombatClock.frame - _last_dash_frame

	if target != null and target.combat != null:
		_context.target_state = target.combat.as_target_state()
		_context.target_distance = global_position.distance_to(
			target.global_position)
	else:
		_context.target_state = CombatTypes.TargetState.NONE
		_context.target_distance = INF

	# Soul fields are filled by the Soul component at M3. Left at defaults here.
	return _context


## Movement intent as a discrete direction in the actor's own frame, resolved
## against the target when locked on so that "forward" means "toward the enemy"
## rather than "toward the camera".
func _local_direction() -> CombatTypes.Direction:
	if move_direction.is_zero_approx():
		return CombatTypes.Direction.NEUTRAL

	var reference: Vector3 = -global_transform.basis.z
	if target != null:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.001:
			reference = to_target.normalized()

	var right: Vector3 = reference.cross(Vector3.UP).normalized()
	var local := Vector2(move_direction.dot(-right), move_direction.dot(reference))
	return CombatTypes.resolve_direction(local)


# --- phase 2: combat --------------------------------------------------------

## Advance the combat state machine by one frame.
func phase_combat() -> void:
	if combat == null:
		return
	combat.grounded = is_on_floor()
	combat.tick()
	_recover_poise()


func _recover_poise() -> void:
	if poise >= max_poise:
		return
	if _frames_since_stagger_damage < poise_recovery_delay:
		return
	poise = minf(max_poise, poise + poise_recovery_rate)


# --- phase 3: motion -------------------------------------------------------

## Apply movement and commit it to the physics body.
func phase_motion() -> void:
	if profile == null:
		move_and_slide()
		return

	# Hitstop freezes the actor completely. Movement continuing through hitstop
	# is one of the clearest ways to make a hit feel like it did not land.
	if combat != null and combat.is_in_hitstop():
		velocity = Vector3.ZERO
		return

	_apply_horizontal()
	_apply_gravity()
	_apply_facing()

	var was_airborne: bool = not is_on_floor()
	move_and_slide()

	if was_airborne and is_on_floor():
		_on_landed()
	_was_grounded = is_on_floor()


func _apply_horizontal() -> void:
	# An attack's displacement is AUTHORED, not input-driven: during an attack
	# the player's stick does not move them. That commitment is what makes
	# spacing and whiff-punishing meaningful.
	var motion: Array[MotionKeyframe] = combat.current_motion() if combat != null \
		else [] as Array[MotionKeyframe]
	if not motion.is_empty():
		for key: MotionKeyframe in motion:
			velocity = key.apply(velocity, global_transform.basis)
		return

	if combat != null and combat.state == CombatState.Id.DODGING:
		velocity.x = _dash_direction.x * profile.dash_speed
		velocity.z = _dash_direction.z * profile.dash_speed
		return

	if combat != null and not combat.can_act():
		# Helpless actors keep their momentum and are slowed by friction only,
		# so knockback carries rather than stopping dead.
		velocity.x = move_toward(velocity.x, 0.0,
			profile.deceleration * CombatClock.TICK_DELTA)
		velocity.z = move_toward(velocity.z, 0.0,
			profile.deceleration * CombatClock.TICK_DELTA)
		return

	if combat != null and combat.is_attacking():
		return  # attacks without motion keyframes simply hold position

	var control: float = 1.0 if is_on_floor() else profile.air_control
	var desired: Vector3 = move_direction \
		* profile.target_speed(_intent != null and _intent.locked_on)

	var rate: float = profile.acceleration
	if desired.is_zero_approx():
		rate = profile.decel_for(velocity, desired)
	else:
		rate = maxf(profile.acceleration, profile.decel_for(velocity, desired)) \
			if velocity.normalized().dot(desired.normalized()) < -0.25 \
			else profile.acceleration

	var step: float = rate * control * CombatClock.TICK_DELTA
	velocity.x = move_toward(velocity.x, desired.x, step)
	velocity.z = move_toward(velocity.z, desired.z, step)


func _apply_gravity() -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
		return

	# Asymmetric gravity: a floatier rise and a snappier fall. This is what makes
	# a jump feel controlled instead of drifty, and it matters more here than in
	# most games because air combat is a major system.
	var scale: float = profile.rise_gravity_scale if velocity.y > 0.0 \
		else profile.fall_gravity_scale

	# A launched actor floats longer so an aerial route is executable rather than
	# frame-perfect.
	if combat != null and combat.state == CombatState.Id.LAUNCHED:
		scale *= 0.45

	velocity.y = maxf(velocity.y - _gravity * scale * CombatClock.TICK_DELTA,
		-profile.max_fall_speed)


func _apply_facing() -> void:
	var face: Vector3 = Vector3.ZERO
	if target != null and _intent != null and _intent.locked_on:
		face = target.global_position - global_position
	elif not move_direction.is_zero_approx():
		face = move_direction
	face.y = 0.0
	if face.length_squared() < 0.0001:
		return

	# An attack turns slowly: it must commit to a direction, or spacing stops
	# meaning anything because any attack can be re-aimed mid-swing.
	var speed: float = profile.turn_speed
	if combat != null and combat.is_attacking():
		speed = profile.attack_turn_speed

	var current: float = rotation.y
	var desired: float = atan2(-face.x, -face.z)
	rotation.y = _rotate_toward(current, desired,
		deg_to_rad(speed) * CombatClock.TICK_DELTA)


static func _rotate_toward(from: float, to: float, max_step: float) -> float:
	var difference: float = wrapf(to - from, -PI, PI)
	if absf(difference) <= max_step:
		return to
	return from + signf(difference) * max_step


# --- actions ---------------------------------------------------------------

func _can_jump() -> bool:
	if combat == null or not combat.can_act():
		return false
	if combat.is_attacking():
		return combat.attack != null and combat.attack.find_cancel(
			CombatTypes.CancelInto.JUMP, combat.attack_frame,
			combat.did_hit, combat.did_guard) != null
	return is_on_floor() or _coyote_frames_left > 0


func _jump() -> void:
	velocity.y = profile.jump_velocity(_gravity)
	_coyote_frames_left = 0
	_jump_buffer_frames_left = 0


## Returns true if a dash actually began, so the caller knows whether to spend
## the buffered press.
func _try_dash() -> bool:
	if _dash_cooldown_left > 0:
		return false
	if not is_on_floor():
		if _air_dashes_left <= 0:
			return false

	# Dash goes where the player is pointing; with no input it goes forward, so a
	# neutral dash is still useful rather than doing nothing.
	_dash_direction = move_direction
	if _dash_direction.is_zero_approx():
		_dash_direction = -global_transform.basis.z
	_dash_direction.y = 0.0
	_dash_direction = _dash_direction.normalized()

	if not combat.try_action(CombatAction.Id.DASH, _build_context()):
		return false

	_dash_cooldown_left = profile.dash_cooldown_frames
	_last_dash_frame = CombatClock.frame
	if not is_on_floor():
		# Only spend an air dash once the dash has actually committed.
		_air_dashes_left -= 1
	return true


func _on_landed() -> void:
	if combat != null and combat.state == CombatState.Id.LAUNCHED:
		# Landing from a launch becomes a knockdown rather than instant recovery,
		# so an air combo ends in a real situation.
		pass


# --- damage ----------------------------------------------------------------

func _on_damage_received(result: HitResult) -> void:
	apply_damage(result.damage)
	apply_stagger(result.stagger_damage)

	if result.reaction != null and not result.reaction.launch_velocity.is_zero_approx():
		var away: Vector3 = result.direction
		away.y = 0.0
		velocity = away.normalized() * result.reaction.launch_velocity.z \
			+ Vector3.UP * result.reaction.launch_velocity.y
	elif result.reaction != null and result.reaction.pushback > 0.0:
		var push: Vector3 = result.direction
		push.y = 0.0
		velocity.x = push.normalized().x * result.reaction.pushback
		velocity.z = push.normalized().z * result.reaction.pushback


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()


func apply_stagger(amount: float) -> void:
	if amount <= 0.0:
		return
	_frames_since_stagger_damage = 0
	poise = maxf(0.0, poise - amount)
	if poise <= 0.0:
		poise = max_poise
		GameEvents.actor_staggered.emit(self)


func _die() -> void:
	if combat != null:
		combat.kill()
	died.emit()


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


func is_alive() -> bool:
	return health > 0.0


## Full reset. Used by the Combat Lab's instant reset.
func reset() -> void:
	health = max_health
	poise = max_poise
	velocity = Vector3.ZERO
	move_direction = Vector3.ZERO
	_dash_cooldown_left = 0
	_jump_buffer_frames_left = 0
	_last_dash_frame = -1
	_frames_since_stagger_damage = poise_recovery_delay
	if combat != null:
		combat.reset()
	if intent_source != null:
		intent_source.reset()
	health_changed.emit(health, max_health)
