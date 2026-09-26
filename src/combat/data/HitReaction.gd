class_name HitReaction
extends Resource

## What happens to the victim when an attack connects.
##
## Reactions are authored as their own resource and **shared between attacks**.
## That sharing is the point: "medium stagger" should mean exactly the same
## thing everywhere it is used, so that combo routes remain predictable across
## the whole move set. If every attack defined its own reaction inline, hitstun
## values would drift and the player could never build reliable intuition.
##
## Hitstun is expressed in frames, like everything else in combat.

@export var kind: CombatTypes.ReactionKind = CombatTypes.ReactionKind.MEDIUM

## Frames the victim is unable to act. This value, minus the attacker's
## recovery, is the frame advantage — the single most important number in the
## whole system, because it decides which follow-ups are actually guaranteed.
@export_range(0, 180, 1) var hitstun_frames: int = 14

## Frames the victim's hurtbox remains vulnerable to a *fresh* combo after
## hitstun ends. A small value here creates a real "drop the combo" failure
## state instead of infinite chains.
@export_range(0, 60, 1) var vulnerable_tail_frames: int = 4

## Horizontal pushback applied to the victim, in metres per second, away from
## the attacker. Pushback is what stops combos becoming positionless.
@export_range(0.0, 30.0, 0.1) var pushback: float = 3.0

## Velocity imparted to the victim in the attacker's LOCAL space, used when
## `kind` is LAUNCH or WALL_SPLAT. +Y lifts, +Z pushes away.
@export var launch_velocity: Vector3 = Vector3.ZERO

## Frames the victim's gravity is reduced after a launch, to hold them in the
## air long enough for an aerial route to be executable. Without this, air
## combos are only possible with frame-perfect execution, which makes them a
## trick rather than a system.
@export_range(0, 60, 1) var float_frames: int = 0

## Gravity multiplier during `float_frames`.
@export_range(0.0, 1.0, 0.05) var float_gravity_scale: float = 0.35

## Does the victim end up on the ground, requiring a wake-up?
@export var causes_knockdown: bool = false

## Does this reaction turn the victim to face the attacker? Spinning reactions
## deliberately do not, which is what makes back-hit routes possible.
@export var reorients_victim: bool = true

## Camera shake magnitude, 0 = none. Kept modest by direction: heavy shake
## destroys attack readability, which matters more than impact in a game where
## the player must read tells.
@export_range(0.0, 1.0, 0.05) var camera_shake: float = 0.15


## Frame advantage for the attacker: positive means the attacker recovers first
## and the follow-up is guaranteed. `attacker_recovery` is the attacker's
## remaining recovery frames at the moment of contact.
func frame_advantage(attacker_recovery: int) -> int:
	return hitstun_frames - attacker_recovery


func is_airborne_reaction() -> bool:
	return CombatTypes.reaction_is_airborne(kind)


func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if hitstun_frames < 0:
		problems.append("hitstun_frames is negative (%d)" % hitstun_frames)
	if kind == CombatTypes.ReactionKind.LAUNCH \
			and launch_velocity.is_zero_approx():
		problems.append("kind is LAUNCH but launch_velocity is zero, "
			+ "so the victim would not actually leave the ground")
	if float_frames > 0 and not is_airborne_reaction():
		problems.append("float_frames is set (%d) on a non-airborne reaction "
			% float_frames + "(%s), where it has no effect"
			% CombatTypes.reaction_name(kind))
	return problems
