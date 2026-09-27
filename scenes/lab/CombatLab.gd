extends Node3D

## The Combat Lab — an isolated arena for tuning combat.
##
## Exists BEFORE any real level, on purpose. Tuning combat inside a real
## environment is slow and confounded: terrain, props, lighting and enemy
## placement all change how a hit feels, so a change cannot be attributed to the
## change that was made. The Lab removes every variable except the combat.
##
## Controls beyond the debug keys (F1-F6):
##   1-5   set every dummy's behaviour mode
##   F6    reset the arena

const HINT_LINES: Array[String] = [
	"MOVE  WASD        JUMP  Space      DASH  Shift",
	"PUNCH K           KICK  J          GUARD/PARRY  Q (hold/tap)",
	"SOUL  E           MANIFEST  R      LOCK ON  Tab",
	"",
	"F1 overlay   F2 hitboxes   F3 step   F4 pause   F5 slow-mo   F6 reset",
	"1 idle  2 block  3 parry  4 counter  5 aggressive   (dummy mode)",
]

var _hint: Label
var _mode_label: Label


func _ready() -> void:
	# The configuration self-check moves here with the main scene. It is not
	# dropped: the locked technical decisions (60 Hz tick, Forward+, Jolt, layer
	# allocation) all fail SILENTLY, and a project quietly running at the wrong
	# tick produces combat bugs that get debugged as gameplay problems for days.
	add_child(Bootstrap.new())

	# Inert unless --capture= is passed on the command line.
	add_child(AutoCapture.new())

	_build_hint_ui()
	print_rich("[b]Combat Lab[/b] ready — %d actor(s) registered."
		% CombatDirector.actor_count())


func _build_hint_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.position = Vector2(-520, -140)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.78)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var column := VBoxContainer.new()
	panel.add_child(column)

	_hint = Label.new()
	_hint.text = "\n".join(HINT_LINES)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	column.add_child(_hint)

	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 12)
	_mode_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6))
	column.add_child(_mode_label)
	_update_mode_label(TrainingDummyIntent.Mode.IDLE)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey

	var mode: int = -1
	match key.physical_keycode:
		KEY_1: mode = int(TrainingDummyIntent.Mode.IDLE)
		KEY_2: mode = int(TrainingDummyIntent.Mode.BLOCK)
		KEY_3: mode = int(TrainingDummyIntent.Mode.PARRY)
		KEY_4: mode = int(TrainingDummyIntent.Mode.COUNTER)
		KEY_5: mode = int(TrainingDummyIntent.Mode.AGGRESSIVE)
		_: return

	_set_dummy_mode(mode as TrainingDummyIntent.Mode)


func _set_dummy_mode(mode: TrainingDummyIntent.Mode) -> void:
	for actor: Actor in CombatDirector.actors():
		var intent := actor.intent_source as TrainingDummyIntent
		if intent != null:
			intent.mode = mode
			intent.reset()
	_update_mode_label(mode)


func _update_mode_label(mode: TrainingDummyIntent.Mode) -> void:
	if _mode_label != null:
		_mode_label.text = "dummy mode: %s" % TrainingDummyIntent.mode_name(mode)
