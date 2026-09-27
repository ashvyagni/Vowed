class_name DebugOverlay
extends CanvasLayer

## On-screen combat and performance diagnostics.
##
## Built during M1, NOT deferred. Combat cannot be tuned without it: without a
## live frame-data readout, tuning startup and recovery values is guesswork, and
## "why didn't that combo?" is unanswerable. Treating this as a luxury is how
## projects end up tuning combat by feel and shipping combat that feels
## arbitrary.
##
## Controls (see tools/generate_input_map.gd):
##   F1  toggle overlay        F4  pause / resume
##   F2  toggle hitbox shapes  F5  slow motion
##   F3  step one frame        F6  reset the arena
##
## Reads state and never mutates gameplay — except through `CombatClock`'s own
## time controls and `CombatDirector.reset_all()`, which exist for exactly this.

## Actor whose combat state is inspected. Set by the scene, or the first
## registered actor is used.
@export var subject: Actor

## Draws the hitbox and hurtbox volumes. Found in the tree when not set.
##
## The overlay MUST drive this, because hitboxes have no node in the scene tree —
## they are authored shapes queried during the combat tick — so there is nothing
## for Godot's own collision debug to draw. An earlier version toggled
## `CollisionShape3D.visible` instead, which does nothing at runtime: F2 reported
## "hitbox shapes ON" and showed nothing at all.
@export var hitbox_visualizer: HitboxVisualizer

## Performance budgets from docs/TECH_STACK.md §4. Exceeding one is highlighted,
## because a budget nobody is shown is a budget nobody keeps.
const BUDGET_FRAME_MS: float = 16.6
const BUDGET_DRAW_CALLS: int = 2000
const BUDGET_PROCESS_MB: float = 3500.0

## Physics-step budget. The whole combat pipeline runs inside the physics tick,
## so this is the number that actually moves when combat or AI regresses — and
## unlike frame time it is never inflated by waiting for the display.
const BUDGET_PHYSICS_MS: float = 6.0

const PANEL_WIDTH: int = 470

var _visible_panels: bool = true
var _show_shapes: bool = false

var _combat_label: RichTextLabel
var _input_label: RichTextLabel
var _perf_label: RichTextLabel
var _log_label: RichTextLabel

## Recent combat events, newest first. A rolling log is how a hit that happened
## half a second ago stays readable — the screen alone cannot hold it.
var _log: Array[String] = []
const LOG_LINES: int = 9


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_combat_label = _make_panel(Vector2(12, 12), PANEL_WIDTH, 250)
	_input_label = _make_panel(Vector2(12, 274), PANEL_WIDTH, 150)
	_log_label = _make_panel(Vector2(12, 436), PANEL_WIDTH, 190)
	_perf_label = _make_panel(Vector2(12, 638), PANEL_WIDTH, 110)

	GameEvents.hit_landed.connect(_on_hit_landed)
	GameEvents.hit_guarded.connect(_on_hit_guarded)
	GameEvents.parry_succeeded.connect(_on_parry)
	GameEvents.attack_dodged.connect(_on_dodged)
	GameEvents.combo_ended.connect(_on_combo_ended)
	GameEvents.actor_staggered.connect(_on_staggered)
	GameEvents.assertion_failed.connect(_on_assertion)


func _make_panel(position: Vector2, width: int, height: int) -> RichTextLabel:
	var panel := PanelContainer.new()
	panel.position = position
	panel.custom_minimum_size = Vector2(width, height)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.82)
	style.border_color = Color(0.22, 0.26, 0.32, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.fit_content = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 12)
	label.add_theme_font_size_override("bold_font_size", 12)
	label.add_theme_font_size_override("mono_font_size", 12)

	panel.add_child(label)
	add_child(panel)
	return label


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return

	if event.is_action_pressed(&"debug_toggle_overlay"):
		_visible_panels = not _visible_panels
		for child: Node in get_children():
			(child as CanvasItem).visible = _visible_panels
	elif event.is_action_pressed(&"debug_toggle_hitboxes"):
		_toggle_shapes()
	elif event.is_action_pressed(&"debug_frame_step"):
		CombatClock.request_step()
	elif event.is_action_pressed(&"debug_toggle_pause"):
		CombatClock.toggle_pause()
		_push_log("[b]clock %s[/b]"
			% ("PAUSED" if CombatClock.paused else "running"))
	elif event.is_action_pressed(&"debug_slowmo"):
		CombatClock.toggle_slow_motion()
		_push_log("[b]slow motion %s[/b]"
			% ("ON" if CombatClock.slow_motion else "off"))
	elif event.is_action_pressed(&"debug_reset_lab"):
		CombatDirector.reset_all()
		HitEffects.clear_all()
		_log.clear()
		_push_log("[b]arena reset[/b]")


func _toggle_shapes() -> void:
	if hitbox_visualizer == null:
		hitbox_visualizer = _find_visualizer(get_tree().root)
	if hitbox_visualizer == null:
		# Say so rather than silently reporting success. A debug tool that lies
		# about its own state is worse than one that is missing.
		_push_log("[color=#ff4444]no HitboxVisualizer in the scene — "
			+ "nothing to show[/color]")
		return

	hitbox_visualizer.toggle()
	_show_shapes = hitbox_visualizer.is_enabled()
	_push_log("[b]hitbox shapes %s[/b]" % ("ON" if _show_shapes else "off"))


func _find_visualizer(node: Node) -> HitboxVisualizer:
	if node is HitboxVisualizer:
		return node as HitboxVisualizer
	for child: Node in node.get_children():
		var found: HitboxVisualizer = _find_visualizer(child)
		if found != null:
			return found
	return null


func _process(_delta: float) -> void:
	if not _visible_panels:
		return
	if subject == null:
		subject = _find_subject()

	_draw_combat()
	_draw_input()
	_draw_log()
	_draw_perf()


func _find_subject() -> Actor:
	for actor: Actor in CombatDirector.actors():
		if actor != null and actor.intent_source is PlayerIntentSource:
			return actor
	var all: Array[Actor] = CombatDirector.actors()
	return all[0] if not all.is_empty() else null


# --- combat panel -----------------------------------------------------------

func _draw_combat() -> void:
	var lines: PackedStringArray = []

	var time_state: String = "running"
	if CombatClock.paused:
		time_state = "[color=#ffcc44]PAUSED[/color]"
	elif CombatClock.slow_motion:
		time_state = "[color=#66ccff]SLOW[/color]"

	lines.append("[b]COMBAT[/b]   frame [b]%d[/b]   %s" % [
		CombatClock.frame, time_state])

	if subject == null or subject.combat == null:
		lines.append("[color=#888888]no actor registered[/color]")
		_combat_label.text = "\n".join(lines)
		return

	var combat: CombatComponent = subject.combat
	lines.append("")
	lines.append("%s   hp [b]%.0f[/b]/%.0f   poise %.0f/%.0f   %s" % [
		subject.display_name if subject.display_name != "" else subject.name,
		subject.health, subject.max_health,
		subject.poise, subject.max_poise,
		"ground" if combat.grounded else "[color=#88ccff]AIR[/color]",
	])
	lines.append("state  [b]%s[/b]  (%d frame%s)" % [
		CombatState.name_of(combat.state), combat.state_frame,
		"" if combat.state_frame == 1 else "s",
	])

	if combat.attack != null:
		lines.append("")
		lines.append(_frame_data_bar(combat))
		lines.append("attack [b]%s[/b]   %s" % [
			str(combat.attack.id), combat.attack.frame_data_summary()])
		lines.append("frame  %d / %d        %s" % [
			combat.attack_frame, combat.attack.total_frames() - 1,
			_phase_label(combat),
		])
		var contact: PackedStringArray = []
		if combat.did_hit:
			contact.append("[color=#66ff88]HIT[/color]")
		if combat.did_guard:
			contact.append("[color=#ffcc44]GUARDED[/color]")
		if combat.armor_remaining > 0:
			contact.append("armour %d" % combat.armor_remaining)
		if combat.is_invulnerable():
			contact.append("[color=#88ccff]INVULN[/color]")
		if not contact.is_empty():
			lines.append("       " + "  ".join(contact))
		lines.append("cancels %s" % _cancel_summary(combat))
	else:
		lines.append("")
		lines.append("[color=#888888]no attack[/color]")

	if combat.hitstop_remaining > 0:
		lines.append("[color=#ff8866][b]HITSTOP %d[/b][/color]"
			% combat.hitstop_remaining)
	if combat.combo_length > 0:
		lines.append("combo [b]%d[/b] hit%s   scaling x%.2f" % [
			combat.combo_length, "" if combat.combo_length == 1 else "s",
			maxf(0.3, 1.0 - float(combat.combo_length - 1) * 0.07),
		])

	lines.append("")
	lines.append("routes now: %s" % _available_routes(combat))

	_combat_label.text = "\n".join(lines)


## Visual frame-data timeline: the attack's phases as a bar with a playhead.
## Reading a bar is far faster than reading three numbers, which matters when the
## value being judged is whether a window feels right.
func _frame_data_bar(combat: CombatComponent) -> String:
	var attack: AttackData = combat.attack
	var total: int = attack.total_frames()
	var bar: String = ""
	for frame: int in total:
		var glyph: String = "-"
		var colour: String = "#556070"
		if frame < attack.startup:
			glyph = "."
			colour = "#8899aa"
		elif attack.is_active_window(frame):
			glyph = "#"
			colour = "#ff5544"
		else:
			glyph = "="
			colour = "#667788"

		if attack.find_cancel(CombatTypes.CancelInto.ATTACK, frame,
				combat.did_hit, combat.did_guard) != null:
			colour = "#66ff88"
			if glyph == "=":
				glyph = "+"

		if frame == combat.attack_frame:
			bar += "[bgcolor=#ffffff][color=#000000]|[/color][/bgcolor]"
		else:
			bar += "[color=%s]%s[/color]" % [colour, glyph]
	return "[code]%s[/code]  [color=#8899aa].[/color]startup [color=#ff5544]#[/color]active [color=#66ff88]+[/color]cancel" % bar


func _phase_label(combat: CombatComponent) -> String:
	var attack: AttackData = combat.attack
	if combat.attack_frame < attack.startup:
		return "[color=#8899aa]STARTUP[/color] (%d left)" \
			% (attack.startup - combat.attack_frame)
	if attack.is_active_window(combat.attack_frame):
		return "[color=#ff5544][b]ACTIVE[/b][/color]"
	return "[color=#ffaa66]RECOVERY[/color] (%d left)" \
		% attack.frames_remaining(combat.attack_frame)


func _cancel_summary(combat: CombatComponent) -> String:
	var attack: AttackData = combat.attack
	var open: PackedStringArray = []
	var checks: Dictionary = {
		"atk": CombatTypes.CancelInto.ATTACK,
		"dash": CombatTypes.CancelInto.DASH,
		"jump": CombatTypes.CancelInto.JUMP,
		"guard": CombatTypes.CancelInto.GUARD,
		"soul": CombatTypes.CancelInto.SOUL_TECHNIQUE,
	}
	for label: String in checks:
		if attack.find_cancel(checks[label], combat.attack_frame,
				combat.did_hit, combat.did_guard) != null:
			open.append("[color=#66ff88]%s[/color]" % label)
	if open.is_empty():
		return "[color=#886666]none — committed[/color]"
	return " ".join(open)


func _available_routes(combat: CombatComponent) -> String:
	if combat.graph == null:
		return "[color=#888888]no graph[/color]"
	var context := ComboContext.new()
	combat.fill_context(context)
	if subject != null and subject.target != null \
			and subject.target.combat != null:
		context.target_state = subject.target.combat.as_target_state()
		context.target_distance = subject.global_position.distance_to(
			subject.target.global_position)
	var actions: Array[CombatAction.Id] = combat.graph.available_actions(context)
	if actions.is_empty():
		return "[color=#886666]none[/color]"
	var names: PackedStringArray = []
	for action: CombatAction.Id in actions:
		names.append(CombatAction.display_name(action))
	return "[color=#66ff88]%s[/color]" % ", ".join(names)


# --- input panel ------------------------------------------------------------

func _draw_input() -> void:
	var lines: PackedStringArray = []
	lines.append("[b]INPUT[/b]   buffer %d frames natural / %d precise" % [
		InputBuffer.NATURAL_WINDOW, InputBuffer.PRECISE_WINDOW])

	if subject == null or subject.intent_source == null:
		lines.append("[color=#888888]no intent source[/color]")
		_input_label.text = "\n".join(lines)
		return

	var source: IntentSource = subject.intent_source
	var intent: ActorIntent = source.poll(CombatClock.frame)
	lines.append("")
	lines.append("move (%.2f, %.2f)   dir %s" % [
		intent.move.x, intent.move.y,
		CombatTypes.direction_name(CombatTypes.resolve_direction(intent.move)),
	])

	var held: PackedStringArray = []
	for id: CombatAction.Id in CombatAction.all():
		if intent.is_held(id):
			held.append(CombatAction.display_name(id))
	lines.append("held  %s" % ("[color=#ffcc44]%s[/color]" % ", ".join(held) \
		if not held.is_empty() else "[color=#666666]-[/color]"))

	lines.append("")
	# Showing consumed vs unconsumed presses side by side is how the buffer
	# windows get tuned on evidence rather than by feel.
	var snapshot: Array[Dictionary] = source.buffer.snapshot(
		CombatClock.frame, 30)
	if snapshot.is_empty():
		lines.append("[color=#666666]no recent presses[/color]")
	else:
		var shown: int = 0
		for entry: Dictionary in snapshot:
			if shown >= 5:
				break
			var action: CombatAction.Id = int(entry["action"]) as CombatAction.Id
			var age: int = int(entry["age"])
			var used: bool = bool(entry["consumed"])
			lines.append("  %-16s %2df ago   %s" % [
				CombatAction.display_name(action), age,
				"[color=#66ff88]used[/color]" if used \
					else "[color=#ffcc44]PENDING[/color]",
			])
			shown += 1

	_input_label.text = "\n".join(lines)


# --- event log --------------------------------------------------------------

func _draw_log() -> void:
	var lines: PackedStringArray = ["[b]EVENTS[/b]"]
	if _log.is_empty():
		lines.append("[color=#666666]nothing yet[/color]")
	else:
		lines.append_array(_log)
	_log_label.text = "\n".join(lines)


func _push_log(line: String) -> void:
	_log.insert(0, "[color=#667788]f%d[/color] %s" % [CombatClock.frame, line])
	while _log.size() > LOG_LINES:
		_log.remove_at(_log.size() - 1)


func _on_hit_landed(_attacker: Node, victim: Node, hit: HitResult) -> void:
	_push_log("[color=#66ff88]HIT[/color] %s -> %s  %.1f dmg  x%.2f  combo %d" % [
		str(hit.attack_id), victim.name if victim != null else "?",
		hit.damage, hit.combo_scaling, hit.combo_length,
	])


func _on_hit_guarded(_attacker: Node, _victim: Node, hit: HitResult) -> void:
	_push_log("[color=#ffcc44]GUARD[/color] %s  %.1f chip"
		% [str(hit.attack_id), hit.damage])


func _on_parry(defender: Node, _attacker: Node, hit: HitResult) -> void:
	_push_log("[color=#88ddff][b]PARRY[/b][/color] %s blocked %s perfectly" % [
		defender.name if defender != null else "?", str(hit.attack_id)])


func _on_dodged(defender: Node, _attacker: Node) -> void:
	_push_log("[color=#88ccff]DODGE[/color] %s evaded"
		% (defender.name if defender != null else "?"))


func _on_combo_ended(_actor: Node, length: int, dropped: bool) -> void:
	if length <= 1:
		return
	_push_log("combo ended at %d %s" % [
		length,
		"[color=#ff8866](dropped)[/color]" if dropped else "[color=#66ff88](finished)[/color]",
	])


func _on_staggered(actor: Node) -> void:
	_push_log("[color=#ff8866][b]STAGGER[/b][/color] %s poise broken"
		% (actor.name if actor != null else "?"))


func _on_assertion(source: String, message: String) -> void:
	# Routed on screen so a violated invariant is noticed during a playtest
	# instead of scrolling past in a console nobody is watching.
	_push_log("[color=#ff4444][b]ASSERT[/b] %s: %s[/color]" % [source, message])


# --- performance panel ------------------------------------------------------

func _draw_perf() -> void:
	var fps: float = maxf(1.0, Engine.get_frames_per_second())
	var frame_ms: float = 1000.0 / fps
	var draw_calls: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var process_mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	var video_mb: float = float(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0
	var physics_ms: float = Performance.get_monitor(
		Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var lines: PackedStringArray = []
	lines.append("[b]PERFORMANCE[/b]   budgets from docs/TECH_STACK.md")
	lines.append("")

	# Frame time is only a COST when the frame is not simply waiting for the
	# display. On this machine (macOS/Metal) presentation is pinned to the
	# monitor's refresh whatever the vsync setting says, so raw frame time sits
	# permanently at the refresh period. Colouring that red would mark a healthy
	# frame as over budget forever — and a performance panel that is always red
	# is a panel nobody reads.
	if _is_display_capped(fps):
		lines.append("frame   [color=#8899aa]%.1f ms (%d fps, vsync-capped)[/color]"
			% [frame_ms, int(fps)])
		lines.append("        [color=#667788]raw cost hidden by the display "
			+ "cap — judge CPU below[/color]")
	else:
		lines.append("frame   %s   (%d fps)" % [
			_budget(frame_ms, BUDGET_FRAME_MS, "%.1f ms"), int(fps)])

	# Physics time is the honest CPU number: it is real work and never absorbs
	# the present-wait, so it is what actually reveals a combat/AI regression.
	lines.append("cpu     %s physics" % _budget(physics_ms, BUDGET_PHYSICS_MS,
		"%.2f ms"))
	lines.append("draws   %s        memory %s" % [
		_budget(float(draw_calls), float(BUDGET_DRAW_CALLS), "%.0f"),
		_budget(process_mb, BUDGET_PROCESS_MB, "%.0f MB")])
	lines.append("video   %.0f MB        actors %d" % [
		video_mb, CombatDirector.actor_count()])

	_perf_label.text = "\n".join(lines)


## Is the frame rate sitting on the display's refresh rate rather than on a
## real cost? Compared with tolerance because the measured value jitters.
func _is_display_capped(fps: float) -> bool:
	var refresh: float = DisplayServer.screen_get_refresh_rate()
	if refresh <= 0.0:
		refresh = 60.0
	return absf(fps - refresh) <= maxf(1.5, refresh * 0.03)


## Colour a measurement against its budget. Amber from 80%, red past it — an
## early warning is more useful than a failure notice.
func _budget(value: float, budget: float, format: String) -> String:
	var text: String = format % value
	if value > budget:
		return "[color=#ff5544][b]%s[/b][/color]" % text
	if value > budget * 0.8:
		return "[color=#ffcc44]%s[/color]" % text
	return "[color=#66ff88]%s[/color]" % text
