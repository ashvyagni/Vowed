extends TestCase

## Combo graph resolution.
##
## These tests exist because the combo graph is the one system whose failures are
## almost invisible in play. A broken route does not crash — it simply never
## comes out, and the player concludes the game is unresponsive. With a target of
## 100+ routes, "check it by playing" stops being a viable verification strategy
## very early.
##
## Each test states the design rule it protects, not just the behaviour.

var graph: ComboGraph
var context: ComboContext


func before_each() -> void:
	graph = ComboGraph.new()
	graph.id = &"test_graph"
	context = ComboContext.new()


# --- helpers ----------------------------------------------------------------

func _edge(from: StringName, to: StringName, action: CombatAction.Id,
		priority: int = 0) -> ComboEdge:
	var e := ComboEdge.new()
	e.from = from
	e.to = to
	e.action = action
	e.priority = priority
	graph.edges.append(e)
	graph.invalidate_index()
	return e


# --- basic resolution -------------------------------------------------------

func test_empty_graph_resolves_nothing() -> void:
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"an empty graph must not invent a route")


func test_resolves_entry_attack_from_neutral() -> void:
	_edge(&"", &"jab_1", CombatAction.Id.PUNCH)
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"jab_1")


func test_wrong_button_resolves_nothing() -> void:
	_edge(&"", &"jab_1", CombatAction.Id.PUNCH)
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"",
		"KICK must not fire a PUNCH route")


func test_resolves_a_chain() -> void:
	_edge(&"", &"jab_1", CombatAction.Id.PUNCH)
	_edge(&"jab_1", &"jab_2", CombatAction.Id.PUNCH)
	_edge(&"jab_2", &"straight", CombatAction.Id.PUNCH)

	context.current_attack = &"jab_1"
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"jab_2")
	context.current_attack = &"jab_2"
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"straight")


func test_route_is_scoped_to_its_source() -> void:
	# A route out of jab_1 must not be reachable from jab_2. Without this,
	# every string would collapse into one shared pool of follow-ups.
	_edge(&"jab_1", &"uppercut", CombatAction.Id.KICK)
	context.current_attack = &"jab_2"
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"",
		"a route must not leak to a different source attack")


# --- priority ----------------------------------------------------------------

func test_higher_priority_wins() -> void:
	_edge(&"", &"generic_punch", CombatAction.Id.PUNCH, 0)
	_edge(&"", &"special_punch", CombatAction.Id.PUNCH, 10)
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"special_punch",
		"priority must decide deterministically, not authoring order")


func test_priority_respected_regardless_of_authoring_order() -> void:
	# Same as above with the edges declared the other way round: resolution must
	# not depend on the order edges happen to appear in the resource.
	_edge(&"", &"special_punch", CombatAction.Id.PUNCH, 10)
	_edge(&"", &"generic_punch", CombatAction.Id.PUNCH, 0)
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"special_punch")


# --- directional conditions -------------------------------------------------

func test_direction_selects_between_routes_on_one_button() -> void:
	# This is how a small input language produces a large move set: one button,
	# several attacks, chosen by stick direction.
	var neutral := _edge(&"", &"jab", CombatAction.Id.PUNCH, 0)
	neutral.require_direction = CombatTypes.Direction.NEUTRAL
	var forward := _edge(&"", &"lunge_punch", CombatAction.Id.PUNCH, 5)
	forward.require_direction = CombatTypes.Direction.FORWARD

	context.direction = CombatTypes.Direction.NEUTRAL
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"jab")

	context.direction = CombatTypes.Direction.FORWARD
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"lunge_punch")


func test_neutral_requirement_excludes_directional_input() -> void:
	# NEUTRAL is not ANY: it actively requires no movement input.
	var e := _edge(&"", &"jab", CombatAction.Id.PUNCH)
	e.require_direction = CombatTypes.Direction.NEUTRAL
	context.direction = CombatTypes.Direction.BACK
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"a NEUTRAL-only route must not fire while a direction is held")


func test_toward_accepts_forward() -> void:
	# TOWARD/AWAY are target-relative and resolved upstream into FORWARD/BACK,
	# so an edge authored either way must behave the same.
	var e := _edge(&"", &"rush", CombatAction.Id.KICK)
	e.require_direction = CombatTypes.Direction.TOWARD
	context.direction = CombatTypes.Direction.FORWARD
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"rush")


# --- contact conditions -----------------------------------------------------

func test_on_hit_route_requires_a_connected_hit() -> void:
	# The core risk/reward mechanism: a connected attack is expressive, a whiff
	# stays punishable.
	var e := _edge(&"jab_1", &"rekka", CombatAction.Id.PUNCH)
	e.require_contact = CombatTypes.ContactRequirement.ON_HIT
	context.current_attack = &"jab_1"

	context.did_hit = false
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"an ON_HIT route must not be available on a whiff")

	context.did_hit = true
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"rekka")


func test_on_whiff_route_requires_no_contact() -> void:
	# Enables deliberate feint design.
	var e := _edge(&"jab_1", &"feint_recover", CombatAction.Id.DASH)
	e.require_contact = CombatTypes.ContactRequirement.ON_WHIFF
	context.current_attack = &"jab_1"

	context.did_hit = true
	assert_eq(graph.resolve(CombatAction.Id.DASH, context), &"")

	context.did_hit = false
	assert_eq(graph.resolve(CombatAction.Id.DASH, context), &"feint_recover")


func test_on_contact_accepts_hit_or_guard() -> void:
	var e := _edge(&"jab_1", &"pressure", CombatAction.Id.PUNCH)
	e.require_contact = CombatTypes.ContactRequirement.ON_CONTACT
	context.current_attack = &"jab_1"

	context.did_guard = true
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"pressure",
		"ON_CONTACT should accept a guarded hit")

	context.did_guard = false
	context.did_hit = true
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"pressure",
		"ON_CONTACT should accept a clean hit")


# --- stance and air combat --------------------------------------------------

func test_grounded_route_is_unavailable_airborne() -> void:
	var e := _edge(&"", &"sweep", CombatAction.Id.KICK)
	e.require_stance = CombatTypes.Stance.GROUNDED
	context.grounded = false
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"",
		"a ground-only attack must not come out in the air")


func test_air_route_is_unavailable_grounded() -> void:
	var e := _edge(&"", &"air_kick", CombatAction.Id.KICK)
	e.require_stance = CombatTypes.Stance.AIRBORNE
	context.grounded = true
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"")

	context.grounded = false
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"air_kick")


func test_aerial_route_can_require_an_airborne_target() -> void:
	# The structural reason air combos exist: the follow-up is legal *because*
	# the launcher put the target in the air.
	var e := _edge(&"launcher", &"air_chase", CombatAction.Id.PUNCH)
	e.require_target_state = CombatTypes.TargetState.LAUNCHED
	context.current_attack = &"launcher"

	context.target_state = CombatTypes.TargetState.GROUNDED
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"the air route must not be available against a grounded target")

	context.target_state = CombatTypes.TargetState.LAUNCHED
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"air_chase")


# --- spacing -----------------------------------------------------------------

func test_distance_gates_a_close_range_route() -> void:
	var e := _edge(&"", &"grab", CombatAction.Id.PUNCH)
	e.max_target_distance = 1.5
	context.target_state = CombatTypes.TargetState.GROUNDED

	context.target_distance = 5.0
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"a close-range route must not be available from across the arena")

	context.target_distance = 1.0
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"grab")


# --- combo length ------------------------------------------------------------

func test_min_combo_length_gates_a_late_route() -> void:
	var e := _edge(&"jab_2", &"finisher", CombatAction.Id.KICK)
	e.min_combo_length = 3
	context.current_attack = &"jab_2"

	context.combo_length = 2
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"")

	context.combo_length = 3
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"finisher")


func test_max_combo_length_closes_a_loop() -> void:
	# Prevents one repeatable sequence from being optimal forever.
	var e := _edge(&"jab_2", &"jab_1", CombatAction.Id.PUNCH)
	e.max_combo_length = 4
	context.current_attack = &"jab_2"

	context.combo_length = 4
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"jab_1",
		"the loop should still be open at the limit")

	context.combo_length = 5
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"the loop must close once past max_combo_length")


# --- Soul gating (the M3 mechanism) -----------------------------------------

func test_soul_gated_route_requires_that_soul() -> void:
	var e := _edge(&"jab_2", &"flame_hook", CombatAction.Id.PUNCH)
	e.require_soul = &"infiroar"
	context.current_attack = &"jab_2"

	context.soul_id = &"zephyrix"
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"another Soul must not grant Infiroar's route")

	context.soul_id = &"infiroar"
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"flame_hook")


func test_passive_state_unlocks_routes_rather_than_adding_damage() -> void:
	# This test encodes the project's central Soul design rule: a passive
	# changes HOW the player fights. FURY IGNITION opens branches; it does not
	# raise a number.
	_edge(&"jab_2", &"normal_follow", CombatAction.Id.PUNCH, 0)
	var ignited := _edge(&"jab_2", &"ignited_rush", CombatAction.Id.PUNCH, 10)
	ignited.require_soul = &"infiroar"
	ignited.require_passive_state = &"fury_ignited"

	context.current_attack = &"jab_2"
	context.soul_id = &"infiroar"

	context.passive_state = &""
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"normal_follow",
		"without the passive active, the base route applies")

	context.passive_state = &"fury_ignited"
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"ignited_rush",
		"with FURY IGNITION active, the SAME button takes a different route — "
			+ "this is what 'the Soul changes how you fight' means mechanically")


func test_manifestation_gated_route() -> void:
	var e := _edge(&"", &"beast_claw", CombatAction.Id.PUNCH)
	e.require_soul = &"infiroar"
	e.require_manifestation = true
	context.soul_id = &"infiroar"

	context.manifesting = false
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"")

	context.manifesting = true
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"beast_claw")


func test_resonance_cost_gates_a_route() -> void:
	var e := _edge(&"", &"soul_burst", CombatAction.Id.SOUL_TECHNIQUE)
	e.min_resonance = 25.0

	context.resonance = 10.0
	assert_eq(graph.resolve(CombatAction.Id.SOUL_TECHNIQUE, context), &"",
		"a technique must not fire without the resonance to pay for it")

	context.resonance = 30.0
	assert_eq(graph.resolve(CombatAction.Id.SOUL_TECHNIQUE, context),
		&"soul_burst")


# --- graph composition ------------------------------------------------------

func test_included_graph_contributes_routes() -> void:
	# Souls layer their move set in by inclusion, so the base graph never needs
	# to know they exist.
	_edge(&"", &"jab", CombatAction.Id.PUNCH)

	var soul_graph := ComboGraph.new()
	soul_graph.id = &"infiroar_routes"
	var soul_edge := ComboEdge.new()
	soul_edge.from = &"jab"
	soul_edge.to = &"flame_kick"
	soul_edge.action = CombatAction.Id.KICK
	soul_graph.edges.append(soul_edge)

	graph.included_graphs.append(soul_graph)
	graph.invalidate_index()

	context.current_attack = &"jab"
	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"flame_kick",
		"an included graph's routes must resolve through the parent")
	assert_eq(graph.route_count(), 2,
		"route_count must include layered graphs")


func test_available_actions_lists_only_legal_routes() -> void:
	_edge(&"jab_1", &"jab_2", CombatAction.Id.PUNCH)
	var air_only := _edge(&"jab_1", &"air_kick", CombatAction.Id.KICK)
	air_only.require_stance = CombatTypes.Stance.AIRBORNE

	context.current_attack = &"jab_1"
	context.grounded = true

	var actions: Array[CombatAction.Id] = graph.available_actions(context)
	assert_size(actions, 1, "only the grounded route should be available")
	assert_eq(actions[0], CombatAction.Id.PUNCH)


func test_index_is_rebuilt_after_invalidation() -> void:
	_edge(&"", &"jab", CombatAction.Id.PUNCH)
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"jab")

	# Souls mutate the graph at runtime; a stale index would silently hide the
	# newly added routes.
	var added := ComboEdge.new()
	added.from = &""
	added.to = &"new_kick"
	added.action = CombatAction.Id.KICK
	graph.edges.append(added)
	graph.invalidate_index()

	assert_eq(graph.resolve(CombatAction.Id.KICK, context), &"new_kick",
		"routes added after the first query must resolve")


# --- validation --------------------------------------------------------------

func test_validate_flags_a_route_to_a_missing_attack() -> void:
	_edge(&"", &"does_not_exist", CombatAction.Id.PUNCH)
	var problems: PackedStringArray = graph.validate([&"jab_1"] as Array[StringName])
	assert_not_empty(problems,
		"a route to a non-existent attack must be reported — it would "
			+ "silently never fire")
	assert_contains("\n".join(problems), "does_not_exist")


func test_validate_flags_ambiguous_equal_priority_routes() -> void:
	_edge(&"", &"punch_a", CombatAction.Id.PUNCH, 5)
	_edge(&"", &"punch_b", CombatAction.Id.PUNCH, 5)
	var problems: PackedStringArray = graph.validate()
	assert_contains("\n".join(problems), "ambiguous",
		"two equal-priority routes on one button make the move set "
			+ "unpredictable and must be reported")


func test_validate_accepts_differing_priorities() -> void:
	_edge(&"", &"punch_a", CombatAction.Id.PUNCH, 5)
	_edge(&"", &"punch_b", CombatAction.Id.PUNCH, 6)
	var problems: PackedStringArray = graph.validate()
	assert_false("\n".join(problems).contains("ambiguous"),
		"differing priorities resolve deterministically and are not ambiguous")


func test_validate_flags_a_graph_with_no_entry_point() -> void:
	_edge(&"jab_1", &"jab_2", CombatAction.Id.PUNCH)
	var problems: PackedStringArray = graph.validate()
	assert_contains("\n".join(problems), "neutral",
		"a graph no attack can be started from must be reported")


func test_validate_flags_unreachable_attacks() -> void:
	_edge(&"", &"jab_1", CombatAction.Id.PUNCH)
	# orphan_attack has an outbound route but nothing routes into it — the usual
	# signature of a renamed attack whose inbound edge was missed.
	_edge(&"orphan_attack", &"jab_1", CombatAction.Id.KICK)
	var problems: PackedStringArray = graph.validate()
	assert_contains("\n".join(problems), "orphan_attack")


func test_validate_passes_on_a_well_formed_graph() -> void:
	_edge(&"", &"jab_1", CombatAction.Id.PUNCH)
	_edge(&"jab_1", &"jab_2", CombatAction.Id.PUNCH)
	var known: Array[StringName] = [&"jab_1", &"jab_2"]
	assert_empty(graph.validate(known),
		"a correct graph must produce no findings, or the validator's output "
			+ "becomes noise that gets ignored")


func test_describe_routes_lists_the_move_set() -> void:
	_edge(&"", &"jab_1", CombatAction.Id.PUNCH)
	_edge(&"jab_1", &"jab_2", CombatAction.Id.PUNCH)
	var dump: String = graph.describe_routes()
	assert_contains(dump, "jab_1")
	assert_contains(dump, "jab_2")
	assert_contains(dump, "neutral")

# --- dash recency -----------------------------------------------------------

func test_dash_attack_requires_a_recent_dash() -> void:
	# A dash attack launches from NEUTRAL, so it cannot be gated by an
	# attack-relative frame window — that reads as frame 0 and would fire on
	# every press, making the dash attack beat the jab unconditionally.
	var e := _edge(&"", &"dash_punch", CombatAction.Id.PUNCH, 8)
	e.max_frames_since_dash = 24

	context.frames_since_dash = -1
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"with no dash at all, the dash attack must not be available")

	context.frames_since_dash = 40
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"",
		"a dash 40 frames ago is outside the 24-frame window")

	context.frames_since_dash = 10
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"dash_punch",
		"a recent dash makes the dash attack available")


func test_dash_attack_outranks_the_neutral_attack_only_after_a_dash() -> void:
	# The behaviour that was actually broken: the higher-priority dash attack
	# must not steal the press when the player has not dashed.
	_edge(&"", &"jab_1", CombatAction.Id.PUNCH, 0)
	var dash := _edge(&"", &"dash_punch", CombatAction.Id.PUNCH, 8)
	dash.max_frames_since_dash = 24

	context.frames_since_dash = -1
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"jab_1",
		"without a dash, the plain jab must still come out")

	context.frames_since_dash = 5
	assert_eq(graph.resolve(CombatAction.Id.PUNCH, context), &"dash_punch",
		"after a dash, the dash attack takes priority")


# --- validator precision ----------------------------------------------------

func test_validate_allows_a_self_loop_that_is_bounded() -> void:
	# An air-string that repeats itself is legitimate when max_combo_length
	# closes it. Warning here would be a false positive, and a validator that
	# cries wolf stops being read — which costs more than the check is worth.
	_edge(&"", &"air_punch", CombatAction.Id.PUNCH)
	var loop := _edge(&"air_punch", &"air_punch", CombatAction.Id.PUNCH)
	loop.max_combo_length = 6

	var problems: PackedStringArray = graph.validate()
	assert_false("\n".join(problems).contains("loop"),
		"a bounded self-route is valid and must not be reported")


func test_validate_flags_an_unbounded_self_loop() -> void:
	_edge(&"", &"air_punch", CombatAction.Id.PUNCH)
	_edge(&"air_punch", &"air_punch", CombatAction.Id.PUNCH)

	var problems: PackedStringArray = graph.validate()
	assert_contains("\n".join(problems), "loop never closes",
		"an unbounded self-route would repeat forever and must be reported")
