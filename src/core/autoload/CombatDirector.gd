extends Node

## Owns the per-frame combat pipeline. Autoload singleton: `CombatDirector`.
##
## Actors do NOT advance themselves from `_physics_process`. The director runs a
## fixed sequence of phases across EVERY actor, one phase fully completed before
## the next begins:
##
##   1. INTENT   — every actor decides what it wants (input / AI).
##   2. COMBAT   — every actor's state machine advances one frame.
##   3. RESOLVE  — hits are resolved in one ordered pass over all actors.
##   4. MOTION   — every actor commits its movement to physics.
##   5. PRESENT  — animation is seeked to match the frame.
##
## WHY PHASES RATHER THAN PER-ACTOR TICKS
##
## If each actor ran its whole update in its own `_physics_process`, the outcome
## of a fight would depend on scene-tree order: actor A would resolve its hit
## before actor B had advanced, so B could be struck out of an attack it had not
## yet been given the chance to land. That produces "whoever is earlier in the
## tree wins" — a bug that is invisible in single-actor testing, appears only in
## real fights, and is unfixable without exactly this restructure.
##
## Phase 3 running once, globally, after every actor has advanced, is also what
## makes same-frame trades expressible at all (see `HitResolver`).
##
## Separated from `CombatClock`, which owns only time. Pause, frame-step and
## slow-motion belong to the clock and are used by debug tooling and cinematics;
## they should not be entangled with an actor registry.

## Emitted after a frame is fully resolved, carrying every contact that occurred.
## The debug overlay and combat log hang off this.
signal frame_resolved(frame: int, hits: Array[HitResult])

var _actors: Array[Actor] = []

## Components that may be mid-attack. Kept as its own array so the resolver is
## not re-deriving it from `_actors` every frame.
var _combat_components: Array[CombatComponent] = []

## Set true to stop the pipeline without stopping the clock — used when a
## cutscene owns the actors.
var suspended: bool = false

var _last_hits: Array[HitResult] = []


func _ready() -> void:
	# After CombatClock (priority -1000), before everything else.
	process_physics_priority = -900
	CombatClock.ticked.connect(_on_tick)


func _on_tick(frame: int) -> void:
	if suspended or _actors.is_empty():
		return

	for actor: Actor in _actors:
		if actor != null and actor.is_inside_tree():
			actor.phase_intent()

	for actor: Actor in _actors:
		if actor != null and actor.is_inside_tree():
			actor.phase_combat()

	_last_hits = _resolve_hits()

	for actor: Actor in _actors:
		if actor != null and actor.is_inside_tree():
			actor.phase_motion()

	frame_resolved.emit(frame, _last_hits)


func _resolve_hits() -> Array[HitResult]:
	if _actors.is_empty():
		return [] as Array[HitResult]

	var world: World3D = _actors[0].get_world_3d()
	if world == null:
		return [] as Array[HitResult]

	var space: PhysicsDirectSpaceState3D = \
		PhysicsServer3D.space_get_direct_state(world.space)
	if space == null:
		return [] as Array[HitResult]

	return HitResolver.resolve_frame(_combat_components, space)


# --- registry ---------------------------------------------------------------

func register_actor(actor: Actor) -> void:
	if actor == null or _actors.has(actor):
		return
	_actors.append(actor)
	if actor.combat != null and not _combat_components.has(actor.combat):
		_combat_components.append(actor.combat)


func unregister_actor(actor: Actor) -> void:
	_actors.erase(actor)
	if actor != null and actor.combat != null:
		_combat_components.erase(actor.combat)


func actors() -> Array[Actor]:
	return _actors


func actor_count() -> int:
	return _actors.size()


## Contacts resolved on the most recent frame. Read by the debug overlay.
func last_hits() -> Array[HitResult]:
	return _last_hits


## Nearest living actor to `from`, excluding itself, within `max_distance`.
## Used for lock-on and for AI target selection.
func nearest_actor(from: Actor, max_distance: float = 30.0) -> Actor:
	var best: Actor = null
	var best_distance: float = max_distance
	for actor: Actor in _actors:
		if actor == null or actor == from or not actor.is_alive():
			continue
		var distance: float = from.global_position.distance_to(
			actor.global_position)
		if distance < best_distance:
			best_distance = distance
			best = actor
	return best


## Reset every registered actor. The Combat Lab's instant reset, which is what
## makes iterating on frame data fast enough to actually tune it.
func reset_all() -> void:
	for actor: Actor in _actors:
		if actor != null:
			actor.reset()
	_last_hits = []
