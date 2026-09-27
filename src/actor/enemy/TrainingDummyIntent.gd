class_name TrainingDummyIntent
extends IntentSource

## Scripted intent for the Combat Lab's training dummy.
##
## This is a TESTING TOOL, not the enemy AI. Real AI arrives at M2 with goal-
## driven archetypes (rushdown, zoner, counter-puncher, ...). What this provides
## is a dummy whose behaviour is *predictable*, which is what tuning frame data
## requires: an opponent that varies its responses makes it impossible to tell
## whether a combo dropped because the data is wrong or because the dummy did
## something different.
##
## It is still built on the ordinary `IntentSource` contract, so the dummy drives
## the same combat model as the player through the same path. When real AI
## replaces it, nothing downstream changes — which is the point of routing all
## intent through one interface.

enum Mode {
	IDLE,        ## Stands still, takes everything. For reading frame data.
	BLOCK,       ## Holds guard. For testing chip, guard cancels and unblockables.
	PARRY,       ## Taps guard on a cadence. For testing being parried.
	COUNTER,     ## Blocks, then punishes the moment pressure stops.
	AGGRESSIVE,  ## Attacks on a cadence. For testing trades, armour and defence.
}

@export var mode: Mode = Mode.IDLE

## Frames between actions in the cadence-driven modes.
@export_range(10, 240, 1) var action_interval: int = 70

## Frames the PARRY mode holds guard for. Set near the parry window so the dummy
## genuinely sometimes parries and sometimes does not.
@export_range(1, 60, 1) var parry_hold_frames: int = 7

var _next_action_frame: int = 0
var _guard_until_frame: int = 0


func poll(frame: int) -> ActorIntent:
	_intent.clear()

	match mode:
		Mode.IDLE:
			pass
		Mode.BLOCK:
			_intent.set_held(CombatAction.Id.GUARD, true)
		Mode.PARRY:
			_poll_parry(frame)
		Mode.COUNTER:
			_poll_counter(frame)
		Mode.AGGRESSIVE:
			_poll_aggressive(frame)

	return _intent


func _poll_parry(frame: int) -> void:
	if frame >= _next_action_frame:
		_guard_until_frame = frame + parry_hold_frames
		_next_action_frame = frame + action_interval
	if frame < _guard_until_frame:
		_intent.set_held(CombatAction.Id.GUARD, true)


func _poll_counter(frame: int) -> void:
	# Hold guard continuously, and throw a punish on the cadence. Approximates the
	# most instructive thing a defensive opponent does: make an unsafe attack
	# cost something.
	_intent.set_held(CombatAction.Id.GUARD, true)
	if frame >= _next_action_frame:
		buffer.push(CombatAction.Id.PUNCH, frame)
		_next_action_frame = frame + action_interval


func _poll_aggressive(frame: int) -> void:
	if frame < _next_action_frame:
		return
	# Alternate punch and kick so both defensive answers get exercised rather
	# than only one being tested.
	var use_kick: bool = (frame / maxi(1, action_interval)) % 2 == 1
	buffer.push(CombatAction.Id.KICK if use_kick else CombatAction.Id.PUNCH,
		frame)
	_next_action_frame = frame + action_interval


func reset() -> void:
	super.reset()
	_next_action_frame = 0
	_guard_until_frame = 0


func cycle_mode() -> Mode:
	mode = ((int(mode) + 1) % (int(Mode.AGGRESSIVE) + 1)) as Mode
	reset()
	return mode


static func mode_name(value: Mode) -> String:
	match value:
		Mode.IDLE:       return "Idle"
		Mode.BLOCK:      return "Block"
		Mode.PARRY:      return "Parry"
		Mode.COUNTER:    return "Counter"
		Mode.AGGRESSIVE: return "Aggressive"
	return "?"
