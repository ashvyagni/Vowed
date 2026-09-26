extends TestCase

## Input buffer behaviour.
##
## These tests encode the *feel contract* of the controls, which is why they are
## written before any actor exists. Each one corresponds to a way combat can feel
## broken:
##
##   * a correct press being discarded  -> "the game ate my input"
##   * a press firing much too late     -> "my character keeps doing things I
##                                         asked for ages ago"
##   * mashing queueing several actions -> "I lose control when I panic"
##
## All three are input-buffer bugs, not combat bugs, and all three are cheap to
## catch here and expensive to diagnose in play.

var buffer: InputBuffer


func before_each() -> void:
	buffer = InputBuffer.new()


func test_starts_empty() -> void:
	for id: CombatAction.Id in CombatAction.all():
		assert_false(buffer.peek(id, 0),
			"%s should not be buffered on a fresh buffer"
				% CombatAction.display_name(id))


func test_press_is_available_on_the_same_frame() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	assert_true(buffer.peek(CombatAction.Id.PUNCH, 100),
		"a press must be usable on the frame it was made")


func test_press_survives_until_the_window_expires() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	# The whole point of buffering: a press made slightly early must still be
	# there when the action becomes legal.
	for age: int in range(0, InputBuffer.NATURAL_WINDOW + 1):
		assert_true(buffer.peek(CombatAction.Id.PUNCH, 100 + age),
			"press should still be live at age %d (window is %d)"
				% [age, InputBuffer.NATURAL_WINDOW])


func test_press_expires_after_the_window() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	var past: int = 100 + InputBuffer.NATURAL_WINDOW + 1
	assert_false(buffer.peek(CombatAction.Id.PUNCH, past),
		"a press %d frames old must expire — firing later than that feels "
			% (InputBuffer.NATURAL_WINDOW + 1)
			+ "like the character acting on its own")


func test_consume_takes_the_press_exactly_once() -> void:
	buffer.push(CombatAction.Id.KICK, 50)
	assert_true(buffer.consume(CombatAction.Id.KICK, 52),
		"first consume should succeed")
	assert_false(buffer.consume(CombatAction.Id.KICK, 52),
		"a consumed press must not be reusable, or one press would produce "
			+ "two attacks")


func test_consume_does_not_take_other_actions() -> void:
	buffer.push(CombatAction.Id.PUNCH, 10)
	assert_false(buffer.consume(CombatAction.Id.KICK, 11),
		"consuming KICK must not take a buffered PUNCH")
	assert_true(buffer.peek(CombatAction.Id.PUNCH, 11),
		"PUNCH should still be buffered")


func test_peek_does_not_consume() -> void:
	buffer.push(CombatAction.Id.PUNCH, 10)
	assert_true(buffer.peek(CombatAction.Id.PUNCH, 11))
	assert_true(buffer.peek(CombatAction.Id.PUNCH, 11),
		"peek must be side-effect free — the debug overlay uses it and must "
			+ "not alter what it displays")
	assert_true(buffer.consume(CombatAction.Id.PUNCH, 11),
		"the press should still be consumable after peeking")


func test_mashing_one_action_yields_one_consume() -> void:
	# A panicking player mashes punch. They want one attack, not four queued.
	buffer.push(CombatAction.Id.PUNCH, 100)
	buffer.push(CombatAction.Id.PUNCH, 101)
	buffer.push(CombatAction.Id.PUNCH, 102)
	buffer.push(CombatAction.Id.PUNCH, 103)

	assert_true(buffer.consume(CombatAction.Id.PUNCH, 103),
		"the mash should produce an attack")
	assert_false(buffer.consume(CombatAction.Id.PUNCH, 103),
		"a single consume must clear ALL presses in the window, otherwise "
			+ "mashing queues attacks the player has lost control of")


func test_precise_window_is_tighter_than_natural() -> void:
	# Advanced cancels are where precision IS the skill; leniency there would
	# erase the thing being tested.
	assert_lt(InputBuffer.PRECISE_WINDOW, InputBuffer.NATURAL_WINDOW,
		"the precision window must be tighter than the natural one")

	buffer.push(CombatAction.Id.PUNCH, 100)
	var beyond_precise: int = 100 + InputBuffer.PRECISE_WINDOW + 1
	assert_false(
		buffer.peek(CombatAction.Id.PUNCH, beyond_precise,
			InputBuffer.PRECISE_WINDOW),
		"press should be outside the precision window at age %d"
			% (InputBuffer.PRECISE_WINDOW + 1))
	assert_true(
		buffer.peek(CombatAction.Id.PUNCH, beyond_precise,
			InputBuffer.NATURAL_WINDOW),
		"the same press should still be inside the natural window — the two "
			+ "windows must be independently applicable to the same press")


func test_consume_any_prefers_the_most_recent_press() -> void:
	# The player pressed punch, then changed their mind and pressed kick. The
	# later press is the real intent; the buffer must not impose its own
	# priority order on that choice.
	buffer.push(CombatAction.Id.PUNCH, 100)
	buffer.push(CombatAction.Id.KICK, 102)

	var chosen: int = buffer.consume_any(
		[CombatAction.Id.PUNCH, CombatAction.Id.KICK], 103)
	assert_eq(chosen, int(CombatAction.Id.KICK),
		"consume_any must return the most recent press, not the first listed")


func test_consume_any_returns_negative_when_nothing_matches() -> void:
	buffer.push(CombatAction.Id.JUMP, 100)
	var chosen: int = buffer.consume_any(
		[CombatAction.Id.PUNCH, CombatAction.Id.KICK], 101)
	assert_eq(chosen, -1, "no attack press buffered, so nothing to consume")


func test_consume_any_leaves_unrelated_presses_alone() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	buffer.push(CombatAction.Id.JUMP, 100)
	buffer.consume_any([CombatAction.Id.PUNCH], 101)
	assert_true(buffer.peek(CombatAction.Id.JUMP, 101),
		"a buffered JUMP must survive an attack consume")


func test_clear_discards_everything() -> void:
	buffer.push(CombatAction.Id.PUNCH, 10)
	buffer.push(CombatAction.Id.KICK, 10)
	buffer.clear()
	assert_false(buffer.peek(CombatAction.Id.PUNCH, 11))
	assert_false(buffer.peek(CombatAction.Id.KICK, 11))


func test_age_of_reports_frames_since_press() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	assert_eq(buffer.age_of(CombatAction.Id.PUNCH, 104), 4,
		"age drives buffer-window tuning, so it must be exact")
	assert_eq(buffer.age_of(CombatAction.Id.KICK, 104), -1,
		"an unpressed action has no age")


func test_age_of_reports_the_newest_press() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	buffer.push(CombatAction.Id.PUNCH, 105)
	assert_eq(buffer.age_of(CombatAction.Id.PUNCH, 107), 2,
		"age should measure from the most recent press")


func test_future_stamped_press_is_ignored() -> void:
	# Input is captured between physics ticks, so a press can be stamped with a
	# frame the clock has not reached. It must not be consumable early —
	# otherwise an input could resolve before the frame it belongs to.
	buffer.push(CombatAction.Id.PUNCH, 200)
	assert_false(buffer.peek(CombatAction.Id.PUNCH, 199),
		"a press stamped in the future must not be visible yet")
	assert_true(buffer.peek(CombatAction.Id.PUNCH, 200),
		"it becomes visible on its own frame")


func test_overflow_drops_oldest_not_newest() -> void:
	# Overflow must never cost the player their most recent input.
	for i: int in InputBuffer.CAPACITY + 8:
		buffer.push(CombatAction.Id.PUNCH, 1000 + i)

	var now: int = 1000 + InputBuffer.CAPACITY + 7
	assert_true(buffer.peek(CombatAction.Id.PUNCH, now),
		"the newest press must survive overflow")


func test_flush_consumes_without_erasing_history() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	buffer.flush()
	assert_false(buffer.consume(CombatAction.Id.PUNCH, 101),
		"flush must make pending input unusable")
	assert_not_empty(buffer.snapshot(101),
		"flush must keep the press visible to the debug overlay, so that "
			+ "'why did nothing happen?' is answerable")


func test_snapshot_is_ordered_newest_first() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	buffer.push(CombatAction.Id.KICK, 102)
	buffer.push(CombatAction.Id.JUMP, 101)

	var snap: Array[Dictionary] = buffer.snapshot(103)
	assert_size(snap, 3)
	assert_eq(int(snap[0]["frame"]), 102, "newest press should be first")
	assert_eq(int(snap[1]["frame"]), 101)
	assert_eq(int(snap[2]["frame"]), 100)


func test_snapshot_excludes_stale_entries() -> void:
	buffer.push(CombatAction.Id.PUNCH, 100)
	assert_empty(buffer.snapshot(100 + 61, 60),
		"entries older than max_age should not be reported")
