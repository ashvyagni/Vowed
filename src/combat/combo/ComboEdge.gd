class_name ComboEdge
extends Resource

## One authored route from one attack to another.
##
## The combo system is a **directed graph authored as data**: nodes are attacks,
## edges are these. A 100+ route move set is 100+ authored edge resources, which
## is tractable. Expressing the same thing as branching code would not be — and
## more importantly, would not be inspectable, testable or tunable by anyone
## looking at the move set as a whole.
##
## Every field beyond `from`/`to`/`action` is a CONDITION. Conditions are what
## make routes situational rather than arbitrary button strings: an aerial
## follow-up exists because the target is airborne, not because someone decided
## `K,K,J` should do something.

# --- the route --------------------------------------------------------------

## Source attack id. `&""` means "from neutral" — the entry point into a string.
@export var from: StringName = &""

## Destination attack id. Must exist in `data/attacks/`; the content validator
## checks this, so a typo is caught by tooling rather than by a route that
## silently never fires.
@export var to: StringName = &""

## Input that takes this route.
@export var action: CombatAction.Id = CombatAction.Id.PUNCH

## Tie-break when several edges match the same situation. Higher wins.
##
## Ties are a **content defect**, not a runtime one: two equally-valid routes
## from the same state on the same button means the move set is ambiguous and the
## player cannot form a reliable mental model. The validator reports them.
@export_range(0, 100, 1) var priority: int = 0

## Does taking this route keep the combo counter and its damage scaling?
##
## Combo semantics belong to the ROUTE, not to the cancel window that allowed it:
## timing lives in the attack, routing lives in the graph, and "does this continue
## the combo" is a routing question. Setting this false is how a loop is closed so
## that one repeatable sequence cannot stay optimal forever.
@export var preserves_combo: bool = true

@export_multiline var designer_notes: String = ""


# --- conditions: the actor -------------------------------------------------

@export_group("Conditions — actor")

@export var require_stance: CombatTypes.Stance = CombatTypes.Stance.EITHER

## Directional requirement. `NEUTRAL` is not the same as `ANY`: it actively
## requires no movement input, which is how a neutral attack and a forward
## attack can share a button.
@export var require_direction: CombatTypes.Direction = CombatTypes.Direction.ANY

## What the source attack must have touched. The single most valuable condition
## available: `ON_HIT` makes a connected attack expressive while leaving a whiff
## genuinely punishable.
@export var require_contact: CombatTypes.ContactRequirement = \
	CombatTypes.ContactRequirement.ANY

## Frame window within the source attack during which this route is available.
## `(-1, -1)` defers entirely to the source attack's cancel windows, which is
## the normal case — put timing in the attack, and routing in the graph.
##
## Set it only where one route out of an attack needs a tighter window than the
## rest, e.g. a just-frame link that rewards precision.
@export var require_frame_window: Vector2i = Vector2i(-1, -1)

## Minimum combo length. Used for routes that only open deep into a string.
@export_range(0, 50, 1) var min_combo_length: int = 0

## Maximum combo length, `-1` for none. Used to close a loop so one repeatable
## sequence cannot be optimal forever.
@export_range(-1, 50, 1) var max_combo_length: int = -1


# --- conditions: the target -------------------------------------------------

@export_group("Conditions — target")

@export var require_target_state: CombatTypes.TargetState = \
	CombatTypes.TargetState.ANY

## Maximum distance to the target, `-1` for unlimited. Spacing as a route
## condition: a close-range follow-up should not be available from across the
## arena even when everything else matches.
@export_range(-1.0, 50.0, 0.1) var max_target_distance: float = -1.0


# --- conditions: Soul (M3) --------------------------------------------------

@export_group("Conditions — Soul")

## Soul required. `&""` means the route is universal.
@export var require_soul: StringName = &""

@export var require_manifestation: bool = false

## Required named Soul passive state, e.g. `&"fury_ignited"`.
##
## This is the mechanism by which a Soul passive **changes how the player
## fights** rather than changing a number: FURY IGNITION does not add damage, it
## makes a set of edges like this one become legal. Soul-gated routes are the
## implementation of that design rule.
@export var require_passive_state: StringName = &""

@export_range(0.0, 100.0, 0.5) var min_resonance: float = 0.0


# --- evaluation -------------------------------------------------------------

## Does this edge apply in `context`?
##
## Pure function of (self, context) — no side effects, no globals. That is what
## makes every route in the game unit-testable.
func matches(context: ComboContext) -> bool:
	if context.current_attack != from:
		return false
	if not _stance_ok(context):
		return false
	if not CombatTypes.direction_satisfies(require_direction, context.direction):
		return false
	if not _contact_ok(context):
		return false
	if not _frame_window_ok(context):
		return false
	if not _combo_length_ok(context):
		return false
	if not _target_ok(context):
		return false
	if not _soul_ok(context):
		return false
	return true


func _stance_ok(context: ComboContext) -> bool:
	match require_stance:
		CombatTypes.Stance.GROUNDED: return context.grounded
		CombatTypes.Stance.AIRBORNE: return not context.grounded
		_: return true


func _contact_ok(context: ComboContext) -> bool:
	match require_contact:
		CombatTypes.ContactRequirement.ANY:
			return true
		CombatTypes.ContactRequirement.ON_HIT:
			return context.did_hit
		CombatTypes.ContactRequirement.ON_GUARD:
			return context.did_guard
		CombatTypes.ContactRequirement.ON_CONTACT:
			return context.did_hit or context.did_guard
		CombatTypes.ContactRequirement.ON_WHIFF:
			return not context.did_hit and not context.did_guard
	return false


func _frame_window_ok(context: ComboContext) -> bool:
	if require_frame_window.x < 0:
		return true
	return context.attack_frame >= require_frame_window.x \
		and context.attack_frame <= require_frame_window.y


func _combo_length_ok(context: ComboContext) -> bool:
	if context.combo_length < min_combo_length:
		return false
	if max_combo_length >= 0 and context.combo_length > max_combo_length:
		return false
	return true


func _target_ok(context: ComboContext) -> bool:
	if require_target_state != CombatTypes.TargetState.ANY \
			and context.target_state != require_target_state:
		return false
	if max_target_distance >= 0.0 and context.target_distance > max_target_distance:
		return false
	return true


func _soul_ok(context: ComboContext) -> bool:
	if require_soul != &"" and context.soul_id != require_soul:
		return false
	if require_manifestation and not context.manifesting:
		return false
	if require_passive_state != &"" and context.passive_state != require_passive_state:
		return false
	if context.resonance < min_resonance:
		return false
	return true


## Do two edges compete for the same input from the same source? Used by the
## validator to find ambiguous routes, which are a content defect.
func conflicts_with(other: ComboEdge) -> bool:
	if from != other.from or action != other.action:
		return false
	if priority != other.priority:
		return false  # priority resolves it deterministically
	# Differing conditions may still be mutually exclusive, but any overlap at
	# equal priority is worth a warning: the ordering would be arbitrary.
	return require_stance == other.require_stance \
		and require_direction == other.require_direction \
		and require_contact == other.require_contact \
		and require_target_state == other.require_target_state \
		and require_soul == other.require_soul \
		and require_manifestation == other.require_manifestation \
		and require_passive_state == other.require_passive_state


func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var label: String = describe()

	if to == &"":
		problems.append("%s: 'to' is empty — the route goes nowhere" % label)
	if to == from and from != &"":
		problems.append("%s: routes an attack to itself, which would loop "
			% label + "indefinitely unless max_combo_length closes it")
	if require_frame_window.x >= 0 \
			and require_frame_window.y < require_frame_window.x:
		problems.append("%s: frame window end (%d) is before its start (%d)"
			% [label, require_frame_window.y, require_frame_window.x])
	if max_combo_length >= 0 and max_combo_length < min_combo_length:
		problems.append("%s: max_combo_length (%d) is below min_combo_length "
			% [label, max_combo_length] + "(%d), so the edge can never match"
			% min_combo_length)
	if require_manifestation and require_soul == &"":
		problems.append("%s: requires Manifestation but names no Soul — "
			% label + "probably an authoring oversight")
	return problems


## Compact route notation for debug overlays and the generated move list, e.g.
## `neutral --PUNCH--> jab_1` or `jab_1 --KICK[fwd,on_hit]--> spin_kick`.
func describe() -> String:
	var conditions: PackedStringArray = []
	if require_direction != CombatTypes.Direction.ANY:
		conditions.append(CombatTypes.direction_name(require_direction))
	if require_contact == CombatTypes.ContactRequirement.ON_HIT:
		conditions.append("on_hit")
	elif require_contact == CombatTypes.ContactRequirement.ON_GUARD:
		conditions.append("on_guard")
	elif require_contact == CombatTypes.ContactRequirement.ON_WHIFF:
		conditions.append("on_whiff")
	if require_stance == CombatTypes.Stance.AIRBORNE:
		conditions.append("air")
	elif require_stance == CombatTypes.Stance.GROUNDED:
		conditions.append("ground")
	if require_manifestation:
		conditions.append("manifest")
	if require_passive_state != &"":
		conditions.append(str(require_passive_state))

	var condition_text: String = ""
	if not conditions.is_empty():
		condition_text = "[%s]" % ",".join(conditions)

	return "%s --%s%s--> %s" % [
		"neutral" if from == &"" else str(from),
		CombatAction.display_name(action).to_upper(),
		condition_text,
		str(to) if to != &"" else "<none>",
	]
