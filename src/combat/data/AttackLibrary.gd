class_name AttackLibrary
extends Resource

## Every attack available to one move set, addressable by id.
##
## Combo edges reference attacks by `StringName`; this is what turns that id into
## the `AttackData` to execute. One library per move set — the player's, and one
## per enemy archetype — so an enemy physically cannot execute an attack that is
## not part of its own move set.
##
## Souls extend a move set by contributing a library through `included_libraries`,
## exactly as they contribute routes through `ComboGraph.included_graphs`. Neither
## the base library nor the base graph ever learns that Souls exist.

@export var id: StringName = &""

@export var display_name: String = ""

@export var attacks: Array[AttackData] = []

## Libraries merged into this one. Soul and Manifestation move sets layer in here.
@export var included_libraries: Array[AttackLibrary] = []

## id -> AttackData. Built lazily; lookups happen every frame an attack starts.
var _index: Dictionary = {}
var _indexed: bool = false


## The attack for `id`, or null if this move set does not contain it.
func get_attack(attack_id: StringName) -> AttackData:
	_ensure_index()
	return _index.get(attack_id, null)


func has_attack(attack_id: StringName) -> bool:
	_ensure_index()
	return _index.has(attack_id)


## Every id in this library, including layered ones. Passed to
## `ComboGraph.validate()` so routes can be cross-checked against real attacks.
func attack_ids() -> Array[StringName]:
	_ensure_index()
	var ids: Array[StringName] = []
	for key: StringName in _index:
		ids.append(key)
	return ids


func all_attacks() -> Array[AttackData]:
	var result: Array[AttackData] = []
	for attack: AttackData in attacks:
		if attack != null:
			result.append(attack)
	for sub: AttackLibrary in included_libraries:
		if sub != null:
			result.append_array(sub.all_attacks())
	return result


func count() -> int:
	return all_attacks().size()


## Rebuild the index. Call after mutating `attacks` or `included_libraries` at
## runtime, which happens when a Soul layers its move set in.
func invalidate_index() -> void:
	_index.clear()
	_indexed = false


func _ensure_index() -> void:
	if _indexed:
		return
	_index.clear()
	for attack: AttackData in all_attacks():
		if attack.id == &"":
			continue
		# First definition wins, so a base attack is never silently replaced by a
		# layered one. A Soul that wants to *change* an existing attack must be
		# explicit about it rather than shadowing by accident.
		if not _index.has(attack.id):
			_index[attack.id] = attack
	_indexed = true


# --- validation -------------------------------------------------------------

## Validate every attack, plus library-level problems a single attack cannot see.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var label: String = str(id) if id != &"" else "<unnamed library>"

	if id == &"":
		problems.append("%s: library id is empty" % label)

	var all: Array[AttackData] = all_attacks()
	if all.is_empty():
		problems.append("%s: library contains no attacks" % label)

	# Duplicate ids: the shadowed attack would silently never execute, which is
	# invisible in play and not something a single resource can detect.
	var seen: Dictionary = {}
	for attack: AttackData in all:
		if attack.id == &"":
			continue
		if seen.has(attack.id):
			problems.append("%s: duplicate attack id '%s' — only the first is "
				% [label, attack.id] + "reachable, the other silently never "
				+ "executes")
		seen[attack.id] = true

	for attack: AttackData in all:
		problems.append_array(attack.validate())

	return problems


## Frame-data table for the whole move set, in standard notation. This is the
## document a combat designer actually reads when balancing: startup/active/
## recovery side by side is how outliers become obvious.
func describe_frame_data() -> String:
	var lines: PackedStringArray = []
	lines.append("AttackLibrary '%s' — %d attack(s)" % [str(id), count()])
	lines.append("  %-22s %-9s %-6s %-6s %-8s %s" % [
		"id", "s/a/r", "dmg", "stagr", "hitstop", "category"])

	var all: Array[AttackData] = all_attacks()
	all.sort_custom(func(a: AttackData, b: AttackData) -> bool:
		return str(a.id) < str(b.id))

	for attack: AttackData in all:
		lines.append("  %-22s %-9s %-6.0f %-6.0f %-8d %s" % [
			str(attack.id),
			"%d/%d/%d" % [attack.startup, attack.active, attack.recovery],
			attack.damage,
			attack.stagger_damage,
			attack.hitstop,
			CombatTypes.category_name(attack.category),
		])

	return "\n".join(lines)
