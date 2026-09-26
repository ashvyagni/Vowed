class_name CombatTypes
extends RefCounted

## Shared combat enumerations and bit flags.
##
## These live in one place because they are referenced by authored resources,
## the state machine, the combo graph and the AI. Duplicating them per-file is
## how two definitions of "heavy hit" end up disagreeing.
##
## Never reorder or remove an enum value: authored `.tres` files store enums as
## integers, so reordering silently rewrites the meaning of every existing
## resource. Append new values at the end only.


## What kind of attack this is. Drives Soul interactions (e.g. "alternating
## attack categories builds momentum"), animation sets, and combo conditions.
enum Category {
	PUNCH,      ## Hand strike. K by default.
	KICK,       ## Leg strike. J by default.
	SPECIAL,    ## Command normal — a directional or dash attack.
	SOUL,       ## Soul technique. Consumes or interacts with resonance.
	THROW,      ## Grab. Ignores guard.
	BEAST,      ## Only available during Manifestation.
}


## Where the attack must be blocked, and what can block it at all.
enum Height {
	HIGH,          ## Blockable standing.
	MID,           ## Blockable standing or crouching.
	LOW,           ## Must be blocked crouching.
	OVERHEAD,      ## Must be blocked standing; beats a crouching guard.
	UNBLOCKABLE,   ## Guard does not stop it. Must be dodged or interrupted.
}


## What stance the attack can be initiated from.
enum Stance {
	GROUNDED,   ## Ground only.
	AIRBORNE,   ## Air only.
	EITHER,     ## Both, with the same frame data.
}


## How the victim reacts. Determines hitstun, whether a combo continues, and
## which follow-up routes are available — so this is a *design* choice about
## combo structure, not merely a visual one.
enum ReactionKind {
	LIGHT,      ## Brief flinch. Chains into fast follow-ups.
	MEDIUM,     ## Clear stagger. Standard combo filler.
	HEAVY,      ## Large recoil with pushback. Often ends ground routes.
	LAUNCH,     ## Sends the victim airborne. The gateway to aerial routes.
	SWEEP,      ## Knocks the legs out. Grounded knockdown, no air route.
	CRUMPLE,    ## Slow collapse. A long punish window — reward for a hard hit.
	SPIN,       ## Spinning stagger. Turns the victim, enabling back-hit routes.
	KNOCKDOWN,  ## Straight to the floor. Forces a wake-up situation.
	WALL_SPLAT, ## Pins against geometry, extending a combo near walls.
}


## Which action categories a cancel window permits. Bit flags so one window can
## allow several — and, more importantly, so a window can allow *some* and
## deny others. The denials are what create mastery: if everything cancelled
## into everything, execution would be free.
enum CancelInto {
	NONE           = 0,
	ATTACK         = 1 << 0,  ## Another attack via a combo-graph edge.
	DASH           = 1 << 1,  ## Dash cancel — the core movement-expression tool.
	JUMP           = 1 << 2,  ## Jump cancel. Gateway to ground-to-air routes.
	GUARD          = 1 << 3,  ## Cancel into guard. Grants defensive safety.
	DODGE          = 1 << 4,  ## Cancel into an evasive roll or step.
	SOUL_TECHNIQUE = 1 << 5,  ## Cancel into a Soul technique.
	MANIFESTATION  = 1 << 6,  ## Cancel into Manifestation. Deliberately rare.
}


## What contact outcome a cancel window requires.
##
## This is one of the highest-value depth mechanics available: "you may dash-
## cancel this only if it connected" makes a whiff genuinely punishable while
## keeping a successful hit expressive. Frame data alone cannot express that —
## contact requirements can.
enum ContactRequirement {
	ANY,        ## Always available.
	ON_HIT,     ## Only if a hurtbox was struck.
	ON_GUARD,   ## Only if the attack was blocked.
	ON_CONTACT, ## Hit or guarded — anything but a whiff.
	ON_WHIFF,   ## Only if nothing was touched. For deliberate feint design.
}


## How a motion keyframe applies to the actor's velocity.
enum MotionMode {
	SET,      ## Replace velocity. Predictable, used for most attack lunges.
	ADD,      ## Add to velocity. Preserves momentum for flowing routes.
	DAMPEN,   ## Scale existing velocity toward zero. For grounding an attack.
}


## Guard state of a defender at the moment of contact.
enum GuardState {
	NONE,        ## Not guarding.
	GUARDING,    ## Guard held. Reduced damage, chip, pushback.
	PARRY_ACTIVE,## Inside the perfect-parry window.
}


## Result of resolving one hitbox against one hurtbox. Used by the resolver and
## the event bus.
enum ContactResult {
	MISS,        ## No intersection.
	HIT,         ## Clean hit.
	GUARDED,     ## Stopped by guard.
	PARRIED,     ## Perfect parry — attacker is punished instead.
	DODGED,      ## Defender had active invulnerability frames.
	ARMORED,     ## Defender had interrupt armour: damage applies, no reaction.
	TRADED,      ## Both actors connected on the same frame.
}


## Human-readable name for a category, for debug overlays and tooling.
static func category_name(category: Category) -> String:
	match category:
		Category.PUNCH:   return "Punch"
		Category.KICK:    return "Kick"
		Category.SPECIAL: return "Special"
		Category.SOUL:    return "Soul"
		Category.THROW:   return "Throw"
		Category.BEAST:   return "Beast"
	return "Unknown"


static func reaction_name(kind: ReactionKind) -> String:
	match kind:
		ReactionKind.LIGHT:      return "Light"
		ReactionKind.MEDIUM:     return "Medium"
		ReactionKind.HEAVY:      return "Heavy"
		ReactionKind.LAUNCH:     return "Launch"
		ReactionKind.SWEEP:      return "Sweep"
		ReactionKind.CRUMPLE:    return "Crumple"
		ReactionKind.SPIN:       return "Spin"
		ReactionKind.KNOCKDOWN:  return "Knockdown"
		ReactionKind.WALL_SPLAT: return "Wall splat"
	return "Unknown"


## Whether a reaction sends the victim airborne, and therefore whether aerial
## follow-up routes become legal.
static func reaction_is_airborne(kind: ReactionKind) -> bool:
	return kind == ReactionKind.LAUNCH or kind == ReactionKind.WALL_SPLAT


## Whether a reaction puts the victim on the floor, forcing a wake-up.
static func reaction_is_knockdown(kind: ReactionKind) -> bool:
	return kind == ReactionKind.KNOCKDOWN or kind == ReactionKind.SWEEP
