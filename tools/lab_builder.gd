# VOWED — Combat Lab scene builder.
#
# Invoked by tools/bootstrap_lab_scenes.gd, which loads this at RUNTIME so that
# the autoload singletons exist before any class referencing them is compiled.
# See that file for why the indirection is required.
#
# A BOOTSTRAP, not a build step: it writes the initial .tscn files in a
# guaranteed-valid form, after which the scenes are edited in the Godot editor
# and ARE the source of truth. Re-running overwrites editor changes.
#
# THE COMBAT LAB
#
# An isolated arena with a training dummy, frame-data overlay and instant reset.
# It exists BEFORE any real level, deliberately. Tuning combat inside a real
# environment is slow and confounded: terrain, props, lighting and enemy placement
# all affect what a hit feels like, so a change cannot be attributed. The Lab
# removes every variable except the combat itself.
#
# Collision layer values follow docs/TECH_STACK.md §5.3, computed from bit
# positions rather than written as magic numbers so a layer reassignment cannot
# silently desynchronise from the documented allocation.

extends RefCounted


# Layer bit values, derived from the documented bit positions.
const L_WORLD_STATIC: int = 1 << 0
const L_WORLD_DYNAMIC: int = 1 << 1
const L_PLAYER_BODY: int = 1 << 2
const L_ENEMY_BODY: int = 1 << 3
const L_PLAYER_HURTBOX: int = 1 << 4
const L_ENEMY_HURTBOX: int = 1 << 5
const L_CAMERA_COLLIDE: int = 1 << 9

const PLAYER_PATH: String = "res://scenes/actors/Player.tscn"
const DUMMY_PATH: String = "res://scenes/actors/TrainingDummy.tscn"
const LAB_PATH: String = "res://scenes/lab/CombatLab.tscn"

var _written: int = 0


## Build and write every Lab scene. Returns the number written.
func run() -> int:
	_write_player()
	_write_dummy()
	_write_lab()
	return _written


# --- player -----------------------------------------------------------------

func _write_player() -> void:
	var root := PlayerController.new()
	root.name = "Player"
	root.actor_id = &"player"
	root.display_name = "Player"
	root.max_health = 120.0
	root.max_poise = 70.0
	root.collision_layer = L_PLAYER_BODY
	# Collides with the world and with enemy bodies, so actors cannot pass
	# through each other — spacing is meaningless if they can.
	root.collision_mask = L_WORLD_STATIC | L_WORLD_DYNAMIC | L_ENEMY_BODY
	root.floor_snap_length = 0.35
	root.profile = load("res://data/actors/player_motion.tres") as MotionProfile

	_add_body_shape(root, root)
	_add_graybox_mesh(root, root, Color(0.42, 0.58, 0.78))

	var combat := CombatComponent.new()
	combat.name = "Combat"
	combat.library = load("res://data/attacks/player_base_library.tres") \
		as AttackLibrary
	combat.graph = load("res://data/combos/player_base_graph.tres") as ComboGraph
	root.add_child(combat)
	combat.owner = root
	root.combat = combat

	var intent := PlayerIntentSource.new()
	intent.name = "Intent"
	root.add_child(intent)
	intent.owner = root
	root.intent_source = intent

	_add_hurtbox(root, root, L_PLAYER_HURTBOX, combat)
	_add_camera_proxy(root, root)

	_save_scene(root, PLAYER_PATH)


# --- training dummy ---------------------------------------------------------

func _write_dummy() -> void:
	var root := Actor.new()
	root.name = "TrainingDummy"
	root.actor_id = &"training_dummy"
	root.display_name = "Training Dummy"
	# Deliberately high: the dummy exists to be hit repeatedly while frame data
	# is read, and a dummy that dies mid-combo interrupts the measurement.
	root.max_health = 9999.0
	root.max_poise = 120.0
	root.collision_layer = L_ENEMY_BODY
	root.collision_mask = L_WORLD_STATIC | L_WORLD_DYNAMIC | L_PLAYER_BODY
	root.floor_snap_length = 0.35
	root.profile = load("res://data/actors/player_motion.tres") as MotionProfile

	_add_body_shape(root, root)
	_add_graybox_mesh(root, root, Color(0.78, 0.44, 0.40))

	var combat := CombatComponent.new()
	combat.name = "Combat"
	# The dummy shares the PLAYER's move set on purpose: it proves that one
	# library and one graph drive any actor, and it means the dummy can throw
	# real attacks for testing trades, armour and defence without authoring a
	# second move set before M2.
	combat.library = load("res://data/attacks/player_base_library.tres") \
		as AttackLibrary
	combat.graph = load("res://data/combos/player_base_graph.tres") as ComboGraph
	root.add_child(combat)
	combat.owner = root
	root.combat = combat

	var intent := TrainingDummyIntent.new()
	intent.name = "Intent"
	intent.mode = TrainingDummyIntent.Mode.IDLE
	root.add_child(intent)
	intent.owner = root
	root.intent_source = intent

	_add_hurtbox(root, root, L_ENEMY_HURTBOX, combat)
	_add_camera_proxy(root, root)

	_save_scene(root, DUMMY_PATH)


# --- shared actor parts -----------------------------------------------------

func _add_body_shape(parent: Node, owner_node: Node) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "Body"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.72
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.86, 0.0)
	# Hidden by default; F2 reveals it.
	collision.visible = false
	parent.add_child(collision)
	collision.owner = owner_node


## Graybox stand-in geometry.
##
## Primitives, not asset-pack models, and that is the correct order of work:
## combat must be proven with readable placeholder shapes before any art is
## committed, or art gets made for mechanics that then change. A forward marker
## is included because facing is a combat-critical property that an unadorned
## capsule cannot communicate.
func _add_graybox_mesh(parent: Node, owner_node: Node, tint: Color) -> void:
	var body := MeshInstance3D.new()
	body.name = "Graybox"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.36
	capsule.height = 1.72
	body.mesh = capsule
	body.position = Vector3(0.0, 0.86, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.65
	body.material_override = material
	parent.add_child(body)
	body.owner = owner_node

	# A forward-pointing wedge. Facing is a combat-critical property — spacing,
	# whiff-punishing and directional routes all depend on reading it — and an
	# unadorned capsule communicates nothing about which way it is pointing.
	# Sized and offset to sit clearly PROUD of the 0.36 m capsule radius; an
	# earlier version was tucked inside it and therefore invisible, which defeats
	# the entire purpose.
	var marker := MeshInstance3D.new()
	marker.name = "FacingMarker"
	var wedge := PrismMesh.new()
	wedge.size = Vector3(0.34, 0.46, 0.30)
	marker.mesh = wedge
	# -90 deg about X maps the prism's +Y apex onto -Z, which is forward.
	marker.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	marker.position = Vector3(0.0, 1.18, -0.52)
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = tint.lightened(0.55)
	marker_material.roughness = 0.5
	marker.material_override = marker_material
	parent.add_child(marker)
	marker.owner = owner_node

	# A shoulder stripe, so facing stays readable from directly above or behind
	# where the wedge foreshortens to nothing.
	var stripe := MeshInstance3D.new()
	stripe.name = "FacingStripe"
	var bar := BoxMesh.new()
	bar.size = Vector3(0.62, 0.07, 0.07)
	stripe.mesh = bar
	stripe.position = Vector3(0.0, 1.52, -0.20)
	var stripe_material := StandardMaterial3D.new()
	stripe_material.albedo_color = tint.darkened(0.45)
	stripe.material_override = stripe_material
	parent.add_child(stripe)
	stripe.owner = owner_node


func _add_hurtbox(parent: Node, owner_node: Node, layer: int,
		combat: CombatComponent) -> void:
	var hurtbox := Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = layer
	# Mask 0: a hurtbox is a QUERY TARGET only. It detects nothing itself, which
	# is the whole point of resolving hits by explicit query rather than signals.
	hurtbox.collision_mask = 0
	hurtbox.combat = combat
	parent.add_child(hurtbox)
	hurtbox.owner = owner_node

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.40
	capsule.height = 1.66
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.86, 0.0)
	shape.visible = false
	hurtbox.add_child(shape)
	shape.owner = owner_node


## A collision proxy on the camera-only layer, so the camera spring is pushed out
## by actors without actors being pushed by the camera.
func _add_camera_proxy(parent: Node, owner_node: Node) -> void:
	var proxy := StaticBody3D.new()
	proxy.name = "CameraProxy"
	proxy.collision_layer = L_CAMERA_COLLIDE
	proxy.collision_mask = 0
	parent.add_child(proxy)
	proxy.owner = owner_node

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	shape.position = Vector3(0.0, 1.0, 0.0)
	shape.visible = false
	proxy.add_child(shape)
	shape.owner = owner_node


# --- the lab ----------------------------------------------------------------

func _write_lab() -> void:
	var root := Node3D.new()
	root.name = "CombatLab"
	root.set_script(load("res://scenes/lab/CombatLab.gd"))

	_add_environment(root)
	_add_arena(root)

	# --- player ---
	var player_scene: PackedScene = load(PLAYER_PATH) as PackedScene
	var player := player_scene.instantiate() as PlayerController
	player.name = "Player"
	player.position = Vector3(0.0, 0.2, 4.0)
	# Mouse stays free in the Lab so the editor remains usable while iterating —
	# click the viewport to capture it.
	player.capture_mouse = false
	root.add_child(player)
	player.owner = root

	# --- camera rig (a sibling, not a child: it lerps toward the player, and
	# parenting it would make it inherit the jitter it exists to smooth) ---
	var camera_rig := PlayerCamera.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = player
	camera_rig.position = Vector3(0.0, 1.6, 4.0)
	root.add_child(camera_rig)
	camera_rig.owner = root

	player.camera_rig = camera_rig

	# --- dummies at measured distances ---
	var dummy_scene: PackedScene = load(DUMMY_PATH) as PackedScene
	# Placed at known distances so spacing and attack reach can be READ rather
	# than guessed at: if jab_1 reaches the 1.6 m dummy but not the 3.0 m one,
	# its range is now a measured number.
	var placements: Array[Dictionary] = [
		{"name": "Dummy_Close", "pos": Vector3(0.0, 0.2, 1.6),
			"mode": TrainingDummyIntent.Mode.IDLE},
		{"name": "Dummy_Mid", "pos": Vector3(-3.4, 0.2, -0.6),
			"mode": TrainingDummyIntent.Mode.BLOCK},
		{"name": "Dummy_Far", "pos": Vector3(3.4, 0.2, -0.6),
			"mode": TrainingDummyIntent.Mode.AGGRESSIVE},
	]
	for placement: Dictionary in placements:
		var dummy := dummy_scene.instantiate() as Actor
		dummy.name = str(placement["name"])
		dummy.position = placement["pos"]
		# Face the player's start position. Actors face -Z, so a dummy left at
		# identity rotation would stand with its back turned — which reads as a
		# bug and hides the facing marker behind its own body.
		var to_player: Vector3 = Vector3(0.0, 0.0, 4.0) - dummy.position
		to_player.y = 0.0
		if to_player.length_squared() > 0.001:
			dummy.rotation.y = atan2(-to_player.x, -to_player.z)
		root.add_child(dummy)
		dummy.owner = root
		# The instantiated intent node is owned by the dummy's own scene, so its
		# mode is set on the instance rather than re-created here.
		var intent := dummy.get_node_or_null("Intent") as TrainingDummyIntent
		if intent != null:
			intent.mode = placement["mode"]

	# --- debug tooling ---
	var overlay := DebugOverlay.new()
	overlay.name = "DebugOverlay"
	overlay.subject = player
	root.add_child(overlay)
	overlay.owner = root

	var visualizer := HitboxVisualizer.new()
	visualizer.name = "HitboxVisualizer"
	root.add_child(visualizer)
	visualizer.owner = root

	_save_scene(root, LAB_PATH)


func _add_environment(root: Node3D) -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-52.0, -40.0, 0.0)
	light.light_energy = 1.05
	light.shadow_enabled = true
	root.add_child(light)
	light.owner = root

	var env := WorldEnvironment.new()
	env.name = "Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.42, 0.58)
	sky_material.sky_horizon_color = Color(0.58, 0.60, 0.64)
	sky_material.ground_bottom_color = Color(0.16, 0.17, 0.20)
	sky_material.ground_horizon_color = Color(0.42, 0.42, 0.44)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.55
	environment.ssao_enabled = false
	env.environment = environment
	root.add_child(env)
	env.owner = root


func _add_arena(root: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = L_WORLD_STATIC
	floor_body.collision_mask = 0
	root.add_child(floor_body)
	floor_body.owner = root

	var floor_collision := CollisionShape3D.new()
	floor_collision.name = "Shape"
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40.0, 0.4, 40.0)
	floor_collision.shape = floor_shape
	floor_collision.position = Vector3(0.0, -0.2, 0.0)
	floor_collision.visible = false
	floor_body.add_child(floor_collision)
	floor_collision.owner = root

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "FloorMesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.24, 0.25, 0.27)
	floor_material.roughness = 0.9
	floor_mesh.material_override = floor_material
	floor_body.add_child(floor_mesh)
	floor_mesh.owner = root

	# Distance markers every 2 m. Spacing is a first-class combat skill, so the
	# arena makes distance legible instead of leaving it to be eyeballed.
	for ring: int in range(1, 6):
		var marker := MeshInstance3D.new()
		marker.name = "Marker_%dm" % (ring * 2)
		var torus := TorusMesh.new()
		torus.inner_radius = float(ring) * 2.0 - 0.03
		torus.outer_radius = float(ring) * 2.0 + 0.03
		marker.mesh = torus
		marker.position = Vector3(0.0, 0.012, 0.0)
		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = Color(0.40, 0.43, 0.47)
		marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = marker_material
		root.add_child(marker)
		marker.owner = root


func _save_scene(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		printerr("FAILED to pack %s (error %d)" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		printerr("FAILED to save %s (error %d)" % [path, err])
		return
	print("  wrote %s" % path)
	_written += 1
