class_name IntentSource
extends Node

## Base class for anything that decides what an actor wants to do.
##
## Subclasses: `PlayerIntentSource` (devices), and later `AIIntentSource` (M2)
## and `ScriptedIntentSource` (tests and replays).
##
## The contract has two halves, split by how the two kinds of input differ:
##
##   * `poll()` returns CONTINUOUS state for this frame (movement, held buttons).
##   * `buffer` accumulates DISCRETE presses with frame stamps, consumed once.
##
## Discrete presses cannot be a per-frame snapshot: a press made two frames
## before a cancel window opens must survive until the window opens, then be
## consumed exactly once. That is the whole reason the buffer exists separately.

## Frame-stamped presses. Owned here so every actor has an independent buffer —
## a global buffer would make two actors fight over the same presses.
var buffer: InputBuffer = InputBuffer.new()

## Monotonic count of frames in which this actor could ACTUALLY ACT.
##
## Buffered input ages against this rather than against wall-clock combat
## frames, and the distinction matters as soon as hitstop is long enough to
## feel: hitstop freezes the actor, so the cancel window it is waiting for
## arrives later in wall frames, while a buffer measured in wall frames keeps
## counting down. The press expires inside a freeze the player did not choose
## and never asked to sit through — which is the "the hit ate my input"
## complaint, and it gets WORSE the punchier hitstop is made.
##
## Freezing this counter during hitstop makes buffer leniency mean what a player
## assumes it means: frames during which they could have acted.
var frame_now: int = 0


## Advance the actionable clock. Called once per combat frame by the owner,
## before intent is polled.
func advance(actionable: bool) -> void:
	if actionable:
		frame_now += 1

var _intent: ActorIntent = ActorIntent.new()


## Produce this frame's continuous intent. Overridden by subclasses.
##
## Returns the SAME `ActorIntent` instance each call, mutated in place, rather
## than a fresh object. Called every frame for every actor, so allocating here
## would make intent gathering a per-frame garbage source for no benefit.
func poll(_frame: int) -> ActorIntent:
	return _intent


## Discard pending presses and zero continuous intent. Called when honouring
## queued input would be wrong — death, stagger into a cutscene, menu opened.
func reset() -> void:
	buffer.clear()
	_intent.clear()
	frame_now = 0
