extends Node3D

## Locate the impact moment inside each combat animation.
##
##     godot --headless --path . res://tools/ImpactProbe.tscn
##
## WHY THIS EXISTS
##
## An attack's authored frame data and its source animation are different
## lengths — jab_1 is 14 frames, Punch_Jab is 50. Mapping one onto the other
## requires the animation's IMPACT (the moment of full extension) to land on the
## attack's ACTIVE frames. Get that wrong and the hit reads as early or late no
## matter how correct the numbers are, which is exactly the "combat feels off"
## complaint that cannot be diagnosed from frame data alone.
##
## Rather than eyeball it, this samples the striking limb every frame and reports
## where it is furthest from the body. A measurement is repeatable, and survives
## an animation being swapped for a better one later.
##
## It is a SCENE rather than a `-s` script because a script run with `-s` never
## processes the tree, so the AnimationPlayer stays at its bind pose and every
## clip reports impact on frame 0.

const LIBRARY: String = "res://assets/animations/quaternius_universal_animation_library/AnimationLibrary_Godot_Standard.gltf"

## Clips to measure, and which bones do the striking.
const TARGETS: Dictionary = {
	"Punch_Jab": ["DEF-hand.L", "DEF-hand.R"],
	"Punch_Cross": ["DEF-hand.L", "DEF-hand.R"],
	"Punch_Enter": ["DEF-hand.L", "DEF-hand.R"],
	"Sword_Attack": ["DEF-hand.L", "DEF-hand.R"],
	"Spell_Simple_Shoot": ["DEF-hand.L", "DEF-hand.R"],
	"Hit_Chest": ["DEF-spine.003"],
	"Roll": ["DEF-head"],
}

const ROOT_BONE: String = "DEF-hips"


func _ready() -> void:
	var packed: PackedScene = load(LIBRARY) as PackedScene
	if packed == null:
		printerr("could not load the animation library")
		get_tree().quit(1)
		return

	var instance: Node = packed.instantiate()
	add_child(instance)
	await get_tree().process_frame

	var player: AnimationPlayer = instance.get_node("AnimationPlayer")
	var skeleton: Skeleton3D = instance.get_node("Rig/Skeleton3D")

	# Manual advance: the probe controls the clock, so a sampled pose
	# corresponds exactly to the time asked for.
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	print("clip                  len     impact     frame   extension   position")
	print("".lpad(72, "-"))

	for clip: String in TARGETS:
		if not player.has_animation(clip):
			print("%-20s MISSING" % clip)
			continue
		await _measure(player, skeleton, clip, TARGETS[clip])

	get_tree().quit(0)


func _measure(player: AnimationPlayer, skeleton: Skeleton3D, clip: String,
		bones: Array) -> void:
	var animation: Animation = player.get_animation(clip)
	var length: float = animation.length
	var frames: int = maxi(1, int(round(length * 60.0)))

	var root_index: int = skeleton.find_bone(ROOT_BONE)
	var bone_indices: Array[int] = []
	for bone_name: String in bones:
		var index: int = skeleton.find_bone(bone_name)
		if index >= 0:
			bone_indices.append(index)
	if bone_indices.is_empty() or root_index < 0:
		print("%-20s bones not found" % clip)
		return

	player.play(clip)

	var best_distance: float = -1.0
	var best_frame: int = 0

	for frame: int in frames + 1:
		player.seek(float(frame) / 60.0, true)
		player.advance(0.0)
		await get_tree().process_frame
		skeleton.force_update_all_bone_transforms()

		var origin: Vector3 = skeleton.get_bone_global_pose(root_index).origin
		for index: int in bone_indices:
			var offset: Vector3 = skeleton.get_bone_global_pose(index).origin \
				- origin
			# Forward reach specifically, not raw distance: a raised arm is not
			# an impact. Weighted toward the actor's facing axis (-Z).
			var reach: float = -offset.z * 1.6 + offset.length() * 0.4
			if reach > best_distance:
				best_distance = reach
				best_frame = frame

	player.stop()

	print("%-20s %6.3fs  %6.3fs  f%-4d  %7.3f   %5.1f%% in" % [
		clip, length, float(best_frame) / 60.0, best_frame, best_distance,
		100.0 * float(best_frame) / float(frames),
	])
