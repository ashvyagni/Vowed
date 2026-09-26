class_name HitResult
extends RefCounted

## The outcome of resolving one hitbox against one hurtbox, for one frame.
##
## `RefCounted`, not `Resource`: this is transient runtime data produced and
## discarded every frame, never authored or saved. Making it a `Resource` would
## invite it being serialised, which would be meaningless.
##
## Carries everything a consumer needs so that UI, audio, VFX, camera and AI can
## each react without querying back into combat. That one-way flow is what keeps
## `combat` free of dependencies on its own observers
## (docs/ARCHITECTURE.md §2.1).

var attacker: Node = null
var victim: Node = null

## The attack that produced this contact.
var attack_id: StringName = &""

## Which contact group of the attack connected. Lets a multi-hit flurry be
## distinguished from a single moving volume in logs and feedback.
var hit_group: int = 0

var result: CombatTypes.ContactResult = CombatTypes.ContactResult.MISS

## Damage actually applied, after guard reduction and combo scaling. This is the
## final number, not the authored one — consumers should never recompute it.
var damage: float = 0.0
var stagger_damage: float = 0.0

## Reaction applied to the victim. Null when guarded, parried or dodged.
var reaction: HitReaction = null

## World-space contact point, for VFX placement.
var position: Vector3 = Vector3.ZERO

## Direction from attacker to victim, for directional feedback and pushback.
var direction: Vector3 = Vector3.FORWARD

## Combo length including this hit, 1 for a fresh combo.
var combo_length: int = 1

## Damage scaling applied because of combo length. 1.0 = unscaled.
var combo_scaling: float = 1.0

## The combat frame this contact resolved on. Essential for debugging: "why did
## that not combo?" is answered by comparing frame stamps.
var frame: int = 0

## True when the victim was airborne at contact — aerial routes and reactions
## frequently differ.
var victim_airborne: bool = false

## True when the attack struck the victim from behind. Reserved for M2 punish
## design and back-hit routes.
var from_behind: bool = false

## True when both actors connected on the same frame and traded.
var was_trade: bool = false


func is_clean_hit() -> bool:
	return result == CombatTypes.ContactResult.HIT \
		or result == CombatTypes.ContactResult.TRADED


func was_stopped_by_defence() -> bool:
	return result == CombatTypes.ContactResult.GUARDED \
		or result == CombatTypes.ContactResult.PARRIED \
		or result == CombatTypes.ContactResult.DODGED


## Should this contact extend a combo? A guarded or dodged attack does not.
func continues_combo() -> bool:
	return is_clean_hit() or result == CombatTypes.ContactResult.ARMORED


## One-line description for the debug log. Combat is only tunable if what
## happened can be read back afterwards.
func describe() -> String:
	var kind: String = "?"
	match result:
		CombatTypes.ContactResult.MISS:    kind = "MISS"
		CombatTypes.ContactResult.HIT:     kind = "HIT"
		CombatTypes.ContactResult.GUARDED: kind = "GUARD"
		CombatTypes.ContactResult.PARRIED: kind = "PARRY"
		CombatTypes.ContactResult.DODGED:  kind = "DODGE"
		CombatTypes.ContactResult.ARMORED: kind = "ARMOR"
		CombatTypes.ContactResult.TRADED:  kind = "TRADE"
	return "f%d %s %s -> %s  dmg %.1f (x%.2f)  combo %d%s" % [
		frame, kind, str(attack_id),
		victim.name if victim != null else "<none>",
		damage, combo_scaling, combo_length,
		"  [air]" if victim_airborne else "",
	]
