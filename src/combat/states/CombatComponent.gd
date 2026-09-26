class_name CombatComponent
extends Node

## Executes frame data. The engine of the combat system.
##
## Attached to any actor that fights — player and enemy alike, with the identical
## component. The only difference between them is where their `ActorIntent` comes
## from (docs/ARCHITECTURE.md §4). That is a design requirement, not a
## convenience: enemies must be able to out-play the player mechanically, which is
## impossible if they run a different combat model.
##
## Advanced by `tick()` exactly once per logical combat frame. It never reads
## `delta`, never reads an animation's position, and never uses a timer. Frames
## are the only unit of time here.
##
## TWO INDEPENDENT GATES decide whether an action may start, and keeping them
## separate is what keeps a large move set authorable:
##
##   1. ROUTING — does `ComboGraph` have an edge for this input in this
##      situation? (*what* may follow *what*)
##   2. TIMING — does the current attack have a cancel window open right now,
##      given what it has touched? (*when* it may be left)
##
## Routing lives in the graph; timing lives in the attack. Neither knows about
## the other, so a designer can retime an attack without touching routes, and
## reroute a move set without retiming attacks.

## Emitted on every state transition. The debug overlay and animation driver
## both hang off this rather than polling.
signal state_changed(from_state: CombatState.Id, to_state: CombatState.Id)

## Emitted when an attack begins executing.
signal attack_started(attack: AttackData, cancelled_from: StringName)

## Emitted when an attack finishes or is cancelled out of.
signal attack_ended(attack_id: StringName, was_cancelled: bool)

## Emitted every frame an attack advances, for the frame-data readout. Not
## emitted during hitstop, because the attack genuinely is not advancing.
signal attack_frame_advanced(attack: AttackData, attack_frame: int)

## The move set's attacks. Without one the actor cannot attack at all.
@export var library: AttackLibrary

## The move set's routes.
@export var graph: ComboGraph


var state: CombatState.Id = CombatState.Id.NEUTRAL

## Frames spent in the current state. Reset on every transition.
var state_frame: int = 0

## Currently executing attack, or null.
var attack: AttackData = null

## Frames into the current attack (0-based). Frozen during hitstop.
var attack_frame: int = 0

## Hits landed in the current combo. Reset when a combo ends.
var combo_length: int = 0

## Frames of hitstop remaining. While non-zero, nothing advances — which is what
## gives a hit its weight.
var hitstop_remaining: int = 0

## Has the current attack connected cleanly / been guarded? Drives contact
## requirements on cancel windows and combo edges.
var did_hit: bool = false
var did_guard: bool = false

## Armour hits remaining on the current attack.
var armor_remaining: int = 0

## Frames of hitstun/stagger/launch left to serve.
var stun_remaining: int = 0

## Set by the owning actor each frame, since the component does not do physics.
var grounded: bool = true

## victim instance id -> Array of hit groups already connected. This is what stops
## a moving hitbox connecting once per frame — the classic "my attack does 900
## damage" defect. Cleared when an attack starts.
var _connected_groups: Dictionary = {}

var _context: ComboContext = ComboContext.new()


# --- per-frame advance ------------------------------------------------------

## Advance exactly one logical combat frame. Called by the actor from the
## combat tick, never from `_process` or `_physics_process` directly.
func tick() -> void:
	# Hitstop freezes everything: the attack does not advance, stun does not
	# tick down, animation does not move. Both actors are held.
	if hitstop_remaining > 0:
		hitstop_remaining -= 1
		return

	state_frame += 1

	match state:
		CombatState.Id.ATTACKING:
			_tick_attacking()
		CombatState.Id.HITSTUN, CombatState.Id.STAGGERED, \
		CombatState.Id.LAUNCHED, CombatState.Id.KNOCKDOWN:
			_tick_stunned()
		CombatState.Id.PARRYING:
			_tick_parrying()
		CombatState.Id.DODGING:
			_tick_dodging()
		CombatState.Id.WAKEUP:
			_tick_wakeup()
		_:
			pass


func _tick_attacking() -> void:
	if attack == null:
		_transition(CombatState.Id.NEUTRAL)
		return

	attack_frame += 1
	attack_frame_advanced.emit(attack, attack_frame)

	# An air attack is cut short by landing, so aerial routes end on contact with
	# the ground instead of playing out awkwardly.
	if attack.cancelled_by_landing and grounded \
			and attack.stance == CombatTypes.Stance.AIRBORNE:
		_finish_attack(false)
		return

	if attack_frame >= attack.total_frames():
		_finish_attack(false)


func _tick_stunned() -> void:
	stun_remaining -= 1
	if stun_remaining > 0:
		return
	# A knockdown routes through WAKEUP rather than straight to neutral, so
	# getting up is a real situation the opponent can pressure.
	if state == CombatState.Id.KNOCKDOWN:
		_transition(CombatState.Id.WAKEUP)
		stun_remaining = WAKEUP_FRAMES
	else:
		_transition(CombatState.Id.NEUTRAL)


func _tick_parrying() -> void:
	# The parry window is deliberately short. Past it, the actor is left in guard
	# rather than neutral, so a failed parry attempt still defends — a mistimed
	# parry should cost the reward, not the defence.
	if state_frame > PARRY_WINDOW_FRAMES:
		_transition(CombatState.Id.GUARDING)


func _tick_dodging() -> void:
	if state_frame >= DODGE_FRAMES:
		_transition(CombatState.Id.NEUTRAL)


func _tick_wakeup() -> void:
	stun_remaining -= 1
	if stun_remaining <= 0:
		_transition(CombatState.Id.NEUTRAL)


# --- defensive timing constants ---------------------------------------------
#
# Deliberately const rather than @export: these define the game's defensive feel
# and must be identical for every actor. Per-actor parry windows would make
# defence unreadable.

## Frames of perfect-parry window. Tight enough that parrying is a genuine skill,
## wide enough to be learnable — this is the number most likely to need tuning
## from playtests, and the one most likely to be tuned by feel rather than data.
const PARRY_WINDOW_FRAMES: int = 5

## Total dodge duration.
const DODGE_FRAMES: int = 22

## Dodge invulnerability, `[first, last]` inclusive within the dodge.
## Starting at 1 rather than 0 means a dodge cannot be used as a reactionless
## panic button on the exact frame of contact.
const DODGE_INVULN: Vector2i = Vector2i(1, 11)

## Frames spent getting up from a knockdown.
const WAKEUP_FRAMES: int = 18

## Wake-up invulnerability, so getting up is not a guaranteed free punish.
const WAKEUP_INVULN: Vector2i = Vector2i(0, 12)


# --- starting actions -------------------------------------------------------

## Attempt to start an action. Returns true if it started.
##
## `context` must already carry the situational fields the caller owns — target
## state and distance, direction, Soul state. This component fills in its own
## state via `fill_context()`.
func try_action(action: CombatAction.Id, context: ComboContext) -> bool:
	if state == CombatState.Id.DEAD:
		return false
	if CombatState.is_helpless(state):
		return false

	# --- non-attack actions resolve without the graph ---
	match action:
		CombatAction.Id.GUARD:
			return _try_guard()
		CombatAction.Id.DASH:
			if _can_leave_for(CombatTypes.CancelInto.DASH):
				return _start_dodge()
			return false
		_:
			pass

	if library == null or graph == null:
		return false

	# --- gate 1: routing ---
	fill_context(context)
	var edge: ComboEdge = graph.resolve_edge(action, context)
	if edge == null:
		return false

	var target: AttackData = library.get_attack(edge.to)
	if target == null:
		# A route to a non-existent attack. The content validator should have
		# caught this; surfacing it at runtime too means it cannot hide in a
		# build that skipped validation.
		GameEvents.report_assertion("CombatComponent",
			"route %s points at attack '%s', which is not in library '%s'"
				% [edge.describe(), edge.to,
					library.id if library != null else &"<none>"])
		return false

	# --- gate 2: timing ---
	if state == CombatState.Id.ATTACKING:
		if not _attack_cancel_permitted(edge):
			return false
	elif not CombatState.accepts_free_action(state):
		return false

	# --- gate 3: the attack's own requirements ---
	if not _attack_usable(target, context):
		return false

	_begin_attack(target, edge.preserves_combo)
	return true


## Is a cancel out of the current attack into `edge` allowed right now?
##
## An edge's own frame window, when authored, is the tighter constraint and
## replaces the attack's cancel windows. That is for just-frame links where one
## route out of an attack needs precision the others do not.
func _attack_cancel_permitted(edge: ComboEdge) -> bool:
	if attack == null:
		return true
	if edge.require_frame_window.x >= 0:
		return attack_frame >= edge.require_frame_window.x \
			and attack_frame <= edge.require_frame_window.y
	return attack.find_cancel(CombatTypes.CancelInto.ATTACK, attack_frame,
		did_hit, did_guard) != null


## Does the current state permit leaving for a non-attack action?
func _can_leave_for(action: CombatTypes.CancelInto) -> bool:
	if CombatState.accepts_free_action(state):
		return true
	if state == CombatState.Id.ATTACKING and attack != null:
		return attack.find_cancel(action, attack_frame, did_hit, did_guard) != null
	return false


func _attack_usable(target: AttackData, context: ComboContext) -> bool:
	if grounded and not target.can_be_used_grounded():
		return false
	if not grounded and not target.can_be_used_airborne():
		return false
	if target.resonance_cost > context.resonance:
		return false
	if target.requires_manifestation and not context.manifesting:
		return false
	return true


func _try_guard() -> bool:
	if state == CombatState.Id.GUARDING or state == CombatState.Id.PARRYING:
		return false
	if not _can_leave_for(CombatTypes.CancelInto.GUARD):
		return false
	# Pressing guard opens the parry window first. Guard is therefore the same
	# input as parry, distinguished only by timing — which is what makes perfect
	# parry a skill expression rather than a separate resource.
	_transition(CombatState.Id.PARRYING)
	return true


func _start_dodge() -> bool:
	if state == CombatState.Id.DODGING:
		return false
	_transition(CombatState.Id.DODGING)
	return true


func release_guard() -> void:
	if state == CombatState.Id.GUARDING or state == CombatState.Id.PARRYING:
		_transition(CombatState.Id.NEUTRAL)


func _begin_attack(target: AttackData, preserve_combo: bool) -> void:
	var previous: StringName = attack.id if attack != null else &""
	var was_attacking: bool = state == CombatState.Id.ATTACKING

	if was_attacking:
		attack_ended.emit(previous, true)
	if not preserve_combo:
		_end_combo(true)

	attack = target
	attack_frame = 0
	did_hit = false
	did_guard = false
	armor_remaining = target.interrupt_armor
	_connected_groups.clear()

	_transition(CombatState.Id.ATTACKING)
	attack_started.emit(target, previous)


func _finish_attack(cancelled: bool) -> void:
	var finished_id: StringName = attack.id if attack != null else &""
	attack = null
	attack_frame = 0
	_connected_groups.clear()
	attack_ended.emit(finished_id, cancelled)

	# An attack running to completion without connecting drops the combo. This is
	# what makes a dropped combo a real failure state rather than a pause.
	if not did_hit:
		_end_combo(true)

	did_hit = false
	did_guard = false
	armor_remaining = 0
	_transition(CombatState.Id.NEUTRAL)


# --- receiving hits ---------------------------------------------------------

## Apply an incoming hit. Called by the resolver, never directly by an attacker.
##
## Returns the contact result, which the resolver uses to decide what feedback to
## raise. Deciding the result HERE, on the defender, is deliberate: the defender
## owns its own guard, parry and invulnerability state, and an attacker that
## decided its own hit outcomes could not be trusted.
func receive_hit(incoming: AttackData, attacker_facing: Vector3,
		hit_group: int, attacker_id: int) -> CombatTypes.ContactResult:
	if state == CombatState.Id.DEAD:
		return CombatTypes.ContactResult.MISS

	# One contact per hit group per attacker, so a moving volume connects once.
	var groups: Array = _connected_groups.get(attacker_id, [])
	if groups.has(hit_group):
		return CombatTypes.ContactResult.MISS

	if is_invulnerable():
		return CombatTypes.ContactResult.DODGED

	if state == CombatState.Id.PARRYING \
			and incoming.height != CombatTypes.Height.UNBLOCKABLE:
		_register_contact(attacker_id, hit_group)
		# A successful parry leaves the defender in guard, ready to punish.
		_transition(CombatState.Id.GUARDING)
		return CombatTypes.ContactResult.PARRIED

	if state == CombatState.Id.GUARDING and _guard_covers(incoming):
		_register_contact(attacker_id, hit_group)
		return CombatTypes.ContactResult.GUARDED

	_register_contact(attacker_id, hit_group)

	# Armour absorbs the reaction but not the damage, which is what lets a heavy
	# attack be committed rather than merely slow.
	if armor_remaining > 0:
		armor_remaining -= 1
		return CombatTypes.ContactResult.ARMORED

	_enter_hitstun(incoming, attacker_facing)
	return CombatTypes.ContactResult.HIT


func _guard_covers(incoming: AttackData) -> bool:
	if incoming.height == CombatTypes.Height.UNBLOCKABLE:
		return false
	# Crouching guard and overheads arrive with the crouch state at M2; a
	# standing guard currently covers everything else.
	return true


func _enter_hitstun(incoming: AttackData, attacker_facing: Vector3) -> void:
	var reaction: HitReaction = incoming.on_hit
	if reaction == null:
		stun_remaining = 10
		_transition(CombatState.Id.HITSTUN)
		return

	stun_remaining = reaction.hitstun_frames

	if reaction.causes_knockdown:
		_transition(CombatState.Id.KNOCKDOWN)
	elif reaction.is_airborne_reaction():
		_transition(CombatState.Id.LAUNCHED)
		GameEvents.actor_launched.emit(get_parent(),
			attacker_facing * reaction.launch_velocity.z
				+ Vector3.UP * reaction.launch_velocity.y)
	elif reaction.kind == CombatTypes.ReactionKind.CRUMPLE \
			or reaction.kind == CombatTypes.ReactionKind.SPIN:
		_transition(CombatState.Id.STAGGERED)
	else:
		_transition(CombatState.Id.HITSTUN)

	# Being hit ends the victim's own attack immediately.
	if attack != null:
		var interrupted: StringName = attack.id
		attack = null
		attack_frame = 0
		did_hit = false
		did_guard = false
		attack_ended.emit(interrupted, true)


func _register_contact(attacker_id: int, hit_group: int) -> void:
	if not _connected_groups.has(attacker_id):
		_connected_groups[attacker_id] = []
	(_connected_groups[attacker_id] as Array).append(hit_group)


## Record that the actor's own current attack connected. Called by the resolver
## on the ATTACKER.
func register_own_contact(result: CombatTypes.ContactResult) -> void:
	match result:
		CombatTypes.ContactResult.HIT, CombatTypes.ContactResult.ARMORED, \
		CombatTypes.ContactResult.TRADED:
			did_hit = true
			combo_length += 1
			if attack != null:
				hitstop_remaining = attack.hitstop
			GameEvents.combo_extended.emit(get_parent(), combo_length)
		CombatTypes.ContactResult.GUARDED:
			did_guard = true
			if attack != null:
				hitstop_remaining = attack.guard_hitstop
		_:
			pass


func apply_hitstop(frames: int) -> void:
	hitstop_remaining = maxi(hitstop_remaining, frames)


# --- queries ----------------------------------------------------------------

func is_invulnerable() -> bool:
	if state == CombatState.Id.DODGING:
		return state_frame >= DODGE_INVULN.x and state_frame <= DODGE_INVULN.y
	if state == CombatState.Id.WAKEUP:
		return state_frame >= WAKEUP_INVULN.x and state_frame <= WAKEUP_INVULN.y
	if state == CombatState.Id.ATTACKING and attack != null:
		return attack.is_invulnerable_on(attack_frame)
	return false


## Hitboxes live this frame. Empty unless mid-attack inside an active window.
func active_hitboxes() -> Array[HitboxKeyframe]:
	if state != CombatState.Id.ATTACKING or attack == null:
		return [] as Array[HitboxKeyframe]
	if hitstop_remaining > 0:
		return [] as Array[HitboxKeyframe]
	return attack.active_hitboxes_on(attack_frame)


func is_in_hitstop() -> bool:
	return hitstop_remaining > 0


func is_attacking() -> bool:
	return state == CombatState.Id.ATTACKING


func can_act() -> bool:
	return not CombatState.is_helpless(state) and hitstop_remaining == 0


## Motion keyframes applying this frame. Read by the movement system.
func current_motion() -> Array[MotionKeyframe]:
	if state != CombatState.Id.ATTACKING or attack == null \
			or hitstop_remaining > 0:
		return [] as Array[MotionKeyframe]
	return attack.motion_on(attack_frame)


## Write this component's own state into `context`. The caller fills the fields
## it owns (target, direction, Soul) before calling `try_action()`.
func fill_context(context: ComboContext) -> void:
	context.current_attack = attack.id if attack != null else &""
	context.attack_frame = attack_frame
	context.grounded = grounded
	context.did_hit = did_hit
	context.did_guard = did_guard
	context.combo_length = combo_length
	context.frame = CombatClock.frame


## This actor's state as a combo-edge target condition, for whoever is attacking
## it. Routing and state therefore cannot drift apart.
func as_target_state() -> CombatTypes.TargetState:
	return CombatState.to_target_state(state, grounded)


# --- transitions ------------------------------------------------------------

func _transition(to_state: CombatState.Id) -> void:
	if state == to_state:
		# Re-entering the same state still resets its frame counter — an
		# important case for repeated dodges and re-guards.
		state_frame = 0
		return
	var from_state: CombatState.Id = state
	state = to_state
	state_frame = 0

	if CombatState.is_helpless(to_state):
		_end_combo(true)

	state_changed.emit(from_state, to_state)


func _end_combo(dropped: bool) -> void:
	if combo_length <= 0:
		return
	GameEvents.combo_ended.emit(get_parent(), combo_length, dropped)
	combo_length = 0


func kill() -> void:
	stun_remaining = 0
	attack = null
	_transition(CombatState.Id.DEAD)
	GameEvents.actor_defeated.emit(get_parent())


## Full reset. Used by the Combat Lab's instant-reset, which is what makes
## iterating on frame data fast.
func reset() -> void:
	attack = null
	attack_frame = 0
	combo_length = 0
	hitstop_remaining = 0
	stun_remaining = 0
	did_hit = false
	did_guard = false
	armor_remaining = 0
	_connected_groups.clear()
	state = CombatState.Id.NEUTRAL
	state_frame = 0


## One-line state summary for the debug overlay.
func describe() -> String:
	var base: String = "%s@%d" % [CombatState.name_of(state), state_frame]
	if attack != null:
		var phase: String = "startup"
		if attack.is_active_window(attack_frame):
			phase = "ACTIVE"
		elif attack_frame > attack.last_active_frame():
			phase = "recovery"
		base += "  %s f%d/%d %s" % [
			str(attack.id), attack_frame, attack.total_frames() - 1, phase]
	if hitstop_remaining > 0:
		base += "  hitstop %d" % hitstop_remaining
	if combo_length > 0:
		base += "  combo %d" % combo_length
	return base
