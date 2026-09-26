class_name ComboGraph
extends Resource

## The complete set of authored combat routes.
##
## Nodes are attacks (`AttackData` in `data/attacks/`); edges are `ComboEdge`.
## One graph per move set: the player's, and one per enemy archetype.
##
## Resolution is a **pure function** of (graph, from-state, action, context), so
## every route in the game is testable headlessly. With a target of 100+ routes
## that is not a nicety — a move set whose behaviour can only be checked by
## playing it cannot be checked at all once it is large.
##
## Souls extend the move set by contributing edges to this graph rather than by
## special-casing anything in combat (docs/ARCHITECTURE.md §5). That is how a
## Soul passive can *change how the player fights*: FURY IGNITION does not raise
## a damage number, it makes a set of Soul-gated edges become legal.

## Identifier, e.g. `&"player_base"` or `&"brawler_enemy"`.
@export var id: StringName = &""

@export var display_name: String = ""

## Every authored route in this move set.
@export var edges: Array[ComboEdge] = []

## Graphs merged into this one at load. Souls and Manifestation sets are layered
## in this way, so the base move set never has to know they exist.
@export var included_graphs: Array[ComboGraph] = []

## from-attack id -> edges leaving it, pre-sorted by descending priority.
## Built lazily: resolution runs every frame for every actor, and rescanning a
## few hundred edges per query would be avoidable waste.
var _index: Dictionary = {}
var _indexed: bool = false


## Best route out of `context` for `action`, or `&""` if none applies.
##
## "Best" = highest priority among matching edges. Equal-priority matches are a
## content defect — the move set is ambiguous and the player cannot form a
## reliable mental model — and are reported by `validate()`.
func resolve(action: CombatAction.Id, context: ComboContext) -> StringName:
	var edge: ComboEdge = resolve_edge(action, context)
	return edge.to if edge != null else &""


## As `resolve()`, but returns the edge so callers can read its conditions —
## needed because whether a route preserves the combo counter is a property of
## the route taken, not of the destination attack.
func resolve_edge(action: CombatAction.Id, context: ComboContext) -> ComboEdge:
	_ensure_index()
	var candidates: Array = _index.get(context.current_attack, [])
	for edge: ComboEdge in candidates:
		if edge.action == action and edge.matches(context):
			return edge
	return null


## Every action that has a legal route right now. Drives the debug overlay's
## "available routes" display and AI option evaluation.
func available_actions(context: ComboContext) -> Array[CombatAction.Id]:
	_ensure_index()
	var result: Array[CombatAction.Id] = []
	for edge: ComboEdge in _index.get(context.current_attack, []):
		if edge.matches(context) and not result.has(edge.action):
			result.append(edge.action)
	return result


## Every edge leaving `from`, regardless of conditions. For tooling and for the
## generated move list.
func edges_from(from: StringName) -> Array[ComboEdge]:
	_ensure_index()
	var result: Array[ComboEdge] = []
	for edge: ComboEdge in _index.get(from, []):
		result.append(edge)
	return result


## All edges, including those contributed by included graphs.
func all_edges() -> Array[ComboEdge]:
	var result: Array[ComboEdge] = []
	for edge: ComboEdge in edges:
		if edge != null:
			result.append(edge)
	for sub: ComboGraph in included_graphs:
		if sub != null:
			result.append_array(sub.all_edges())
	return result


## Every attack id reachable in this graph. Used by the validator to confirm
## each one has an `AttackData` resource behind it.
func referenced_attack_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for edge: ComboEdge in all_edges():
		if edge.from != &"" and not ids.has(edge.from):
			ids.append(edge.from)
		if edge.to != &"" and not ids.has(edge.to):
			ids.append(edge.to)
	return ids


## Entry points: attacks reachable directly from neutral.
func entry_attacks() -> Array[StringName]:
	var ids: Array[StringName] = []
	for edge: ComboEdge in all_edges():
		if edge.from == &"" and edge.to != &"" and not ids.has(edge.to):
			ids.append(edge.to)
	return ids


## Total authored routes, including included graphs. The project's headline
## combat-content metric (target: 100+ meaningful routes).
func route_count() -> int:
	return all_edges().size()


## Rebuild the index. Call after mutating edges at runtime, which Souls do when
## layering their move set in.
func invalidate_index() -> void:
	_index.clear()
	_indexed = false


func _ensure_index() -> void:
	if _indexed:
		return
	_index.clear()
	for edge: ComboEdge in all_edges():
		if not _index.has(edge.from):
			_index[edge.from] = [] as Array[ComboEdge]
		(_index[edge.from] as Array[ComboEdge]).append(edge)
	# Descending priority, so resolution can return the first match.
	for key: StringName in _index:
		var list: Array[ComboEdge] = _index[key]
		list.sort_custom(func(a: ComboEdge, b: ComboEdge) -> bool:
			return a.priority > b.priority)
	_indexed = true


# --- validation -------------------------------------------------------------

## Validate the graph's structure. `known_attack_ids` should be every id present
## in `data/attacks/`; pass an empty array to skip that cross-check.
##
## Returns human-readable problems; empty means valid. Run by the content
## validator, so a broken route is caught in seconds rather than by a player
## wondering why a follow-up never comes out.
func validate(known_attack_ids: Array[StringName] = []) -> PackedStringArray:
	var problems: PackedStringArray = []
	var label: String = str(id) if id != &"" else "<unnamed graph>"
	var all: Array[ComboEdge] = all_edges()

	if id == &"":
		problems.append("%s: graph id is empty" % label)
	if all.is_empty():
		problems.append("%s: graph has no edges, so no attack can be started"
			% label)

	for i: int in all.size():
		for p: String in all[i].validate():
			problems.append("%s: %s" % [label, p])

	# Every referenced attack must exist. A typo here produces a route that
	# silently never fires, which is nearly impossible to notice in play.
	if not known_attack_ids.is_empty():
		for attack_id: StringName in referenced_attack_ids():
			if not known_attack_ids.has(attack_id):
				problems.append("%s: references attack '%s', which has no "
					% [label, attack_id] + "AttackData resource")

	if entry_attacks().is_empty():
		problems.append("%s: no edge leaves neutral, so no attack can ever "
			% label + "be started from a standing state")

	# Ambiguity: equal-priority edges competing for the same input.
	for i: int in all.size():
		for j: int in range(i + 1, all.size()):
			if all[i].conflicts_with(all[j]):
				problems.append("%s: ambiguous routes at equal priority — "
					% label + "'%s' and '%s' both match the same situation; "
					% [all[i].describe(), all[j].describe()]
					+ "which one fires would be arbitrary")

	# Unreachable attacks: named as a source but never as a destination, and not
	# an entry point. Usually a renamed attack whose inbound edge was missed.
	var destinations: Array[StringName] = []
	for edge: ComboEdge in all:
		if edge.to != &"":
			destinations.append(edge.to)
	for edge: ComboEdge in all:
		if edge.from != &"" and not destinations.has(edge.from):
			problems.append("%s: '%s' has routes leaving it but nothing routes "
				% [label, edge.from] + "INTO it, so those routes are "
				+ "unreachable")

	return problems


## Human-readable dump of the whole move set, grouped by source. Used by the
## debug overlay and by `tools/` to generate a move list — which is how a
## hundred-route move set stays reviewable as a whole.
func describe_routes() -> String:
	var lines: PackedStringArray = []
	lines.append("ComboGraph '%s' — %d route(s)" % [str(id), route_count()])

	var by_source: Dictionary = {}
	for edge: ComboEdge in all_edges():
		var key: StringName = edge.from
		if not by_source.has(key):
			by_source[key] = [] as Array[ComboEdge]
		(by_source[key] as Array[ComboEdge]).append(edge)

	var sources: Array = by_source.keys()
	sources.sort_custom(func(a: StringName, b: StringName) -> bool:
		# Neutral first: it is where every string begins.
		if a == &"":
			return true
		if b == &"":
			return false
		return str(a) < str(b))

	for source: StringName in sources:
		lines.append("  from %s:" % ("neutral" if source == &"" else str(source)))
		var list: Array[ComboEdge] = by_source[source]
		list.sort_custom(func(a: ComboEdge, b: ComboEdge) -> bool:
			return a.priority > b.priority)
		for edge: ComboEdge in list:
			lines.append("    %s" % edge.describe())

	return "\n".join(lines)
