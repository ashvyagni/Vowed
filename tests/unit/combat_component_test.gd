extends TestCase

## Combat state machine behaviour.
##
## This is the most important test file in the project. The state machine decides
## how combat *feels*, and almost every way it can be wrong is invisible in a
## screenshot and hard to reproduce on demand:
##
##   * an attack advancing during hitstop        -> hits feel weightless
##   * a cancel legal outside its window         -> execution becomes free
##   * a hitbox connecting once per frame        -> absurd damage
##   * hitstun off by a frame                   -> combos silently stop working
##
## Every test names the design rule it protects. A test that only asserts current
## behaviour cannot tell you whether a change is a fix or a regression.

var component: CombatComponent
var library: AttackLibrary
var graph: ComboGraph
var context: ComboContext


func before_each() -> void:
	library = AttackLibrary.new()
	library.id = &"test_lib"
	graph = ComboGraph.new()
	graph.id = &"test_graph"

	component = CombatComponent.new()
	component.library = library
	component.graph = graph

	context = ComboContext.new()


func after_each() -> void:
	if component != null:
		component.free()
		component = null


# --- builders ---------------------------------------------------------------

func _reaction(hitstun: int = 14,
		kind: CombatTypes.ReactionKind = CombatTypes.ReactionKind.MEDIUM
		) -> HitReaction:
	var r := HitReaction.new()
	r.kind = kind
	r.hitstun_frames = hitstun
	if kind == CombatTypes.ReactionKind.LAUNCH:
		r.launch_velocity = Vector3(0.0, 8.0, 2.0)
	if kind == CombatTypes.ReactionKind.KNOCKDOWN:
		r.causes_knockdown = true
	return r


func _attack(id: StringName, startup: int = 5, active: int = 3,
		recovery: int = 10, hitstop: int = 0) -> AttackData:
	var a := AttackData.new()
	a.id = id
	a.animation = id
	a.startup = startup
	a.active = active
	a.recovery = recovery
	a.hitstop = hitstop
	a.guard_hitstop = hitstop
	a.on_hit = _reaction()

	var box := HitboxKeyframe.new()
	box.hit_group = 0
	box.first_frame = startup
	box.last_frame = startup + active - 1
	box.shape = SphereShape3D.new()
	a.hitboxes.append(box)

	library.attacks.append(a)
	library.invalidate_index()
	return a


func _cancel(a: AttackData, first: int, last: int,
		into: int = CombatTypes.CancelInto.ATTACK,
		requires: CombatTypes.ContactRequirement = \
			CombatTypes.ContactRequirement.ANY) -> CancelWindow:
	var w := CancelWindow.new()
	w.first_frame = first
	w.last_frame = last
	w.cancel_into = into
	w.requires = requires
	a.cancel_windows.append(w)
	return w


func _route(from: StringName, to: StringName,
		action: CombatAction.Id = CombatAction.Id.PUNCH) -> ComboEdge:
	var e := ComboEdge.new()
	e.from = from
	e.to = to
	e.action = action
	graph.edges.append(e)
	graph.invalidate_index()
	return e


## Advance `count` logical frames.
func _tick(count: int = 1) -> void:
	for _i: int in count:
		component.tick()


# --- baseline ---------------------------------------------------------------

func test_starts_neutral_and_idle() -> void:
	assert_eq(component.state, CombatState.Id.NEUTRAL)
	assert_false(component.is_attacking())
	assert_true(component.can_act())
	assert_eq(component.combo_length, 0)


func test_action_with_no_route_does_nothing() -> void:
	assert_false(component.try_action(CombatAction.Id.PUNCH, context),
		"an unrouted button must not produce an attack")
	assert_eq(component.state, CombatState.Id.NEUTRAL)


# --- attack execution -------------------------------------------------------

func test_starts_an_attack_from_neutral() -> void:
	_attack(&"jab")
	_route(&"", &"jab")

	assert_true(component.try_action(CombatAction.Id.PUNCH, context))
	assert_eq(component.state, CombatState.Id.ATTACKING)
	assert_eq(component.attack.id, &"jab")
	assert_eq(component.attack_frame, 0, "an attack begins on frame 0")


func test_attack_advances_exactly_one_frame_per_tick() -> void:
	# The whole architecture rests on this: frames, not delta.
	_attack(&"jab", 5, 3, 10)
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)

	for expected: int in range(1, 6):
		_tick()
		assert_eq(component.attack_frame, expected,
			"frame %d expected after %d tick(s)" % [expected, expected])


func test_attack_returns_to_neutral_after_its_last_frame() -> void:
	var a: AttackData = _attack(&"jab", 5, 3, 10)  # 18 frames total
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)

	_tick(a.total_frames() - 1)
	assert_eq(component.state, CombatState.Id.ATTACKING,
		"still attacking on the final frame")

	_tick()
	assert_eq(component.state, CombatState.Id.NEUTRAL,
		"neutral once total_frames have elapsed")
	assert_null(component.attack)


func test_hitboxes_are_inactive_during_startup() -> void:
	# Startup with no hitbox IS the tell the opponent reads. A hitbox live during
	# startup means the attack has no readable window.
	_attack(&"jab", 5, 3, 10)
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)

	for frame: int in range(0, 5):
		assert_empty(component.active_hitboxes(),
			"no hitbox should be live on startup frame %d" % frame)
		_tick()


func test_hitboxes_are_active_during_the_active_window() -> void:
	_attack(&"jab", 5, 3, 10)
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(5)

	for offset: int in range(0, 3):
		assert_not_empty(component.active_hitboxes(),
			"hitbox should be live on active frame %d" % (5 + offset))
		_tick()

	assert_empty(component.active_hitboxes(),
		"hitbox must switch off in recovery")


# --- hitstop ----------------------------------------------------------------

func test_hitstop_freezes_the_attack() -> void:
	# Hitstop is what gives a hit weight. If the attack keeps advancing through
	# it, the impact is never felt.
	_attack(&"jab", 5, 3, 10, 6)
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(5)

	var frame_at_contact: int = component.attack_frame
	component.register_own_contact(CombatTypes.ContactResult.HIT)
	assert_true(component.is_in_hitstop())

	_tick(6)
	assert_eq(component.attack_frame, frame_at_contact,
		"the attack must not advance during hitstop")

	_tick()
	assert_eq(component.attack_frame, frame_at_contact + 1,
		"and must resume immediately after")


func test_no_hitboxes_are_live_during_hitstop() -> void:
	# Otherwise a frozen attack would keep re-querying and connect repeatedly.
	_attack(&"jab", 5, 3, 10, 6)
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(5)
	component.register_own_contact(CombatTypes.ContactResult.HIT)

	assert_empty(component.active_hitboxes(),
		"a frozen attack must not present live hitboxes")


# --- cancels: the timing gate ----------------------------------------------

func test_cancel_is_refused_outside_the_window() -> void:
	# The constraint IS the content. If an attack could be left at any time,
	# committing to it would cost nothing.
	_attack(&"jab", 5, 3, 10)
	_attack(&"hook", 6, 3, 12)
	_cancel(library.get_attack(&"jab"), 8, 12)
	_route(&"", &"jab")
	_route(&"jab", &"hook")

	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(3)  # frame 3, before the window opens at 8

	assert_false(component.try_action(CombatAction.Id.PUNCH, context),
		"a cancel before the window must be refused")
	assert_eq(component.attack.id, &"jab")


func test_cancel_is_allowed_inside_the_window() -> void:
	_attack(&"jab", 5, 3, 10)
	_attack(&"hook", 6, 3, 12)
	_cancel(library.get_attack(&"jab"), 8, 12)
	_route(&"", &"jab")
	_route(&"jab", &"hook")

	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(9)

	assert_true(component.try_action(CombatAction.Id.PUNCH, context))
	assert_eq(component.attack.id, &"hook")
	assert_eq(component.attack_frame, 0,
		"the new attack starts from frame 0")


func test_cancel_is_refused_after_the_window_closes() -> void:
	_attack(&"jab", 5, 3, 10)
	_attack(&"hook", 6, 3, 12)
	_cancel(library.get_attack(&"jab"), 8, 10)
	_route(&"", &"jab")
	_route(&"jab", &"hook")

	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(12)
	assert_false(component.try_action(CombatAction.Id.PUNCH, context),
		"the window closed at frame 10")


func test_on_hit_cancel_requires_the_attack_to_have_connected() -> void:
	# The core risk mechanism: connected attacks are expressive, whiffs are
	# punishable.
	_attack(&"jab", 5, 3, 10)
	_attack(&"rekka", 6, 3, 12)
	_cancel(library.get_attack(&"jab"), 6, 14,
		CombatTypes.CancelInto.ATTACK, CombatTypes.ContactRequirement.ON_HIT)
	_route(&"", &"jab")
	_route(&"jab", &"rekka")

	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(7)

	assert_false(component.try_action(CombatAction.Id.PUNCH, context),
		"an ON_HIT cancel must be refused on a whiff")

	component.register_own_contact(CombatTypes.ContactResult.HIT)
	assert_true(component.try_action(CombatAction.Id.PUNCH, context),
		"and permitted once the attack has connected")


func test_edge_frame_window_overrides_the_attack_windows() -> void:
	# For just-frame links: one route out of an attack needs precision the
	# others do not.
	_attack(&"jab", 5, 3, 10)
	_attack(&"precise", 4, 2, 8)
	_cancel(library.get_attack(&"jab"), 6, 16)  # generous attack window
	_route(&"", &"jab")
	var edge: ComboEdge = _route(&"jab", &"precise")
	edge.require_frame_window = Vector2i(9, 10)  # tight edge window

	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(7)
	assert_false(component.try_action(CombatAction.Id.PUNCH, context),
		"inside the attack's window but outside the edge's — must be refused")

	_tick(2)  # frame 9
	assert_true(component.try_action(CombatAction.Id.PUNCH, context),
		"inside the edge's tighter window — permitted")


# --- combo accounting -------------------------------------------------------

func test_combo_counter_increments_on_contact() -> void:
	_attack(&"jab")
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	assert_eq(component.combo_length, 0)

	component.register_own_contact(CombatTypes.ContactResult.HIT)
	assert_eq(component.combo_length, 1)


func test_guarded_hit_does_not_extend_the_combo() -> void:
	_attack(&"jab")
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	component.register_own_contact(CombatTypes.ContactResult.GUARDED)

	assert_eq(component.combo_length, 0,
		"a blocked attack must not count as a combo hit")
	assert_true(component.did_guard)


func test_combo_drops_when_an_attack_completes_without_connecting() -> void:
	# This is what makes a dropped combo a real failure state rather than a pause.
	var a: AttackData = _attack(&"jab", 5, 3, 10)
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	component.register_own_contact(CombatTypes.ContactResult.HIT)
	assert_eq(component.combo_length, 1)

	_tick(a.total_frames())
	assert_eq(component.state, CombatState.Id.NEUTRAL)

	# A second attack that whiffs entirely.
	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(a.total_frames())
	assert_eq(component.combo_length, 0,
		"a whiffed attack must drop the combo")


func test_non_preserving_route_resets_the_combo() -> void:
	_attack(&"jab", 5, 3, 10)
	_attack(&"reset_move", 5, 3, 10)
	_cancel(library.get_attack(&"jab"), 6, 14)
	_route(&"", &"jab")
	var edge: ComboEdge = _route(&"jab", &"reset_move")
	edge.preserves_combo = false

	component.try_action(CombatAction.Id.PUNCH, context)
	component.register_own_contact(CombatTypes.ContactResult.HIT)
	_tick(7)
	component.try_action(CombatAction.Id.PUNCH, context)

	assert_eq(component.combo_length, 0,
		"a route marked preserves_combo=false must reset the counter — the "
			+ "mechanism that stops one loop being optimal forever")


# --- receiving hits ---------------------------------------------------------

func test_a_clean_hit_causes_hitstun() -> void:
	var incoming: AttackData = _attack(&"enemy_jab")
	incoming.on_hit = _reaction(20)

	var result: CombatTypes.ContactResult = component.receive_hit(
		incoming, Vector3.FORWARD)

	assert_eq(result, CombatTypes.ContactResult.HIT)
	assert_eq(component.state, CombatState.Id.HITSTUN)
	assert_false(component.can_act(), "the victim must be unable to act")


func test_hitstun_lasts_exactly_the_authored_frames() -> void:
	# Hitstun length decides which follow-ups are guaranteed. Off by one frame
	# and combos silently stop working.
	var incoming: AttackData = _attack(&"enemy_jab")
	incoming.on_hit = _reaction(20)
	component.receive_hit(incoming, Vector3.FORWARD)

	_tick(19)
	assert_eq(component.state, CombatState.Id.HITSTUN,
		"still in hitstun on frame 19 of 20")

	_tick()
	assert_eq(component.state, CombatState.Id.NEUTRAL,
		"recovered after exactly 20 frames")


func test_being_hit_interrupts_the_victims_own_attack() -> void:
	_attack(&"jab", 10, 3, 10)
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(3)

	var incoming: AttackData = _attack(&"enemy_jab")
	component.receive_hit(incoming, Vector3.FORWARD)

	assert_null(component.attack, "the interrupted attack must be cleared")
	assert_eq(component.state, CombatState.Id.HITSTUN)


func test_a_launcher_puts_the_victim_in_launched_state() -> void:
	# The structural gateway to aerial routes.
	var incoming: AttackData = _attack(&"launcher")
	incoming.on_hit = _reaction(30, CombatTypes.ReactionKind.LAUNCH)

	component.receive_hit(incoming, Vector3.FORWARD)
	assert_eq(component.state, CombatState.Id.LAUNCHED)
	assert_eq(component.as_target_state(), CombatTypes.TargetState.LAUNCHED,
		"combo edges condition on this, so state and routing must agree")


func test_knockdown_routes_through_wakeup() -> void:
	# Getting up is a real situation the opponent can pressure, not an instant
	# return to neutral.
	var incoming: AttackData = _attack(&"slam")
	incoming.on_hit = _reaction(12, CombatTypes.ReactionKind.KNOCKDOWN)

	component.receive_hit(incoming, Vector3.FORWARD)
	assert_eq(component.state, CombatState.Id.KNOCKDOWN)

	_tick(12)
	assert_eq(component.state, CombatState.Id.WAKEUP,
		"knockdown must lead to wakeup, not straight to neutral")

	_tick(CombatComponent.WAKEUP_FRAMES)
	assert_eq(component.state, CombatState.Id.NEUTRAL)


func test_wakeup_grants_invulnerability() -> void:
	# Otherwise getting up would be a guaranteed free punish.
	var incoming: AttackData = _attack(&"slam")
	incoming.on_hit = _reaction(1, CombatTypes.ReactionKind.KNOCKDOWN)
	component.receive_hit(incoming, Vector3.FORWARD)
	_tick(1)

	assert_eq(component.state, CombatState.Id.WAKEUP)
	assert_true(component.is_invulnerable(),
		"wakeup must have invulnerable frames")


# --- multi-hit protection ---------------------------------------------------

func test_the_same_hit_group_connects_only_once_per_attack() -> void:
	# A moving hitbox must connect once, not once per frame — the "my attack
	# does 900 damage" defect. Tracked on the ATTACKER, because the scope of
	# "already hit" is one attack.
	_attack(&"sweep")
	_route(&"", &"sweep", CombatAction.Id.KICK)
	component.try_action(CombatAction.Id.KICK, context)

	var victim_id: int = 4242
	assert_false(component.has_connected(victim_id, 0),
		"nothing connected yet")
	component.mark_connected(victim_id, 0)
	assert_true(component.has_connected(victim_id, 0),
		"a second contact from the same hit group must be rejected")


func test_different_hit_groups_both_connect() -> void:
	# A genuine multi-hit flurry must still land every hit.
	_attack(&"flurry")
	_route(&"", &"flurry", CombatAction.Id.KICK)
	component.try_action(CombatAction.Id.KICK, context)

	var victim_id: int = 4242
	component.mark_connected(victim_id, 0)
	assert_false(component.has_connected(victim_id, 1),
		"a distinct hit group is a distinct hit")


func test_a_new_attack_may_connect_the_same_group_again() -> void:
	# THE bug this scoping fixes. Holding the record on the victim keyed by
	# attacker meant that once jab_1 landed with hit group 0, every later attack
	# from the same attacker reusing group 0 was rejected forever — so a
	# three-hit string landed exactly one hit while the routing looked perfect.
	_attack(&"jab_1", 4, 2, 8)
	_attack(&"jab_2", 5, 2, 10)
	_cancel(library.get_attack(&"jab_1"), 6, 13)
	_route(&"", &"jab_1")
	_route(&"jab_1", &"jab_2")

	var victim_id: int = 4242
	component.try_action(CombatAction.Id.PUNCH, context)
	component.mark_connected(victim_id, 0)
	assert_true(component.has_connected(victim_id, 0))

	_tick(7)
	assert_true(component.try_action(CombatAction.Id.PUNCH, context),
		"the follow-up should be routable")
	assert_false(component.has_connected(victim_id, 0),
		"a NEW attack must be free to connect hit group 0 on the same victim, "
			+ "or no string can ever land more than one hit")


# --- defence ---------------------------------------------------------------

func test_pressing_guard_opens_the_parry_window_first() -> void:
	# Guard and parry are the same input, separated only by timing — which is
	# what makes perfect parry a skill expression rather than a resource.
	assert_true(component.try_action(CombatAction.Id.GUARD, context))
	assert_eq(component.state, CombatState.Id.PARRYING)


func test_parry_window_expires_into_guard_not_neutral() -> void:
	# A mistimed parry should cost the reward, not the defence.
	component.try_action(CombatAction.Id.GUARD, context)
	_tick(CombatComponent.PARRY_WINDOW_FRAMES + 1)

	assert_eq(component.state, CombatState.Id.GUARDING,
		"a late parry must leave the actor still blocking")


func test_a_hit_inside_the_parry_window_is_parried() -> void:
	component.try_action(CombatAction.Id.GUARD, context)
	var incoming: AttackData = _attack(&"enemy_jab")

	var result: CombatTypes.ContactResult = component.receive_hit(
		incoming, Vector3.FORWARD)
	assert_eq(result, CombatTypes.ContactResult.PARRIED)
	assert_eq(component.state, CombatState.Id.GUARDING,
		"a successful parry leaves the defender ready to punish")


func test_a_hit_after_the_parry_window_is_merely_guarded() -> void:
	component.try_action(CombatAction.Id.GUARD, context)
	_tick(CombatComponent.PARRY_WINDOW_FRAMES + 1)

	var incoming: AttackData = _attack(&"enemy_jab")
	var result: CombatTypes.ContactResult = component.receive_hit(
		incoming, Vector3.FORWARD)
	assert_eq(result, CombatTypes.ContactResult.GUARDED)


func test_an_unblockable_defeats_guard() -> void:
	component.try_action(CombatAction.Id.GUARD, context)
	_tick(CombatComponent.PARRY_WINDOW_FRAMES + 1)

	var incoming: AttackData = _attack(&"grab")
	incoming.height = CombatTypes.Height.UNBLOCKABLE

	var result: CombatTypes.ContactResult = component.receive_hit(
		incoming, Vector3.FORWARD)
	assert_eq(result, CombatTypes.ContactResult.HIT,
		"an unblockable must go through guard — it is what stops turtling")


func test_an_unblockable_cannot_be_parried_either() -> void:
	component.try_action(CombatAction.Id.GUARD, context)
	var incoming: AttackData = _attack(&"grab")
	incoming.height = CombatTypes.Height.UNBLOCKABLE

	assert_eq(component.receive_hit(incoming, Vector3.FORWARD),
		CombatTypes.ContactResult.HIT,
		"parrying an unblockable must not work")


func test_cannot_attack_while_helpless() -> void:
	_attack(&"jab")
	_route(&"", &"jab")
	var incoming: AttackData = _attack(&"enemy_jab")
	incoming.on_hit = _reaction(30)
	component.receive_hit(incoming, Vector3.FORWARD)

	assert_false(component.try_action(CombatAction.Id.PUNCH, context),
		"an actor in hitstun must not be able to act")


# --- dodge ------------------------------------------------------------------

func test_dodge_has_invulnerable_frames_but_is_not_blanket_immune() -> void:
	# A dodge that is invulnerable for its whole duration is a panic button, not
	# a timing skill.
	assert_true(component.try_action(CombatAction.Id.DASH, context))
	assert_eq(component.state, CombatState.Id.DODGING)

	assert_false(component.is_invulnerable(),
		"frame 0 must be vulnerable, or dodge answers everything reactionlessly")

	_tick(CombatComponent.DODGE_INVULN.x)
	assert_true(component.is_invulnerable(), "invulnerable once the window opens")

	_tick(CombatComponent.DODGE_INVULN.y)
	assert_false(component.is_invulnerable(),
		"vulnerable again in the dodge's recovery")


func test_dodge_returns_to_neutral() -> void:
	component.try_action(CombatAction.Id.DASH, context)
	_tick(CombatComponent.DODGE_FRAMES)
	assert_eq(component.state, CombatState.Id.NEUTRAL)


func test_an_invulnerable_actor_dodges_the_hit() -> void:
	component.try_action(CombatAction.Id.DASH, context)
	_tick(CombatComponent.DODGE_INVULN.x)

	var incoming: AttackData = _attack(&"enemy_jab")
	assert_eq(component.receive_hit(incoming, Vector3.FORWARD),
		CombatTypes.ContactResult.DODGED)
	assert_eq(component.state, CombatState.Id.DODGING,
		"a dodged hit must not interrupt the dodge")


# --- armour -----------------------------------------------------------------

func test_armour_absorbs_the_reaction_but_not_the_damage() -> void:
	# Armour is what lets a heavy attack be *committed* rather than merely slow.
	_attack(&"heavy", 14, 4, 20)
	library.get_attack(&"heavy").interrupt_armor = 1
	_route(&"", &"heavy")
	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(3)

	var incoming: AttackData = _attack(&"enemy_jab")
	var result: CombatTypes.ContactResult = component.receive_hit(
		incoming, Vector3.FORWARD)

	assert_eq(result, CombatTypes.ContactResult.ARMORED)
	assert_eq(component.state, CombatState.Id.ATTACKING,
		"armour must keep the attack going")
	assert_not_null(component.attack)


func test_armour_is_consumed_and_the_next_hit_lands() -> void:
	_attack(&"heavy", 14, 4, 20)
	library.get_attack(&"heavy").interrupt_armor = 1
	_route(&"", &"heavy")
	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(3)

	var incoming: AttackData = _attack(&"enemy_jab")
	component.receive_hit(incoming, Vector3.FORWARD)
	var second: CombatTypes.ContactResult = component.receive_hit(
		incoming, Vector3.FORWARD)

	assert_eq(second, CombatTypes.ContactResult.HIT,
		"one armour point must absorb exactly one hit")
	assert_eq(component.state, CombatState.Id.HITSTUN)


# --- stance and resources ---------------------------------------------------

func test_an_air_only_attack_is_refused_on_the_ground() -> void:
	var a: AttackData = _attack(&"air_kick")
	a.stance = CombatTypes.Stance.AIRBORNE
	_route(&"", &"air_kick", CombatAction.Id.KICK)

	component.grounded = true
	assert_false(component.try_action(CombatAction.Id.KICK, context),
		"an air attack must not come out standing")

	component.grounded = false
	assert_true(component.try_action(CombatAction.Id.KICK, context))


func test_resonance_cost_is_enforced() -> void:
	var a: AttackData = _attack(&"soul_strike")
	a.category = CombatTypes.Category.SOUL
	a.resonance_cost = 20.0
	_route(&"", &"soul_strike", CombatAction.Id.SOUL_TECHNIQUE)

	context.resonance = 5.0
	assert_false(component.try_action(CombatAction.Id.SOUL_TECHNIQUE, context),
		"a technique must not fire without the resonance to pay for it")

	context.resonance = 25.0
	assert_true(component.try_action(CombatAction.Id.SOUL_TECHNIQUE, context))


func test_manifestation_requirement_is_enforced() -> void:
	var a: AttackData = _attack(&"beast_claw")
	a.requires_manifestation = true
	_route(&"", &"beast_claw", CombatAction.Id.PUNCH)

	context.manifesting = false
	assert_false(component.try_action(CombatAction.Id.PUNCH, context))

	context.manifesting = true
	assert_true(component.try_action(CombatAction.Id.PUNCH, context))


# --- air attack landing -----------------------------------------------------

func test_an_air_attack_is_cut_short_by_landing() -> void:
	# So aerial routes end on contact with the ground instead of playing out
	# awkwardly through the landing.
	var a: AttackData = _attack(&"air_kick", 4, 3, 30)
	a.stance = CombatTypes.Stance.AIRBORNE
	a.cancelled_by_landing = true
	_route(&"", &"air_kick", CombatAction.Id.KICK)

	component.grounded = false
	component.try_action(CombatAction.Id.KICK, context)
	_tick(5)
	assert_eq(component.state, CombatState.Id.ATTACKING)

	component.grounded = true
	_tick()
	assert_eq(component.state, CombatState.Id.NEUTRAL,
		"landing must end the air attack")


# --- context and reset ------------------------------------------------------

func test_fill_context_reports_the_components_own_state() -> void:
	# Routing depends on this being exact.
	_attack(&"jab", 5, 3, 10)
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	_tick(4)
	component.register_own_contact(CombatTypes.ContactResult.HIT)

	var fresh := ComboContext.new()
	component.fill_context(fresh)

	assert_eq(fresh.current_attack, &"jab")
	assert_eq(fresh.attack_frame, 4)
	assert_true(fresh.did_hit)
	assert_eq(fresh.combo_length, 1)


func test_reset_returns_the_component_to_a_clean_state() -> void:
	# The Combat Lab's instant reset depends on this; a leaky reset would make
	# frame-data iteration untrustworthy.
	_attack(&"jab")
	_route(&"", &"jab")
	component.try_action(CombatAction.Id.PUNCH, context)
	component.register_own_contact(CombatTypes.ContactResult.HIT)
	_tick(3)

	component.reset()

	assert_eq(component.state, CombatState.Id.NEUTRAL)
	assert_null(component.attack)
	assert_eq(component.attack_frame, 0)
	assert_eq(component.combo_length, 0)
	assert_eq(component.hitstop_remaining, 0)
	assert_false(component.did_hit)


func test_a_dead_actor_cannot_act_or_be_hit() -> void:
	component.kill()
	assert_eq(component.state, CombatState.Id.DEAD)
	assert_false(component.try_action(CombatAction.Id.PUNCH, context))

	var incoming: AttackData = _attack(&"enemy_jab")
	assert_eq(component.receive_hit(incoming, Vector3.FORWARD),
		CombatTypes.ContactResult.MISS)
