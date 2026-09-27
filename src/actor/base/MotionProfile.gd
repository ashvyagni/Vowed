class_name MotionProfile
extends Resource

## Movement tuning, authored as data.
##
## Movement feel is content, not code (docs/ARCHITECTURE.md §1). An actor
## references a profile; heavy enemies, nimble enemies and the player differ by
## profile rather than by having different movement code. Tuning is therefore a
## file edit, and the same code path is exercised by every actor — so a movement
## bug cannot exist for only one of them.
##
## All rates are per SECOND but applied per 60 Hz frame, so the numbers stay
## readable while the simulation stays frame-locked.
##
## Exploration and combat share one foundation with different profiles rather
## than two separate controllers. Two controllers is how a game ends up feeling
## like two different games depending on whether an enemy is nearby.

@export var id: StringName = &""

@export_group("Ground speed")

## Top speed with full movement input, m/s.
@export_range(0.0, 30.0, 0.1) var max_speed: float = 6.0

## Top speed while locked on and strafing. Lower, so that circling an opponent is
## a deliberate choice with a cost rather than the strictly best way to move.
@export_range(0.0, 30.0, 0.1) var strafe_speed: float = 4.2

## Acceleration toward the target velocity, m/s².
##
## THE most important number for how movement feels. Too low reads as sluggish;
## too high reads as weightless and makes precise spacing impossible because the
## character reaches top speed before the player can judge distance.
@export_range(1.0, 200.0, 1.0) var acceleration: float = 55.0

## Deceleration when input stops, m/s². Higher than acceleration so stopping is
## crisper than starting — which is what makes spacing controllable.
@export_range(1.0, 200.0, 1.0) var deceleration: float = 75.0

## Extra deceleration when reversing. Prevents a slow skid through zero that
## makes direction changes feel unresponsive.
@export_range(1.0, 300.0, 1.0) var turn_deceleration: float = 120.0


@export_group("Turning")

## Turn rate, degrees per second, when moving freely.
@export_range(30.0, 3600.0, 10.0) var turn_speed: float = 900.0

## Turn rate while an attack is executing. Much lower: an attack must commit to
## a direction, or spacing and whiff-punishing stop meaning anything.
@export_range(0.0, 3600.0, 10.0) var attack_turn_speed: float = 90.0


@export_group("Air")

## Jump apex height in metres. Authored as a HEIGHT rather than an impulse so it
## stays meaningful when gravity is retuned.
@export_range(0.1, 10.0, 0.1) var jump_height: float = 1.9

## Gravity multiplier while rising. Below 1 gives a floatier ascent.
@export_range(0.1, 3.0, 0.05) var rise_gravity_scale: float = 0.85

## Gravity multiplier while falling. Above 1 gives the snappy fall that makes
## jumps feel controlled rather than drifty.
@export_range(0.1, 5.0, 0.05) var fall_gravity_scale: float = 1.35

## How much horizontal control is retained in the air, 0..1. Full air control
## makes aerial combat weightless; none makes air routes unplayable. Air combat
## is a major system here, so this sits deliberately high.
@export_range(0.0, 1.0, 0.05) var air_control: float = 0.72

## Terminal downward speed, m/s.
@export_range(1.0, 100.0, 1.0) var max_fall_speed: float = 32.0

## Frames after leaving a ledge during which a jump still registers. A small
## forgiveness that players never notice but always feel the absence of.
@export_range(0, 12, 1) var coyote_frames: int = 5

## Frames before landing during which a jump press is remembered.
@export_range(0, 12, 1) var jump_buffer_frames: int = 6


@export_group("Dash")

@export_range(0.0, 60.0, 0.5) var dash_speed: float = 13.0

## Frames the dash impulse is applied for.
@export_range(1, 60, 1) var dash_frames: int = 11

## Frames after a dash before another may begin. Without this, dashing is
## strictly better than walking and movement loses its texture.
@export_range(0, 120, 1) var dash_cooldown_frames: int = 14

## Air dashes allowed before touching the ground. Some Souls modify this.
@export_range(0, 5, 1) var air_dashes: int = 1


# --- derived ---------------------------------------------------------------

## Initial vertical speed for `jump_height`, given world gravity.
##
## Derived from the height rather than authored directly, so retuning gravity
## does not silently change every jump in the game. `v = sqrt(2 * g * h)`.
func jump_velocity(gravity: float) -> float:
	return sqrt(2.0 * gravity * rise_gravity_scale * maxf(jump_height, 0.01))


## Target speed for this frame, accounting for lock-on strafing.
func target_speed(locked_on: bool) -> float:
	return strafe_speed if locked_on else max_speed


## Which deceleration applies, given current and desired direction.
## Reversing uses the harsher value so direction changes stay crisp.
func decel_for(current_velocity: Vector3, desired: Vector3) -> float:
	if desired.is_zero_approx():
		return deceleration
	var flat_current := Vector3(current_velocity.x, 0.0, current_velocity.z)
	if flat_current.length_squared() < 0.01:
		return deceleration
	if flat_current.normalized().dot(desired.normalized()) < -0.25:
		return turn_deceleration
	return deceleration


func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var label: String = str(id) if id != &"" else "<unnamed profile>"

	if max_speed <= 0.0:
		problems.append("%s: max_speed is %f — the actor cannot move"
			% [label, max_speed])
	if deceleration < acceleration:
		problems.append("%s: deceleration (%.0f) is below acceleration (%.0f). "
			% [label, deceleration, acceleration]
			+ "Stopping slower than starting reads as skidding and makes "
			+ "spacing hard to control.")
	if strafe_speed > max_speed:
		problems.append("%s: strafe_speed (%.1f) exceeds max_speed (%.1f), so "
			% [label, strafe_speed, max_speed]
			+ "locking on would be strictly faster than running")
	if fall_gravity_scale < rise_gravity_scale:
		problems.append("%s: fall gravity (%.2f) is weaker than rise gravity "
			% [label, fall_gravity_scale]
			+ "(%.2f), which produces a floaty descent"
				% rise_gravity_scale)
	if dash_cooldown_frames == 0:
		problems.append("%s: dash cooldown is 0, so dashing is strictly better "
			% label + "than walking and movement loses its texture")
	return problems
