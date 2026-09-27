class_name CombatAnimator
extends Node

## Drives an actor's `AnimationPlayer` from combat state.
##
## THE RULE (docs/TECH_STACK.md §5.1): during an attack, animation is a SLAVE to
## the combat frame counter. The attack's frame is authoritative; the animation
## is seeked to match it. Animation never drives combat state, is never read to
## decide an outcome, and never advances on its own while an attack is running.
##
## Why it matters that the seek is one-directional:
##   * Hitstop works for free. The attack frame stops advancing, so the pose
##     freezes — which is exactly what makes a hit feel like it landed.
##   * Slow-motion and frame-step work for free, because the animation position
##     is a pure function of the combat frame.
##   * Combat stays frame-rate independent. A 144 fps machine renders the same
##     pose on the same logical frame as a 30 fps one.
##
## LOCOMOTION IS DIFFERENT and deliberately so. Walking is not frame-critical,
## nobody punishes you for being two frames into a jog cycle, and forcing it
## through the same seek would cost blending for no benefit. So locomotion uses
## ordinary playback with crossfades, and only COMBAT is slaved.

## The AnimationPlayer to drive. Resolved from the model subtree when unset.
@export var animation_player: AnimationPlayer

## The actor this animates. Resolved from the parent when unset.
@export var actor: Actor

@export_group("Locomotion clips")
@export var idle_anim: StringName = &"Idle"
@export var walk_anim: StringName = &"Walk"
@export var run_anim: StringName = &"Jog_Fwd"
# NOTE: the glTF importer strips a trailing `_Loop` from clip names, so the
# library's `Jump_Loop` is imported as `Jump`. Getting this wrong is silent in
# every automated check but obvious the moment anyone jumps, which is why
# referenced clips are now validated — see tests/integration/CombatPipeline.
@export var jump_rise_anim: StringName = &"Jump"
@export var jump_land_anim: StringName = &"Jump_Land"
@export var fall_anim: StringName = &"Jump"

@export_group("Reaction clips")
@export var hit_anim: StringName = &"Hit_Chest"
@export var hit_head_anim: StringName = &"Hit_Head"
@export var guard_anim: StringName = &"Sword_Idle"
@export var dodge_anim: StringName = &"Roll"
@export var death_anim: StringName = &"Death01"

@export_group("Tuning")
## Crossfade for locomotion changes. Combat transitions are deliberately
## instant — a blended attack start would soften exactly the frames the player
## is reading to react.
@export_range(0.0, 0.6, 0.01) var locomotion_blend: float = 0.16

## Speed below which the actor is considered idle, m/s.
@export_range(0.0, 3.0, 0.05) var idle_threshold: float = 0.35

## Speed above which the run clip is used rather than the walk clip, m/s.
@export_range(0.5, 12.0, 0.1) var run_threshold: float = 3.4

var _current_non_combat: StringName = &""
var _last_attack_id: StringName = &""
var _missing_reported: Dictionary = {}


func _ready() -> void:
	if actor == null:
		actor = get_parent() as Actor
	if animation_player == null:
		animation_player = _find_player(self if actor == null else actor)
	if animation_player == null:
		GameEvents.report_assertion("CombatAnimator",
			"no AnimationPlayer found for '%s'; it will not animate"
				% (actor.name if actor != null else name))

	# Every connecting hit must RESTART the flinch, not merely request the clip
	# that is already playing. Without this the second and later hits of a combo
	# produce no visible reaction at all — the target silently absorbs them and
	# a four-hit string reads as a single hit. State changes alone cannot express
	# this, because the victim never leaves HITSTUN between the hits.
	if actor != null and actor.combat != null:
		actor.combat.damage_received.connect(_on_damage_received)


func _find_player(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null


## Called once per combat frame by the actor, after combat state has advanced.
func update() -> void:
	if animation_player == null or actor == null or actor.combat == null:
		return

	var combat: CombatComponent = actor.combat

	if combat.state == CombatState.Id.ATTACKING and combat.attack != null:
		_drive_attack(combat)
		return

	_last_attack_id = &""
	_drive_non_combat(combat)


# --- attacks: slaved to the frame counter -----------------------------------

func _drive_attack(combat: CombatComponent) -> void:
	var attack: AttackData = combat.attack
	var clip: StringName = attack.animation
	if not _has(clip):
		return

	# Start the clip once, then stop it advancing on its own. From here the
	# position is set explicitly every frame.
	if _last_attack_id != attack.id:
		_last_attack_id = attack.id
		animation_player.play(String(clip))
		_current_non_combat = &""

	# Pausing is what makes this a SEEK rather than a playback. Without it the
	# clip would also advance by delta and fight the seek, producing a subtle
	# drift that looks like animation jitter and is miserable to diagnose.
	animation_player.pause()

	var length: float = animation_player.get_animation(String(clip)).length
	var position: float = attack.animation_time(combat.attack_frame, length)
	animation_player.seek(position, true)


# --- everything else: ordinary playback -------------------------------------

func _drive_non_combat(combat: CombatComponent) -> void:
	var clip: StringName = _clip_for_state(combat)
	if clip == &"" or not _has(clip):
		return
	if _current_non_combat == clip:
		return

	_current_non_combat = clip
	animation_player.play(String(clip), locomotion_blend)


func _clip_for_state(combat: CombatComponent) -> StringName:
	match combat.state:
		CombatState.Id.DEAD:
			return death_anim
		CombatState.Id.DODGING:
			return dodge_anim
		CombatState.Id.GUARDING, CombatState.Id.PARRYING:
			return guard_anim
		CombatState.Id.HITSTUN, CombatState.Id.STAGGERED:
			return hit_anim
		CombatState.Id.LAUNCHED:
			return hit_head_anim
		CombatState.Id.KNOCKDOWN, CombatState.Id.WAKEUP:
			return hit_anim
		_:
			return _locomotion_clip()


func _locomotion_clip() -> StringName:
	if not actor.is_on_floor():
		return jump_rise_anim if actor.velocity.y > 0.0 else fall_anim

	var speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
	if speed < idle_threshold:
		return idle_anim
	return run_anim if speed >= run_threshold else walk_anim


## Restart the reaction clip on every connecting hit.
##
## Deliberately picks a heavier clip for a heavier reaction, so the player can
## read HOW hard they hit from the target's body rather than from a number.
func _on_damage_received(result: HitResult) -> void:
	if animation_player == null or actor == null or actor.combat == null:
		return
	# A guarded hit has no reaction to play; guard already has its own pose.
	if result.reaction == null:
		return

	var clip: StringName = hit_anim
	if CombatTypes.reaction_is_airborne(result.reaction.kind) \
			or result.reaction.kind == CombatTypes.ReactionKind.HEAVY:
		clip = hit_head_anim
	if not _has(clip):
		return

	animation_player.play(String(clip))
	# From zero, explicitly. `play()` on the clip already playing would resume
	# it mid-flinch, which is exactly the case this exists to fix.
	animation_player.seek(0.0, true)
	_current_non_combat = clip


# --- helpers ----------------------------------------------------------------

func _has(clip: StringName) -> bool:
	if clip == &"":
		return false
	if animation_player.has_animation(String(clip)):
		return true
	# Report each missing clip ONCE. A per-frame error would bury every other
	# message in the log, which is how a real problem gets missed.
	if not _missing_reported.has(clip):
		_missing_reported[clip] = true
		push_warning("[CombatAnimator] '%s' has no animation named '%s'"
			% [actor.name if actor != null else name, clip])
	return false


## Animation clips this animator refers to. Used by the content validator to
## check every referenced clip exists before anything runs.
func referenced_clips() -> Array[StringName]:
	return [
		idle_anim, walk_anim, run_anim, jump_rise_anim, jump_land_anim,
		fall_anim, hit_anim, hit_head_anim, guard_anim, dodge_anim, death_anim,
	]
