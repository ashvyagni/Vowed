extends Node

## Global combat time authority. THE single source of truth for combat time.
##
## Autoload singleton: `CombatClock`.
##
## Everything in combat is expressed in *frames* at a fixed 60 Hz, never in
## seconds and never in `delta`. This is locked (docs/TECH_STACK.md §5.1) and is
## the decision the rest of the combat system is built on:
##
##   * "Active on frame 7" means frame 7 at 60 fps and at 144 fps. Timing cannot
##     drift with render rate.
##   * Combat becomes a pure function of (state, input, frame), so it is
##     unit-testable headlessly with no renderer.
##   * Frame-stepping is possible, so frame data can be *read* during tuning
##     instead of guessed at.
##
## Animation is a SLAVE to this clock — `AnimationPlayer.seek(frame / 60.0)`.
## Animation never drives combat state. If you ever find yourself reading an
## animation's position to decide a combat outcome, the architecture has been
## violated.
##
## This node owns time only. It has no knowledge of actors; `CombatDirector`
## owns the per-tick pipeline. That split exists because pause/step/slow-motion
## are also used by debug tooling and (later) cinematics, and should not be
## entangled with an actor registry.

## Emitted once per logical combat frame, before any actor has advanced.
## `CombatDirector` is the intended primary listener.
signal ticked(frame: int)

## Emitted when time control changes, so debug UI can reflect it without polling.
signal time_control_changed()

## The fixed logical rate. Changing this invalidates every authored attack in
## the game — frame data is expressed in these ticks.
const TICK_RATE: int = 60
const TICK_DELTA: float = 1.0 / float(TICK_RATE)

## Logical combat frames advanced per real frame while slow-motion is engaged.
## 1-in-8 gives roughly 7.5 logical fps, slow enough to read startup frames by
## eye while still animating.
const SLOW_MOTION_DIVISOR: int = 8

## Monotonically increasing logical combat frame. Never decreases, never resets
## during a session — actors store absolute frame stamps and compare against it,
## so a reset would make every stored stamp retroactively wrong.
var frame: int = 0

## When true the clock does not advance except via `request_step()`.
var paused: bool = false:
	set(value):
		if paused == value:
			return
		paused = value
		time_control_changed.emit()

## When true the clock advances one logical frame every SLOW_MOTION_DIVISOR
## physics frames. Debug only — never used for gameplay effects like hitstop,
## which is per-actor state rather than global time.
var slow_motion: bool = false:
	set(value):
		if slow_motion == value:
			return
		slow_motion = value
		_slow_accumulator = 0
		time_control_changed.emit()

var _step_requested: bool = false
var _slow_accumulator: int = 0


func _ready() -> void:
	# Run before every other node's physics step so that `frame` is already
	# correct for this tick by the time anything else reads it. Without this the
	# tick order depends on scene-tree order, which is exactly the kind of
	# implicit ordering that makes combat bugs irreproducible.
	process_physics_priority = -1000

	# Time control must keep working while the game is paused, otherwise
	# frame-stepping a paused game is impossible — which is when it is most
	# needed.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	if not _should_advance():
		return
	frame += 1
	ticked.emit(frame)


func _should_advance() -> bool:
	# An explicit step overrides both pause and slow-motion: when the user asks
	# for one frame they get exactly one frame.
	if _step_requested:
		_step_requested = false
		return true
	if paused:
		return false
	if slow_motion:
		_slow_accumulator += 1
		if _slow_accumulator < SLOW_MOTION_DIVISOR:
			return false
		_slow_accumulator = 0
	return true


# --- time control (debug) ---------------------------------------------------

## Advance exactly one logical frame on the next physics step, regardless of
## pause or slow-motion state.
func request_step() -> void:
	_step_requested = true


func toggle_pause() -> void:
	paused = not paused


func toggle_slow_motion() -> void:
	slow_motion = not slow_motion


# --- conversion helpers ----------------------------------------------------
#
# These exist so that the frames-to-seconds conversion happens in exactly one
# place. Scattered `/ 60.0` literals are how a project ends up with two
# different definitions of a frame.

## Frames to seconds. Used for `AnimationPlayer.seek()` and nothing else in
## gameplay logic.
static func frames_to_seconds(frames: int) -> float:
	return float(frames) * TICK_DELTA


## Seconds to frames, rounded. Only for importing authored data expressed in
## seconds (e.g. animation lengths from a DCC tool). Gameplay code should never
## need this — if it does, something is being authored in the wrong unit.
static func seconds_to_frames(seconds: float) -> int:
	return int(round(seconds * float(TICK_RATE)))


## Frames elapsed since an absolute frame stamp.
func frames_since(stamp: int) -> int:
	return frame - stamp
