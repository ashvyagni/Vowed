class_name HitResolver
extends RefCounted

## Resolves every active hitbox against every hurtbox, once per combat frame.
##
## An EXPLICIT, ORDERED pass — not physics callbacks
## (docs/TECH_STACK.md §5.2). The ordering is the point: it makes hit resolution
## deterministic, inspectable, and able to express same-frame trade rules, none
## of which `Area3D.body_entered` can do.
##
## Three phases, in this order, for a specific reason:
##
##   1. GATHER   — collect every candidate contact without applying anything.
##   2. ADJUDICATE — decide mutual contacts (A hits B while B hits A) by
##                 priority. This is only possible because nothing was applied
##                 in phase 1: an attack cannot be cancelled by a hit it was
##                 simultaneously landing.
##   3. APPLY    — commit outcomes and raise feedback.
##
## Collapsing these into one loop would make the result depend on iteration
## order, which is how a fighting system ends up with "whoever is earlier in the
## scene tree wins" — a bug that is invisible until two players notice it
## disagrees with itself.

## Maximum hurtboxes one hitbox query may return. Generous; exceeding it would
## mean an attack overlapping an implausible number of actors.
const MAX_QUERY_RESULTS: int = 16


## One candidate contact, before adjudication.
class Candidate extends RefCounted:
	var attacker: CombatComponent
	var attacker_node: Node3D
	var victim: CombatComponent
	var hurtbox: Hurtbox
	var hitbox: HitboxKeyframe
	var attack: AttackData
	var position: Vector3
	var direction: Vector3


## Resolve one combat frame. Returns every contact that actually occurred, for
## the debug overlay and combat logging.
##
## `attackers` are the components that may be mid-attack; `space` is the physics
## space to query. Passing the space in rather than reaching for a global keeps
## this testable against a stub.
static func resolve_frame(attackers: Array[CombatComponent],
		space: PhysicsDirectSpaceState3D) -> Array[HitResult]:
	var candidates: Array[Candidate] = _gather(attackers, space)
	if candidates.is_empty():
		return [] as Array[HitResult]
	var accepted: Array[Candidate] = _adjudicate(candidates)
	return _apply(accepted)


# --- phase 1: gather --------------------------------------------------------

static func _gather(attackers: Array[CombatComponent],
		space: PhysicsDirectSpaceState3D) -> Array[Candidate]:
	var candidates: Array[Candidate] = []

	for attacker: CombatComponent in attackers:
		if attacker == null or not attacker.is_attacking():
			continue
		var boxes: Array[HitboxKeyframe] = attacker.active_hitboxes()
		if boxes.is_empty():
			continue

		var attacker_node: Node3D = attacker.get_parent() as Node3D
		if attacker_node == null:
			continue

		for box: HitboxKeyframe in boxes:
			if box.shape == null:
				continue
			candidates.append_array(
				_query_hitbox(attacker, attacker_node, box, space))

	return candidates


static func _query_hitbox(attacker: CombatComponent, attacker_node: Node3D,
		box: HitboxKeyframe, space: PhysicsDirectSpaceState3D
		) -> Array[Candidate]:
	var found: Array[Candidate] = []

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box.shape
	# The offset is authored in the actor's LOCAL space, so the same data works
	# at any facing.
	params.transform = attacker_node.global_transform.translated_local(box.offset)
	params.collision_mask = _opposing_hurtbox_mask(attacker_node)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = [attacker_node.get_rid()]

	var results: Array[Dictionary] = space.intersect_shape(params,
		MAX_QUERY_RESULTS)

	for result: Dictionary in results:
		var hurtbox: Hurtbox = result.get("collider", null) as Hurtbox
		if hurtbox == null or not hurtbox.is_receptive():
			continue
		if hurtbox.combat == attacker:
			continue  # never hit yourself

		var candidate := Candidate.new()
		candidate.attacker = attacker
		candidate.attacker_node = attacker_node
		candidate.victim = hurtbox.combat
		candidate.hurtbox = hurtbox
		candidate.hitbox = box
		candidate.attack = attacker.attack
		candidate.position = hurtbox.global_position
		var offset: Vector3 = hurtbox.global_position - attacker_node.global_position
		offset.y = 0.0
		candidate.direction = offset.normalized() if offset.length_squared() > 0.001 \
			else -attacker_node.global_transform.basis.z
		found.append(candidate)

	return found


## Which hurtbox layer this attacker should hit. Derived from the attacker's own
## body layer so an actor can never hit its own side, without every attack
## having to author a mask.
static func _opposing_hurtbox_mask(attacker_node: Node3D) -> int:
	const PLAYER_BODY_BIT: int = 1 << 2      # layer 3
	const PLAYER_HURTBOX_BIT: int = 1 << 4   # layer 5
	const ENEMY_HURTBOX_BIT: int = 1 << 5    # layer 6

	var body := attacker_node as CollisionObject3D
	if body != null and (body.collision_layer & PLAYER_BODY_BIT) != 0:
		return ENEMY_HURTBOX_BIT
	return PLAYER_HURTBOX_BIT


# --- phase 2: adjudicate ---------------------------------------------------

## Decide which candidates stand, resolving mutual contacts by attack priority.
##
## Nothing has been applied yet, which is what makes a genuine trade expressible:
## if both attacks would land on the same frame at equal priority, BOTH land.
## Resolving as we gathered would let whichever was processed first cancel the
## other's attack and silently win.
static func _adjudicate(candidates: Array[Candidate]) -> Array[Candidate]:
	var accepted: Array[Candidate] = []

	for candidate: Candidate in candidates:
		var mutual: Candidate = _find_mutual(candidates, candidate)
		if mutual == null:
			accepted.append(candidate)
			continue

		var own_priority: int = candidate.attack.priority
		var other_priority: int = mutual.attack.priority

		if own_priority > other_priority:
			accepted.append(candidate)
		elif own_priority == other_priority:
			# A true trade: both connect. Recorded so feedback can present it
			# as a trade rather than as two unrelated hits.
			candidate.hurtbox.set_meta(&"traded", true)
			accepted.append(candidate)
		# Lower priority: dropped. The opponent's attack beat it outright.

	return accepted


static func _find_mutual(candidates: Array[Candidate],
		candidate: Candidate) -> Candidate:
	for other: Candidate in candidates:
		if other.attacker == candidate.victim \
				and other.victim == candidate.attacker:
			return other
	return null


# --- phase 3: apply --------------------------------------------------------

static func _apply(accepted: Array[Candidate]) -> Array[HitResult]:
	var results: Array[HitResult] = []

	for candidate: Candidate in accepted:
		var was_trade: bool = candidate.hurtbox.has_meta(&"traded")
		if was_trade:
			candidate.hurtbox.remove_meta(&"traded")

		var attacker_facing: Vector3 = \
			-candidate.attacker_node.global_transform.basis.z

		# The DEFENDER decides the outcome: it owns its guard, parry and
		# invulnerability state. An attacker adjudicating its own hits could
		# not be trusted to respect them.
		var outcome: CombatTypes.ContactResult = candidate.victim.receive_hit(
			candidate.attack, attacker_facing, candidate.hitbox.hit_group,
			candidate.attacker_node.get_instance_id())

		if outcome == CombatTypes.ContactResult.MISS:
			continue

		if was_trade and outcome == CombatTypes.ContactResult.HIT:
			outcome = CombatTypes.ContactResult.TRADED

		candidate.attacker.register_own_contact(outcome)

		var result: HitResult = _build_result(candidate, outcome)
		results.append(result)

		# Damage goes to the victim's component, which re-emits it for the actor
		# to apply. The resolver never touches health directly — it does not know
		# what an Actor is, and must not.
		if result.damage > 0.0:
			candidate.victim.report_damage(result)

		_raise_feedback(candidate, result, outcome)

	return results


static func _build_result(candidate: Candidate,
		outcome: CombatTypes.ContactResult) -> HitResult:
	var result := HitResult.new()
	result.attacker = candidate.attacker_node
	result.victim = candidate.hurtbox.actor
	result.attack_id = candidate.attack.id
	result.hit_group = candidate.hitbox.hit_group
	result.result = outcome
	result.position = candidate.position
	result.direction = candidate.direction
	result.frame = CombatClock.frame
	result.combo_length = candidate.attacker.combo_length
	result.combo_scaling = _combo_scaling(candidate.attacker.combo_length)
	result.victim_airborne = not candidate.victim.grounded
	result.was_trade = outcome == CombatTypes.ContactResult.TRADED

	var reaction: HitReaction = candidate.hitbox.override_reaction
	if reaction == null:
		reaction = candidate.attack.on_hit

	match outcome:
		CombatTypes.ContactResult.HIT, CombatTypes.ContactResult.TRADED, \
		CombatTypes.ContactResult.ARMORED:
			result.damage = candidate.attack.damage \
				* candidate.hitbox.damage_scale \
				* candidate.hurtbox.damage_multiplier \
				* result.combo_scaling
			result.stagger_damage = candidate.attack.stagger_damage \
				* candidate.hitbox.stagger_scale
			result.reaction = reaction
		CombatTypes.ContactResult.GUARDED:
			result.damage = candidate.attack.chip_damage
			result.stagger_damage = candidate.attack.stagger_damage * 0.25
		_:
			result.damage = 0.0

	return result


## Damage scaling by combo length.
##
## Combos must be rewarding without being the only thing that matters: a long
## combo should out-damage a short one, but not proportionally, or the game
## becomes "land one hit, win". Scaling also makes the FIRST hit of a combo the
## most valuable, which keeps neutral play meaningful — the part of a fighting
## game where the real decisions happen.
static func _combo_scaling(combo_length: int) -> float:
	if combo_length <= 1:
		return 1.0
	# Asymptotic floor at 0.3 rather than a linear ramp to zero, so a long combo
	# never becomes literally pointless.
	return maxf(0.3, 1.0 - float(combo_length - 1) * 0.07)


static func _raise_feedback(candidate: Candidate, result: HitResult,
		outcome: CombatTypes.ContactResult) -> void:
	var attacker_node: Node = candidate.attacker_node
	var victim_node: Node = candidate.hurtbox.actor

	match outcome:
		CombatTypes.ContactResult.HIT, CombatTypes.ContactResult.TRADED, \
		CombatTypes.ContactResult.ARMORED:
			GameEvents.hit_landed.emit(attacker_node, victim_node, result)
		CombatTypes.ContactResult.GUARDED:
			GameEvents.hit_guarded.emit(attacker_node, victim_node, result)
		CombatTypes.ContactResult.PARRIED:
			# The defender is the subject of a parry, so the argument order is
			# defender-first — the parry is their achievement.
			GameEvents.parry_succeeded.emit(victim_node, attacker_node, result)
			# A parried attacker eats a long freeze, which IS the punish window.
			candidate.attacker.apply_hitstop(PARRY_ATTACKER_FREEZE)
		CombatTypes.ContactResult.DODGED:
			GameEvents.attack_dodged.emit(victim_node, attacker_node)
		_:
			pass


## Frames a parried attacker is frozen for. Long, because a perfect parry is the
## highest-skill defensive action in the game and its reward has to be worth the
## risk of attempting it.
const PARRY_ATTACKER_FREEZE: int = 22
