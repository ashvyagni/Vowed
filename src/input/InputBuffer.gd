class_name InputBuffer
extends RefCounted

## Frame-stamped ring buffer of discrete action presses.
##
## THE reason this exists: without buffering, a player must press the next attack
## on the exact frame the current one becomes cancellable. That is not difficulty,
## it is unfairness — the input was correct and the game discarded it. Combat
## that drops correct inputs feels broken no matter how good the rest of it is.
##
## With buffering, a press slightly early is remembered and fires as soon as it
## becomes legal. The buffer therefore makes combat feel RESPONSIVE without
## making it EASY: the window is short enough that deliberate timing still
## matters, and cancel windows (the actual execution skill) are unchanged.
##
## The balance is set by two windows:
##   * `NATURAL_WINDOW` — generous. For the next attack in a string, which the
##     player is entitled to get for free once they have committed to it.
##   * `PRECISE_WINDOW` — tight. For advanced cancels, where precision IS the
##     skill being tested and leniency would erase it.
##
## Fixed-size `Packed*Array` storage: zero allocation per press, which matters
## because this is written from input events and read every combat frame.

## Presses retained. Well beyond any realistic window; overflow silently drops
## the oldest, which is correct — a press 32 inputs ago is not wanted.
const CAPACITY: int = 32

## Frames a press stays eligible for a natural follow-up. 6 frames = 100 ms.
## Large enough to feel forgiving, short enough that a press cannot fire so late
## that the player has forgotten making it.
const NATURAL_WINDOW: int = 6

## Frames a press stays eligible for a precision cancel. 3 frames = 50 ms.
const PRECISE_WINDOW: int = 3

var _actions: PackedInt32Array = PackedInt32Array()
var _frames: PackedInt32Array = PackedInt32Array()
var _consumed: PackedByteArray = PackedByteArray()
var _write: int = 0
var _count: int = 0


func _init() -> void:
	_actions.resize(CAPACITY)
	_frames.resize(CAPACITY)
	_consumed.resize(CAPACITY)
	clear()


## Record a press. `frame` is the combat frame it happened on.
func push(action: CombatAction.Id, frame: int) -> void:
	_actions[_write] = int(action)
	_frames[_write] = frame
	_consumed[_write] = 0
	_write = (_write + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)


## Take a buffered press of `action` if one is within `window` frames of `now`.
##
## Consumes EVERY matching unconsumed entry in the window, not just one. This is
## deliberate: a player who mashes punch three times in four frames wants one
## attack, not three queued attacks that fire over the next half second. Leaving
## the extras buffered is how a combat system develops the "my character is
## still doing things I asked for ages ago" feel.
func consume(action: CombatAction.Id, now: int,
		window: int = NATURAL_WINDOW) -> bool:
	var found: bool = false
	for i: int in CAPACITY:
		if _consumed[i] != 0:
			continue
		if _actions[i] != int(action):
			continue
		if not _within(i, now, window):
			continue
		_consumed[i] = 1
		found = true
	return found


## Take whichever of `actions` was pressed MOST RECENTLY within the window.
## Returns the consumed action, or -1 if none.
##
## Most-recent rather than first-listed so that the buffer never imposes a
## priority order on the player's choice: if they pressed kick after punch, they
## changed their mind, and the later press is the real intent.
func consume_any(actions: Array[CombatAction.Id], now: int,
		window: int = NATURAL_WINDOW) -> int:
	var best_index: int = -1
	var best_frame: int = -1
	for i: int in CAPACITY:
		if _consumed[i] != 0:
			continue
		if not _within(i, now, window):
			continue
		if not (_actions[i] as CombatAction.Id) in actions:
			continue
		if _frames[i] > best_frame:
			best_frame = _frames[i]
			best_index = i
	if best_index < 0:
		return -1
	var chosen: int = _actions[best_index]
	# Consume all presses of the chosen action in the window, for the same
	# anti-double-fire reason as `consume()`.
	consume(chosen as CombatAction.Id, now, window)
	return chosen


## Is a press available, without consuming it? For AI prediction and for the
## debug overlay, which must not alter the state it displays.
func peek(action: CombatAction.Id, now: int,
		window: int = NATURAL_WINDOW) -> bool:
	for i: int in CAPACITY:
		if _consumed[i] == 0 and _actions[i] == int(action) \
				and _within(i, now, window):
			return true
	return false


## Frames since the most recent unconsumed press of `action`, or -1 if none.
## Used by the debug overlay to show how much of a buffer window was used, which
## is how the window length gets tuned on evidence instead of by feel.
func age_of(action: CombatAction.Id, now: int) -> int:
	var newest: int = -1
	for i: int in CAPACITY:
		if _consumed[i] == 0 and _actions[i] == int(action) \
				and _frames[i] >= 0 and _frames[i] <= now:
			newest = maxi(newest, _frames[i])
	return -1 if newest < 0 else now - newest


## Discard everything. Used on state changes where honouring old input would be
## wrong — death, cutscene entry, menu open.
func clear() -> void:
	for i: int in CAPACITY:
		_actions[i] = -1
		_frames[i] = -1
		_consumed[i] = 1
	_write = 0
	_count = 0


## Mark every buffered press consumed without discarding history, so the debug
## overlay can still show what was pressed. Used when an action deliberately
## eats pending input.
func flush() -> void:
	for i: int in CAPACITY:
		_consumed[i] = 1


## Live entries, newest first, for the debug overlay:
## `[{action, frame, age, consumed}]`
func snapshot(now: int, max_age: int = 60) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i: int in CAPACITY:
		if _frames[i] < 0 or now - _frames[i] > max_age:
			continue
		entries.append({
			"action": _actions[i],
			"frame": _frames[i],
			"age": now - _frames[i],
			"consumed": _consumed[i] != 0,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["frame"]) > int(b["frame"]))
	return entries


func _within(index: int, now: int, window: int) -> bool:
	var f: int = _frames[index]
	if f < 0:
		return false
	var age: int = now - f
	# age < 0 guards against a press stamped on a frame the clock has not
	# reached, which can happen when input is captured between physics ticks.
	return age >= 0 and age <= window
