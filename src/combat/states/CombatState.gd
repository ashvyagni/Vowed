class_name CombatState
extends RefCounted

## The combat states an actor can be in, and what each one permits.
##
## Kept small on purpose. Every added state multiplies the transition surface
## that has to be reasoned about and tested, and combat bugs overwhelmingly live
## in transitions rather than in states. Anything expressible as a property of an
## existing state (hitstop, armour, invulnerability) is a property, not a state.

enum Id {
	NEUTRAL,     ## Idle or moving freely. Everything is available.
	ATTACKING,   ## Executing an AttackData. Cancels gated by its windows.
	GUARDING,    ## Guard held. Can block; cannot attack.
	PARRYING,    ## Inside the perfect-parry window. Brief and decisive.
	DODGING,     ## Evasive movement, possibly with invulnerability frames.
	HITSTUN,     ## Struck; unable to act. The combo victim's state.
	LAUNCHED,    ## Airborne from a launcher. Gateway to being air-combo'd.
	STAGGERED,   ## Poise broken. A long punish window.
	KNOCKDOWN,   ## On the ground.
	WAKEUP,      ## Getting up. Usually briefly invulnerable.
	DEAD,
}


static func name_of(state: Id) -> String:
	match state:
		Id.NEUTRAL:   return "Neutral"
		Id.ATTACKING: return "Attacking"
		Id.GUARDING:  return "Guarding"
		Id.PARRYING:  return "Parrying"
		Id.DODGING:   return "Dodging"
		Id.HITSTUN:   return "Hitstun"
		Id.LAUNCHED:  return "Launched"
		Id.STAGGERED: return "Staggered"
		Id.KNOCKDOWN: return "Knockdown"
		Id.WAKEUP:    return "Wakeup"
		Id.DEAD:      return "Dead"
	return "?"


## Can the actor start a NEW action from this state without a cancel window?
## ATTACKING is excluded deliberately: leaving an attack early must go through a
## cancel window, which is where execution skill lives.
static func accepts_free_action(state: Id) -> bool:
	return state == Id.NEUTRAL or state == Id.GUARDING


## Is the actor unable to act at all? These are the states a player is *being
## punished* in, and the reason a dropped combo matters.
static func is_helpless(state: Id) -> bool:
	return state == Id.HITSTUN or state == Id.LAUNCHED \
		or state == Id.STAGGERED or state == Id.KNOCKDOWN \
		or state == Id.DEAD


## Can the actor be hit in this state? Invulnerability during DODGING and WAKEUP
## is frame-windowed rather than blanket, so those remain hittable states.
static func is_hittable(state: Id) -> bool:
	return state != Id.DEAD


## Does this state block an incoming attack?
static func is_defensive(state: Id) -> bool:
	return state == Id.GUARDING or state == Id.PARRYING


## Map a state to the target-state condition combo edges test against, so routing
## and state never drift apart.
static func to_target_state(state: Id, grounded: bool) -> CombatTypes.TargetState:
	match state:
		Id.LAUNCHED:  return CombatTypes.TargetState.LAUNCHED
		Id.STAGGERED: return CombatTypes.TargetState.STAGGERED
		Id.KNOCKDOWN: return CombatTypes.TargetState.KNOCKED_DOWN
		Id.GUARDING, Id.PARRYING: return CombatTypes.TargetState.GUARDING
		_:
			return CombatTypes.TargetState.GROUNDED if grounded \
				else CombatTypes.TargetState.AIRBORNE
