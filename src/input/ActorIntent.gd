class_name ActorIntent
extends RefCounted

## What an actor wants to do on one combat frame.
##
## The seam between "who is deciding" and "what the body does". A player, an AI,
## a replay and a test all produce `ActorIntent`; the combat and movement systems
## consume it and cannot tell which produced it.
##
## That symmetry is a design requirement rather than tidiness. Enemies must run
## the *identical* combat model as the player (docs/ARCHITECTURE.md §4) or they
## cannot out-play the player mechanically, and combat becomes solitaire. Sharing
## this type is what makes that guarantee structural instead of aspirational.
##
## Continuous state lives here. Discrete presses live in `InputBuffer`, because
## presses need frame stamps and a consume-once contract that a per-frame
## snapshot cannot express.

## Desired movement, magnitude 0..1. x = strafe (+ right), y = forward (+ away
## from camera). Already resolved to world-space intent by the source, so combat
## and movement never need to know about cameras.
var move: Vector2 = Vector2.ZERO

## Desired facing, world space, normalised. `Vector3.ZERO` means "use `move`".
## Set when locked on, so an actor can strafe while still facing its target.
var facing: Vector3 = Vector3.ZERO

## Bitmask of currently held `CombatAction.Id`s (see `CombatAction.bit()`).
## Held state, not presses — guard is held, punch is pressed.
var held: int = 0

## True while a lock-on target is engaged. Changes movement (strafing) and
## camera behaviour.
var locked_on: bool = false


func is_held(action: CombatAction.Id) -> bool:
	return (held & CombatAction.bit(action)) != 0


func set_held(action: CombatAction.Id, value: bool) -> void:
	if value:
		held |= CombatAction.bit(action)
	else:
		held &= ~CombatAction.bit(action)


## Is there meaningful movement input? Dead-zoned, so stick drift and a
## near-centred stick both read as "no input" rather than as a crawl.
func has_move_input() -> bool:
	return move.length_squared() > 0.01


func clear() -> void:
	move = Vector2.ZERO
	facing = Vector3.ZERO
	held = 0
	locked_on = false


func describe() -> String:
	var held_names: PackedStringArray = []
	for id: CombatAction.Id in CombatAction.all():
		if is_held(id):
			held_names.append(CombatAction.display_name(id))
	return "move(%.2f, %.2f) held[%s]%s" % [
		move.x, move.y,
		", ".join(held_names),
		" locked" if locked_on else "",
	]
