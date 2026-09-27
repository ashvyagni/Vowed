extends Node

## Impact feedback. Autoload singleton: `HitEffects`.
##
## Listens to `GameEvents` and never touches combat. Combat resolves a hit and
## is finished; this is one of the observers that reacts
## (docs/ARCHITECTURE.md §2.1). That is why combat has no reference to it.
##
## WHY THIS MATTERS MORE THAN IT LOOKS
##
## Correct frame data and a correct animation still produce a hit that feels
## like nothing if the moment of contact is not PUNCTUATED. The player is not
## reading damage numbers — they are reading a spike of light, a flinch, a
## freeze and a shake, all landing on the same frame. Remove the spike and the
## same hit reads as the fist passing through the target.
##
## Everything here is procedural: generated meshes and materials, no external
## assets. Impact VFX is one of the few places where a primitive genuinely does
## the job, and it keeps the feedback tunable in code while combat is still
## being tuned.
##
## Effects are POOLED. This fires several times a second during a combo, and a
## feedback system that allocates per hit would show up as a hitch on exactly
## the frames the player is judging.

## How long an impact flash lives, in combat frames.
const FLASH_FRAMES: int = 9

## How long a victim's body flash lasts, in combat frames. Shorter than the
## impact spark: a lingering body flash reads as a status effect rather than a
## hit.
const BODY_FLASH_FRAMES: int = 5

const COLOUR_HIT := Color(1.0, 0.93, 0.72)
const COLOUR_HEAVY := Color(1.0, 0.72, 0.38)
const COLOUR_GUARD := Color(0.62, 0.80, 1.0)
const COLOUR_PARRY := Color(0.55, 1.0, 1.0)

var _container: Node3D
var _pool: Array[MeshInstance3D] = []
var _active: Array[Dictionary] = []
var _flashing: Array[Dictionary] = []
var _sphere: SphereMesh


func _ready() -> void:
	_container = Node3D.new()
	_container.name = "HitEffectContainer"
	add_child(_container)

	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 10
	_sphere.rings = 5

	GameEvents.hit_landed.connect(_on_hit_landed)
	GameEvents.hit_guarded.connect(_on_hit_guarded)
	GameEvents.parry_succeeded.connect(_on_parry)

	CombatClock.ticked.connect(_on_tick)


# --- reacting to combat -----------------------------------------------------

func _on_hit_landed(_attacker: Node, victim: Node, hit: HitResult) -> void:
	var heavy: bool = hit.reaction != null \
		and (hit.reaction.kind == CombatTypes.ReactionKind.HEAVY
			or CombatTypes.reaction_is_airborne(hit.reaction.kind))

	# Scale with the hit's weight so the player can read how hard they connected
	# without looking at a number.
	# Sized to punctuate the contact, not to obscure the target. A spark that
	# covers the head hides the flinch — which is the feedback that actually
	# tells the player what kind of hit they landed.
	var size: float = 0.40 if heavy else 0.26
	var colour: Color = COLOUR_HEAVY if heavy else COLOUR_HIT

	_spawn(hit.position, colour, size)
	_flash_body(victim, colour)


func _on_hit_guarded(_attacker: Node, _victim: Node, hit: HitResult) -> void:
	# Deliberately smaller and cooler than a clean hit. The difference between
	# hitting and being blocked has to be legible through feel alone, with no UI.
	_spawn(hit.position, COLOUR_GUARD, 0.20)


func _on_parry(defender: Node, _attacker: Node, hit: HitResult) -> void:
	# The loudest feedback in the game. A perfect parry is the highest-skill
	# defensive action, and the player must know instantly that it worked.
	_spawn(hit.position, COLOUR_PARRY, 0.62)
	_flash_body(defender, COLOUR_PARRY)


# --- effects ----------------------------------------------------------------

func _spawn(position: Vector3, colour: Color, size: float) -> void:
	var instance: MeshInstance3D = _acquire()
	instance.global_position = position
	instance.scale = Vector3.ONE * size * 0.35
	instance.visible = true

	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Additive so overlapping hits build brightness instead of flattening, and
	# unculled+depth-tested-off so the spark is never swallowed by the body it
	# is landing on.
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material

	_active.append({
		"node": instance,
		"frame": 0,
		"size": size,
		"material": material,
	})


func _flash_body(victim: Node, colour: Color) -> void:
	if victim == null:
		return
	for mesh: MeshInstance3D in _find_meshes(victim):
		var material := mesh.material_override as StandardMaterial3D
		if material == null:
			continue
		# Skip a material already flashing, or the stored base colour would be
		# overwritten with the flash colour and the actor would stay lit.
		if _is_flashing(material):
			continue
		_flashing.append({
			"material": material,
			"frame": 0,
			"base": material.emission,
			"base_enabled": material.emission_enabled,
			"colour": colour,
		})


func _is_flashing(material: StandardMaterial3D) -> bool:
	for entry: Dictionary in _flashing:
		if entry["material"] == material:
			return true
	return false


# --- per-frame advance ------------------------------------------------------

func _on_tick(_frame: int) -> void:
	_advance_sparks()
	_advance_body_flashes()


func _advance_sparks() -> void:
	var finished: Array[Dictionary] = []

	for entry: Dictionary in _active:
		entry["frame"] = int(entry["frame"]) + 1
		var progress: float = float(entry["frame"]) / float(FLASH_FRAMES)

		if progress >= 1.0:
			finished.append(entry)
			continue

		var node: MeshInstance3D = entry["node"]
		var material: StandardMaterial3D = entry["material"]
		var size: float = float(entry["size"])

		# Fast out, slow settle: a linear expand reads as a bubble, an eased one
		# reads as an impact.
		var eased: float = 1.0 - pow(1.0 - progress, 3.0)
		node.scale = Vector3.ONE * size * (0.35 + eased * 1.5)

		var alpha: float = 1.0 - progress
		material.albedo_color.a = alpha
		material.emission_energy_multiplier = 3.0 * alpha

	for entry: Dictionary in finished:
		var node: MeshInstance3D = entry["node"]
		node.visible = false
		_pool.append(node)
		_active.erase(entry)


func _advance_body_flashes() -> void:
	var finished: Array[Dictionary] = []

	for entry: Dictionary in _flashing:
		entry["frame"] = int(entry["frame"]) + 1
		var progress: float = float(entry["frame"]) / float(BODY_FLASH_FRAMES)
		var material: StandardMaterial3D = entry["material"]

		if progress >= 1.0:
			material.emission = entry["base"]
			material.emission_enabled = entry["base_enabled"]
			material.emission_energy_multiplier = 1.0
			finished.append(entry)
			continue

		material.emission_enabled = true
		material.emission = entry["colour"]
		material.emission_energy_multiplier = 1.6 * (1.0 - progress)

	for entry: Dictionary in finished:
		_flashing.erase(entry)


# --- pooling ----------------------------------------------------------------

func _acquire() -> MeshInstance3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var instance := MeshInstance3D.new()
	instance.mesh = _sphere
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_container.add_child(instance)
	return instance


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_find_meshes(child))
	return found


## Drop every live effect. Used by the Combat Lab's reset so the arena is
## genuinely clean rather than merely reset.
func clear_all() -> void:
	for entry: Dictionary in _active:
		var node: MeshInstance3D = entry["node"]
		node.visible = false
		_pool.append(node)
	_active.clear()

	for entry: Dictionary in _flashing:
		var material: StandardMaterial3D = entry["material"]
		material.emission = entry["base"]
		material.emission_enabled = entry["base_enabled"]
		material.emission_energy_multiplier = 1.0
	_flashing.clear()
