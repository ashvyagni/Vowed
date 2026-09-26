class_name ComboContext
extends RefCounted

## The situation in which a combo edge is evaluated.
##
## Everything a route can condition on, gathered into one object so that edge
## evaluation is a **pure function** of (edge, context). That purity is what makes
## the whole combo graph unit-testable headlessly, with no actor, no scene and no
## renderer — which in turn is what makes a 100+ route move set maintainable.
## Routes that can only be verified by playing them cannot be verified at all
## once there are a hundred of them.
##
## Reused in place each frame rather than reallocated: this is built for every
## actor, every frame.

# --- the actor ---------------------------------------------------------------

## Attack currently executing, or `&""` in neutral.
var current_attack: StringName = &""

## Frames into the current attack (0-based).
var attack_frame: int = 0

var grounded: bool = true

## Discrete movement direction, already resolved target-relative where relevant.
var direction: CombatTypes.Direction = CombatTypes.Direction.NEUTRAL

# --- what the current attack touched ---------------------------------------
#
# These gate contact requirements — the mechanism behind "you may only cancel
# this if it connected", which is what keeps a whiff punishable while letting a
# successful hit be expressive.

var did_hit: bool = false
var did_guard: bool = false

# --- the target -------------------------------------------------------------

var target_state: CombatTypes.TargetState = CombatTypes.TargetState.NONE

## Metres to the target. `INF` when there is none.
var target_distance: float = INF

# --- Soul (M3) --------------------------------------------------------------

var soul_id: StringName = &""
var manifesting: bool = false
var resonance: float = 0.0

## Named Soul passive state, e.g. `&"fury_ignited"` for Infiroar's FURY
## IGNITION. A `StringName` rather than a bool so one Soul can have several
## escalating states — which is what lets a passive *deepen* with continued
## clean play instead of simply toggling.
var passive_state: StringName = &""

# --- combo ------------------------------------------------------------------

## Hits landed in the current combo. 0 in neutral.
var combo_length: int = 0

## Combat frame this context was built on. Debug and logging only.
var frame: int = 0


func reset() -> void:
	current_attack = &""
	attack_frame = 0
	grounded = true
	direction = CombatTypes.Direction.NEUTRAL
	did_hit = false
	did_guard = false
	target_state = CombatTypes.TargetState.NONE
	target_distance = INF
	soul_id = &""
	manifesting = false
	resonance = 0.0
	passive_state = &""
	combo_length = 0
	frame = 0


func is_neutral() -> bool:
	return current_attack == &""


func has_target() -> bool:
	return target_state != CombatTypes.TargetState.NONE


func describe() -> String:
	return "f%d from[%s]@%d %s dir=%s target=%s%s%s" % [
		frame,
		"neutral" if is_neutral() else str(current_attack),
		attack_frame,
		"ground" if grounded else "air",
		CombatTypes.direction_name(direction),
		int(target_state),
		"  hit" if did_hit else ("  guard" if did_guard else ""),
		"  MANIFEST" if manifesting else "",
	]
