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
