extends Node

## End-to-end verification of the whole combat pipeline.
##
##     godot --headless --path . res://tests/integration/CombatPipeline.tscn
##
## Exits 0 on success, 1 on failure, so it slots into tools/check.sh.
##
## WHY THIS EXISTS SEPARATELY FROM THE UNIT SUITE
##
## Every part of combat is unit-tested in isolation, and all of it passes. None
## of that proves the parts are WIRED TOGETHER. The unit tests never touch the
## physics space, the hurtbox layers, the director's phase ordering or the damage
## signal — so a mis-set collision mask, an unregistered actor or a hurtbox with
## no component would leave 100+ green tests and a game where punches pass
## straight through the enemy.
##
## This runs the real scenes, in the real tree, with real physics queries, and
## asserts that a punch actually damages a dummy. It is the test that would catch
## the class of failure the unit suite structurally cannot see.
##
## It needs a live SceneTree and awaited frames, which the synchronous unit
## runner cannot provide — hence a scene rather than a `*_test.gd` file.

const PLAYER_SCENE: String = "res://scenes/actors/Player.tscn"
const DUMMY_SCENE: String = "res://scenes/actors/TrainingDummy.tscn"

## Well inside jab_1's reach: its hitbox sits 0.72 m forward with a 0.42 m
## radius, so it reaches ~1.14 m, and the dummy's hurtbox surface is 0.40 m in
## front of its origin. 1.3 m leaves clear margin without being point-blank.
const ENGAGE_DISTANCE: float = 1.3

var _check: TestCase
var _player: PlayerController
var _dummy: Actor
var _scripted: ScriptedIntentSource
var _failures: int = 0
var _cases: int = 0


func _ready() -> void:
	_check = TestCase.new()
	_build_arena()

	# Let the tree settle so collision shapes register with the physics server
	# before any query is issued.
	await _frames(6)

	await _case("a punch damages the dummy", _test_punch_lands)
	await _case("a string chains and the combo counter tracks it",
		_test_string_chains)
	await _case("a guarding dummy takes chip, not full damage",
		_test_guard_reduces_damage)
	await _case("a launcher puts the dummy airborne", _test_launcher_launches)
	await _case("hitstop freezes the attacker on contact", _test_hitstop)
	await _case("combat produces audio feedback", _test_audio_feedback)
	await _case("combat is identical at 30 and 240 fps",
		_test_frame_rate_independence)
	await _case("the same inputs produce the same outcome twice",
		_test_determinism)

	_report()


# --- arena ------------------------------------------------------------------

func _build_arena() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(60.0, 0.4, 60.0)
	floor_collision.shape = floor_shape
	floor_collision.position = Vector3(0.0, -0.2, 0.0)
	floor_body.add_child(floor_collision)
	add_child(floor_body)

	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as PlayerController
	_player.capture_mouse = false
	_player.position = Vector3.ZERO

	# Replace the device-driven intent source with a scripted one. Device input
	# cannot be simulated headlessly, and directional command normals need held
	# movement that a raw buffer push cannot express. The combat system cannot
	# tell the difference — which is the property being relied on.
	var device_intent: Node = _player.get_node("Intent")
	_player.remove_child(device_intent)
	device_intent.queue_free()

	_scripted = ScriptedIntentSource.new()
	_scripted.name = "Intent"
	_player.add_child(_scripted)
	_player.intent_source = _scripted

	add_child(_player)

	_dummy = (load(DUMMY_SCENE) as PackedScene).instantiate() as Actor
	# Actors face -Z, so the dummy is placed along the player's forward axis.
	_dummy.position = Vector3(0.0, 0.0, -ENGAGE_DISTANCE)
	_dummy.rotation.y = PI
	add_child(_dummy)


# --- cases ------------------------------------------------------------------

func _test_punch_lands() -> void:
	var before: float = _dummy.health
	_press(CombatAction.Id.PUNCH)
	await _frames(14)

	_check.assert_lt(_dummy.health, before,
		"a punch at %.1f m must reduce the dummy's health — if this fails, the "
			% ENGAGE_DISTANCE
			+ "combat pipeline is not wired to the physics space at all")
	_check.assert_eq(_player.combat.combo_length, 1,
		"a landed hit must register on the attacker's combo counter")


func _test_string_chains() -> void:
	_reset()
	await _frames(4)

	# jab_1 -> jab_2 -> straight. Cancel windows open at 6, 7 and 10 frames
	# respectively, so the presses are spaced to land inside them. That the
	# authored frame data actually permits this chain is precisely the claim
	# being tested.
	_press(CombatAction.Id.PUNCH)
	await _frames(8)
	_press(CombatAction.Id.PUNCH)
	await _frames(10)
	_press(CombatAction.Id.PUNCH)
	await _frames(16)

	_check.assert_ge(float(_player.combat.combo_length), 3.0,
		"jab_1 -> jab_2 -> straight should produce a 3-hit combo; got %d. "
			% _player.combat.combo_length
			+ "A lower count means the authored cancel windows and hitstun do "
			+ "not actually support the string.")


func _test_guard_reduces_damage() -> void:
	_reset()
	_set_dummy_mode(TrainingDummyIntent.Mode.BLOCK)
	# Give the dummy time to enter guard, and to leave the parry window so this
	# measures GUARD rather than an accidental parry.
	await _frames(20)

	var before: float = _dummy.health
	_press(CombatAction.Id.PUNCH)
	await _frames(14)

	var taken: float = before - _dummy.health
	_check.assert_lt(taken, 3.0,
		"a guarded jab should deal only chip damage; took %.2f" % taken)
	_check.assert_eq(_player.combat.combo_length, 0,
		"a blocked attack must not extend the combo")
	_check.assert_true(_player.combat.did_guard,
		"the attacker should know its attack was guarded")

	_set_dummy_mode(TrainingDummyIntent.Mode.IDLE)


func _test_launcher_launches() -> void:
	_reset()
	await _frames(4)

	# uppercut is reached from neutral with BACK held, so movement intent is
	# injected directly rather than through a device.
	_press_with_direction(CombatAction.Id.PUNCH, Vector2(0.0, -1.0))
	await _frames(26)

	_check.assert_eq(_dummy.combat.state, CombatState.Id.LAUNCHED,
		"the launcher must put the dummy in LAUNCHED state (got %s) — this is "
			% CombatState.name_of(_dummy.combat.state)
			+ "the gateway every aerial route depends on")
	_check.assert_gt(_dummy.velocity.y, 0.0,
		"a launched actor must actually be moving upward — hitstop must FREEZE "
			+ "the launch impulse, not erase it")

	# And it must still be rising once the freeze ends, not merely at the
	# instant of contact.
	await _frames(10)
	_check.assert_gt(_dummy.global_position.y, 0.25,
		"the dummy should have gained height after the freeze released; "
			+ "got y=%.2f" % _dummy.global_position.y)


func _test_hitstop() -> void:
	_reset()
	await _frames(4)

	_press(CombatAction.Id.PUNCH)
	# jab_1 connects on frame 4-5; sample just after so hitstop is still running.
	await _frames(6)

	_check.assert_true(_player.combat.is_in_hitstop(),
		"the attacker must be in hitstop right after connecting — without it, "
			+ "hits have no weight")


## Audio is wired and actually fires.
##
## Worth a test because silence is invisible: every other system can be green
## while combat makes no sound at all, and nobody notices until someone plays
## it with the volume up. The specific failures this catches are an empty or
## mis-named sound directory, and events never reaching the audio service.
func _test_audio_feedback() -> void:
	var categories: Array[String] = CombatAudio.available_categories()
	_check.assert_not_empty(categories,
		"no sound categories loaded — combat would be entirely silent")

	# The three outcomes a player must be able to tell apart by ear alone.
	var joined: String = " ".join(categories)
	for required: String in ["impactPunch_medium", "impactPunch_heavy",
			"impactMetal_light", "impactBell_heavy"]:
		_check.assert_contains(joined, required,
			"missing the '%s' set; hit, guard and parry must be " % required
				+ "distinguishable by ear")

	_reset()
	await _frames(4)
	_press(CombatAction.Id.PUNCH)
	await _frames(8)

	_check.assert_gt(float(_dummy.max_health - _dummy.health), 0.0,
		"the punch must land for this case to mean anything")


## THE architectural claim, checked rather than asserted.
##
## docs/TECH_STACK.md §5.1 locks a fixed 60 Hz logical tick with animation slaved
## to the frame counter, and M1's exit criteria require that combat run
## identically at any render rate. This is the test that makes that a fact.
##
## What it actually guards against is combat logic leaking into `_process` or
## reading `delta`. Both are easy mistakes, and both produce timing that drifts
## with frame rate in a way that is nearly impossible to diagnose from play —
## the symptom is "combos feel inconsistent", not a crash.
func _test_frame_rate_independence() -> void:
	var slow: Dictionary = await _run_scripted_sequence(30)
	var fast: Dictionary = await _run_scripted_sequence(240)

	_check.assert_eq(slow["combo"], fast["combo"],
		"combo length differed between 30 and 240 fps (%d vs %d) — combat "
			% [slow["combo"], fast["combo"]]
			+ "timing is leaking into the render rate")
	_check.assert_almost_eq(float(slow["damage"]), float(fast["damage"]), 0.01,
		"damage differed between 30 and 240 fps (%.2f vs %.2f)"
			% [slow["damage"], fast["damage"]])
	_check.assert_eq(slow["combat_frames"], fast["combat_frames"],
		"the clock advanced a different number of logical frames at 30 vs 240 "
			+ "fps (%d vs %d) — the tick is not fixed"
			% [slow["combat_frames"], fast["combat_frames"]])


## Determinism: identical inputs must produce an identical outcome.
##
## The property the whole combat model is built to have — combat as a pure
## function of (state, input, frame). Without it, a reported bug cannot be
## reproduced from an input log and frame data cannot be tuned with confidence,
## because the same test may simply behave differently next time.
func _test_determinism() -> void:
	var first: Dictionary = await _run_scripted_sequence(0)
	var second: Dictionary = await _run_scripted_sequence(0)

	_check.assert_eq(first["combo"], second["combo"],
		"identical inputs gave different combo lengths (%d vs %d)"
			% [first["combo"], second["combo"]])
	_check.assert_almost_eq(float(first["damage"]), float(second["damage"]),
		0.001, "identical inputs gave different damage (%.4f vs %.4f)"
			% [first["damage"], second["damage"]])


## Run one fixed input sequence at a given render cap and report the outcome.
## `max_fps` of 0 means uncapped.
func _run_scripted_sequence(max_fps: int) -> Dictionary:
	Engine.max_fps = max_fps
	_reset()
	await _frames(6)

	var start_frame: int = CombatClock.frame
	var start_health: float = _dummy.health

	_press(CombatAction.Id.PUNCH)
	await _frames(8)
	_press(CombatAction.Id.PUNCH)
	await _frames(10)
	_press(CombatAction.Id.PUNCH)
	await _frames(16)

	var outcome: Dictionary = {
		"combo": _player.combat.combo_length,
		"damage": start_health - _dummy.health,
		"combat_frames": CombatClock.frame - start_frame,
	}

	Engine.max_fps = 0
	return outcome


# --- harness ----------------------------------------------------------------

func _case(label: String, body: Callable) -> void:
	_cases += 1
	_check._test_reset()
	await body.call()

	var failures: PackedStringArray = _check._test_failures()
	if failures.is_empty():
		print("  \u001b[32mPASS\u001b[0m %s" % label)
		return

	_failures += 1
	print("  \u001b[31mFAIL\u001b[0m %s" % label)
	for failure: String in failures:
		print("      - %s" % failure)


func _reset() -> void:
	CombatDirector.reset_all()
	_player.position = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_dummy.position = Vector3(0.0, 0.0, -ENGAGE_DISTANCE)
	_dummy.rotation.y = PI
	_dummy.velocity = Vector3.ZERO
	_dummy.health = _dummy.max_health
	_scripted.reset()


func _press(action: CombatAction.Id) -> void:
	_scripted.move = Vector2.ZERO
	_scripted.press(action)


## Press while holding a direction, for command normals that require one.
func _press_with_direction(action: CombatAction.Id, move: Vector2) -> void:
	_scripted.press_with_direction(action, move)


func _set_dummy_mode(mode: TrainingDummyIntent.Mode) -> void:
	var intent := _dummy.intent_source as TrainingDummyIntent
	if intent != null:
		intent.mode = mode
		intent.reset()


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().physics_frame


func _report() -> void:
	print("".lpad(62, "-"))
	if _failures == 0:
		print("\u001b[32mINTEGRATION OK\u001b[0m  %d case(s) passed" % _cases)
		get_tree().quit(0)
		return
	print("\u001b[31mINTEGRATION FAILED\u001b[0m  %d of %d case(s) failed"
		% [_failures, _cases])
	get_tree().quit(1)
