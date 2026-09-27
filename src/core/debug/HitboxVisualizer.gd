class_name HitboxVisualizer
extends Node3D

## Draws active hitbox volumes.
##
## Hitboxes have NO node in the scene tree — they are authored shapes queried
## directly during the combat tick (docs/TECH_STACK.md §5.2), which is what makes
## hit resolution deterministic. The consequence is that Godot's built-in
## "Visible Collision Shapes" cannot show them, because there is nothing to show.
##
## So the debug view is drawn explicitly here. This is not optional tooling: a
## combat system whose hitboxes cannot be seen is tuned by superstition. Being
## able to see that an attack's volume sits behind the visual limb, or is live a
## frame too early, turns a week of confusion into an obvious fix.
##
## Colour encodes state, so a still frame is readable:
##   red      active hitbox
##   orange   active hitbox that has already connected this attack
##   blue     hurtbox
##   yellow   invulnerable hurtbox

const COLOUR_HITBOX := Color(1.0, 0.24, 0.2, 0.32)
const COLOUR_HITBOX_SPENT := Color(1.0, 0.62, 0.2, 0.22)
const COLOUR_HURTBOX := Color(0.3, 0.62, 1.0, 0.18)
const COLOUR_INVULNERABLE := Color(1.0, 0.9, 0.3, 0.26)

var _enabled: bool = false
var _pool: Array[MeshInstance3D] = []
var _used: int = 0
var _materials: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After the director's physics step, so what is drawn is what was resolved
	# this frame rather than last frame's state.
	process_priority = 1000
	set_visible(false)


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_release_all()


func is_enabled() -> bool:
	return _enabled


func toggle() -> void:
	set_enabled(not _enabled)


func _process(_delta: float) -> void:
	if not _enabled:
		return
	_used = 0

	for actor: Actor in CombatDirector.actors():
		if actor == null or not actor.is_inside_tree():
			continue
		_draw_hurtboxes(actor)
		_draw_hitboxes(actor)

	_release_unused()


func _draw_hitboxes(actor: Actor) -> void:
	var combat: CombatComponent = actor.combat
	if combat == null or not combat.is_attacking() or combat.attack == null:
		return

	# Deliberately NOT `combat.active_hitboxes()`: that returns empty during
	# hitstop, and hitstop is exactly when a frozen frame is being inspected.
	var boxes: Array[HitboxKeyframe] = combat.attack.active_hitboxes_on(
		combat.attack_frame)
	for box: HitboxKeyframe in boxes:
		if box.shape == null:
			continue
		var colour: Color = COLOUR_HITBOX_SPENT if combat.did_hit \
			else COLOUR_HITBOX
		_draw_shape(box.shape,
			actor.global_transform.translated_local(box.local_offset()), colour)


func _draw_hurtboxes(actor: Actor) -> void:
	var invulnerable: bool = actor.combat != null and actor.combat.is_invulnerable()
	var colour: Color = COLOUR_INVULNERABLE if invulnerable else COLOUR_HURTBOX
	for hurtbox: Node in _find_hurtboxes(actor):
		var area := hurtbox as Hurtbox
		for child: Node in area.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node == null or shape_node.shape == null:
				continue
			_draw_shape(shape_node.shape, shape_node.global_transform, colour)


func _find_hurtboxes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		if child is Hurtbox:
			found.append(child)
		found.append_array(_find_hurtboxes(child))
	return found


func _draw_shape(shape: Shape3D, transform: Transform3D, colour: Color) -> void:
	var instance: MeshInstance3D = _acquire()
	var mesh: Mesh = _mesh_for(shape)
	if mesh == null:
		return
	instance.mesh = mesh
	instance.material_override = _material_for(colour)
	instance.global_transform = transform
	instance.visible = true


## Build a display mesh matching a collision shape. Only the shape types combat
## actually uses are handled — spheres and capsules, because box corners produce
## edge cases players read as inconsistency.
func _mesh_for(shape: Shape3D) -> Mesh:
	if shape is SphereShape3D:
		var sphere := SphereMesh.new()
		var radius: float = (shape as SphereShape3D).radius
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		return sphere
	if shape is CapsuleShape3D:
		var capsule := CapsuleMesh.new()
		capsule.radius = (shape as CapsuleShape3D).radius
		capsule.height = (shape as CapsuleShape3D).height
		capsule.radial_segments = 12
		capsule.rings = 4
		return capsule
	if shape is BoxShape3D:
		var box := BoxMesh.new()
		box.size = (shape as BoxShape3D).size
		return box
	return null


func _material_for(colour: Color) -> StandardMaterial3D:
	var key: String = str(colour)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Draw through geometry: a hitbox hidden inside a character model is not a
	# debug view.
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 5
	_materials[key] = material
	return material


# --- instance pooling -------------------------------------------------------
#
# Pooled because this runs every frame while enabled. Allocating meshes per frame
# would make the debug view itself distort the performance numbers shown next to
# it, which would be self-defeating.

func _acquire() -> MeshInstance3D:
	if _used < _pool.size():
		var existing: MeshInstance3D = _pool[_used]
		_used += 1
		return existing
	var instance := MeshInstance3D.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_pool.append(instance)
	_used += 1
	return instance


func _release_unused() -> void:
	for i: int in range(_used, _pool.size()):
		_pool[i].visible = false


func _release_all() -> void:
	for instance: MeshInstance3D in _pool:
		instance.visible = false
	_used = 0
