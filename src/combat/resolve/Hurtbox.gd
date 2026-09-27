class_name Hurtbox
extends Area3D

## A volume that can receive hits.
##
## Deliberately used as a QUERY TARGET only — its `area_entered` /
## `body_entered` signals are never connected for combat. Hit detection is an
## explicit ordered shape query during the combat tick
## (docs/TECH_STACK.md §5.2), because signal delivery order is not controllable,
## signals fire on the physics step rather than the combat frame, and same-frame
## trade rules are effectively impossible to express through them.
##
## An `Area3D` is still the right node: it gives a collision shape the physics
## server can answer queries against, without participating in physics
## resolution.

## The combat component that receives hits landing here. Resolved from the
## ancestry when not set, so a hurtbox cannot be silently orphaned.
@export var combat: CombatComponent

## The actor this volume belongs to, for feedback positioning and events.
@export var actor: Node3D

## Damage multiplier for hits landing here. Enables weak points on large
## enemies and Prime Beasts — a readable, positional skill expression rather
## than a stat check.
@export_range(0.0, 10.0, 0.05) var damage_multiplier: float = 1.0

## Marks a weak point, so feedback can be distinctly stronger. Hitting one
## should be unmistakable, otherwise the mechanic is invisible.
@export var is_weak_point: bool = false


func _ready() -> void:
	# Never participate in physics resolution — queries only.
	monitoring = false
	monitorable = true

	if combat == null:
		combat = _find_combat()
	if actor == null:
		actor = _find_actor()

	if combat == null:
		GameEvents.report_assertion("Hurtbox",
			"'%s' has no CombatComponent above it, so hits landing on it would "
				% get_path() + "be silently discarded")


func _find_combat() -> CombatComponent:
	var node: Node = get_parent()
	while node != null:
		for child: Node in node.get_children():
			if child is CombatComponent:
				return child as CombatComponent
		node = node.get_parent()
	return null


func _find_actor() -> Node3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node as Node3D
		node = node.get_parent()
	return get_parent() as Node3D


func is_receptive() -> bool:
	return combat != null and CombatState.is_hittable(combat.state)
