class_name CancelWindow
extends Resource

## A frame range during which an attack may be interrupted by another action.
##
## Cancel windows are the primary source of mechanical depth in this combat
## system, and — just as importantly — **the constraints are the content**.
## If every attack cancelled into everything at any time, execution would be
## free and there would be nothing to master. Meaningful mastery comes from
## knowing *which* attack cancels into *what*, *when*, and *only if it hit*.
##
## Frames are relative to the start of the attack (0-based).

## Which action categories this window permits. Bit flags from
## `CombatTypes.CancelInto`.
@export_flags(
	"Attack:1", "Dash:2", "Jump:4", "Guard:8",
	"Dodge:16", "Soul technique:32", "Manifestation:64"
) var cancel_into: int = CombatTypes.CancelInto.ATTACK

## First frame the window is open, relative to attack start (inclusive).
@export_range(0, 240, 1) var first_frame: int = 0

## Last frame the window is open (inclusive).
@export_range(0, 240, 1) var last_frame: int = 0

## What contact outcome is required for this window to open at all.
##
## `ON_HIT` is the workhorse: it makes a connected attack expressive while
## leaving a whiff genuinely punishable. `ON_WHIFF` enables deliberate feint
## design. `ANY` should be used sparingly — an always-open cancel removes the
## risk from throwing the attack out.
@export var requires: CombatTypes.ContactRequirement = \
	CombatTypes.ContactRequirement.ANY

## Optional whitelist of attack ids reachable through this window. Empty means
## "any edge the combo graph allows". A whitelist here is the tighter of the two
## constraints and is meant for special cases — routine routing belongs in the
## combo graph, where it is visible as a graph.
@export var allowed_attack_ids: Array[StringName] = []

## If true, taking this cancel preserves the current combo counter and its
## damage scaling. If false the cancel resets the combo — the mechanism that
## stops a single loop from being optimal forever.
@export var preserves_combo: bool = true


func is_open_on(attack_frame: int) -> bool:
	return attack_frame >= first_frame and attack_frame <= last_frame


func allows(action: CombatTypes.CancelInto) -> bool:
	return (cancel_into & int(action)) != 0


## Is the contact requirement satisfied by what the attack actually touched?
func contact_satisfied(did_hit: bool, did_guard: bool) -> bool:
	match requires:
		CombatTypes.ContactRequirement.ANY:
			return true
		CombatTypes.ContactRequirement.ON_HIT:
			return did_hit
		CombatTypes.ContactRequirement.ON_GUARD:
			return did_guard
		CombatTypes.ContactRequirement.ON_CONTACT:
			return did_hit or did_guard
		CombatTypes.ContactRequirement.ON_WHIFF:
			return not did_hit and not did_guard
	return false


## Full check: is this window usable for `action` on `attack_frame`, given what
## the attack has touched so far?
func permits(action: CombatTypes.CancelInto, attack_frame: int,
		did_hit: bool, did_guard: bool) -> bool:
	return is_open_on(attack_frame) \
		and allows(action) \
		and contact_satisfied(did_hit, did_guard)


func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if last_frame < first_frame:
		problems.append("last_frame (%d) is before first_frame (%d)"
			% [last_frame, first_frame])
	if cancel_into == CombatTypes.CancelInto.NONE:
		problems.append("permits no actions, so the window has no effect")
	if first_frame < 0:
		problems.append("first_frame is negative (%d)" % first_frame)
	return problems
