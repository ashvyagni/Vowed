class_name ScriptedIntentSource
extends IntentSource

## Intent driven by code rather than by a device or an AI.
##
## Two uses, both of which depend on the same property: that the combat system
## cannot tell the difference between this and a real player.
##
##   * INTEGRATION TESTS — drive an actor deterministically and assert what
##     happens. Device input cannot be simulated headlessly, and an AI is not
##     deterministic enough to test frame-accurate behaviour against.
##   * REPLAYS AND SCRIPTED SEQUENCES — later, for cinematic gameplay moments
##     and for reproducing a reported bug from a recorded input log.
##
## It is the third implementation of the same `IntentSource` contract as the
## player and the AI, which is what makes "the enemy runs the identical combat
## model" checkable rather than merely asserted.

## Held movement, in the actor's own frame: x = strafe, y = forward.
var move: Vector2 = Vector2.ZERO:
	set(value):
		move = value
		_intent.move = value

var locked_on: bool = false:
	set(value):
		locked_on = value
		_intent.locked_on = value


func poll(_frame: int) -> ActorIntent:
	# `_intent` is mutated by the setters above and by hold()/release(), so it is
	# already current. Returned as-is, matching the contract that `poll()` does
	# not allocate.
	return _intent


func press(action: CombatAction.Id) -> void:
	buffer.push(action, CombatClock.frame)


func hold(action: CombatAction.Id) -> void:
	_intent.set_held(action, true)


func release(action: CombatAction.Id) -> void:
	_intent.set_held(action, false)


## Press while holding a direction, for command normals that need one.
func press_with_direction(action: CombatAction.Id, direction: Vector2) -> void:
	move = direction
	press(action)


func reset() -> void:
	super.reset()
	move = Vector2.ZERO
	locked_on = false
