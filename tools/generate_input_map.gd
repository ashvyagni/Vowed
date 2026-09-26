# VOWED — default input binding generator
#
# This script is the SOURCE OF TRUTH for the game's default control scheme.
# Run it to (re)generate the [input] section of project.godot:
#
#     godot --headless --path . -s tools/generate_input_map.gd
#
# Why a script instead of hand-editing project.godot: InputEvent serialisation
# is verbose and version-sensitive. Letting the engine write it removes a whole
# class of silent parse errors, and keeps the canonical binding list readable
# here as code rather than as serialised object soup.
#
# Design notes:
#   * Keyboard bindings use PHYSICAL keycodes so the layout survives non-QWERTY
#     keyboards — "the key where J is", not "the key that types J".
#   * Gamepad bindings are authored in parallel from M1 rather than retrofitted.
#     Bolting a second input device onto a finished combat system is expensive,
#     and combat feel differs enough between stick and keyboard that both need
#     to be playable while the system is still being tuned.
#   * Every gameplay action is rebindable. Debug actions deliberately are not.

extends SceneTree


const DEADZONE: float = 0.25


func _initialize() -> void:
	var actions: Dictionary = _build_actions()

	# Clear any previously generated actions so this script is idempotent and
	# removing a binding here actually removes it from the project.
	for setting: String in ProjectSettings.get_property_list().map(
			func(p: Dictionary) -> String: return str(p.get("name", ""))):
		if setting.begins_with("input/"):
			ProjectSettings.set_setting(setting, null)

	for action_name: String in actions:
		var events: Array = actions[action_name]
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": DEADZONE,
			"events": events,
		})

	var err: int = ProjectSettings.save()
	if err != OK:
		printerr("FAILED to save project settings: %d" % err)
		quit(1)
		return

	print("Generated %d input actions." % actions.size())
	quit(0)


# --- binding table ---------------------------------------------------------

func _build_actions() -> Dictionary:
	var a: Dictionary = {}

	# --- Movement ----------------------------------------------------------
	a["move_forward"] = [_key(KEY_W), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)]
	a["move_back"]    = [_key(KEY_S), _joy_axis(JOY_AXIS_LEFT_Y,  1.0)]
	a["move_left"]    = [_key(KEY_A), _joy_axis(JOY_AXIS_LEFT_X, -1.0)]
	a["move_right"]   = [_key(KEY_D), _joy_axis(JOY_AXIS_LEFT_X,  1.0)]

	# --- Core combat verbs (master directive §25) --------------------------
	# J = Kick, K = Punch, Space = Jump, Shift = Dash,
	# Q = Guard/Parry, E = Soul Technique, R = Manifestation.
	a["kick"]           = [_key(KEY_J),     _joy_btn(JOY_BUTTON_Y)]
	a["punch"]          = [_key(KEY_K),     _joy_btn(JOY_BUTTON_X)]
	a["jump"]           = [_key(KEY_SPACE), _joy_btn(JOY_BUTTON_A)]
	a["dash"]           = [_key(KEY_SHIFT), _joy_btn(JOY_BUTTON_RIGHT_SHOULDER)]
	a["guard"]          = [_key(KEY_Q),     _joy_btn(JOY_BUTTON_LEFT_SHOULDER)]
	a["soul_technique"] = [_key(KEY_E),     _joy_btn(JOY_BUTTON_B)]
	a["manifestation"]  = [_key(KEY_R),     _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]

	# --- Interaction / camera ---------------------------------------------
	a["interact"] = [_key(KEY_F),   _joy_btn(JOY_BUTTON_DPAD_UP)]
	a["lock_on"]  = [_key(KEY_TAB), _joy_btn(JOY_BUTTON_RIGHT_STICK)]

	# --- Shell -------------------------------------------------------------
	a["menu"]         = [_key(KEY_ESCAPE), _joy_btn(JOY_BUTTON_START)]
	a["map"]          = [_key(KEY_M),      _joy_btn(JOY_BUTTON_BACK)]
	a["journal"]      = [_key(KEY_TAB, true)]   # Shift+Tab
	a["ui_confirm_x"] = [_key(KEY_ENTER),  _joy_btn(JOY_BUTTON_A)]

	# --- Debug (not rebindable, stripped from release builds) -------------
	# These exist from M1 because combat cannot be tuned without them.
	a["debug_toggle_overlay"]  = [_key(KEY_F1)]
	a["debug_toggle_hitboxes"] = [_key(KEY_F2)]
	a["debug_frame_step"]      = [_key(KEY_F3)]
	a["debug_toggle_pause"]    = [_key(KEY_F4)]
	a["debug_slowmo"]          = [_key(KEY_F5)]
	a["debug_reset_lab"]       = [_key(KEY_F6)]

	return a


# --- event constructors ----------------------------------------------------

func _key(physical_keycode: Key, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical_keycode
	e.shift_pressed = shift
	return e


func _joy_btn(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
