extends Node

## Project-wide notification bus. Autoload singleton: `GameEvents`.
##
## SCOPE — read before adding a signal here.
##
## This bus carries *notifications* ("this happened"), never *commands* ("do
## this"). Commands are direct, typed method calls on the system that owns the
## behaviour.
##
## The distinction is load-bearing. In a codebase where everything is routed
## through a bus, a stack trace stops answering "how did we get here", and
## control flow becomes unfollowable exactly when a bug is hardest to find.
## Signals are for decoupling *observers* — UI, audio, VFX, analytics, debug
## logging — from gameplay systems that should not know those observers exist.
##
## A signal belongs here only if BOTH hold:
##   1. Several unrelated systems need to react to it, and
##   2. The emitter should not know who they are.
##
## If exactly one system cares, that system should hold a direct reference and
## the signal belongs on the emitting object instead. A bus signal with one
## listener is indirection with no benefit.

# --- Combat feedback -------------------------------------------------------
#
# Emitted by hit resolution. Consumed by UI, audio, VFX and camera shake —
# none of which combat knows about. This is the bus's clearest justified use:
# combat resolves a hit and is finished; five presentation systems react.

## A hitbox connected with a hurtbox and damage was applied.
signal hit_landed(attacker: Node, victim: Node, hit: HitResult)

## An attack was stopped by an active guard.
signal hit_guarded(attacker: Node, victim: Node, hit: HitResult)

## A perfect parry succeeded. Distinct from `hit_guarded` because the feedback
## must be unmistakably different — parry is the highest-skill defensive
## outcome and the player has to *know* it worked from feel alone.
signal parry_succeeded(defender: Node, attacker: Node, hit: HitResult)

## An attack was evaded by a dodge with active invulnerability frames.
signal attack_dodged(defender: Node, attacker: Node)

## An attack whiffed entirely — no hurtbox intersected during its active frames.
## Useful for AI punish learning and for combat analytics during tuning.
signal attack_whiffed(attacker: Node, attack_id: StringName)

## An actor's stagger threshold was exceeded and it entered a stagger state.
signal actor_staggered(actor: Node)

## An actor was launched into the air, opening an aerial route.
signal actor_launched(actor: Node, launch_velocity: Vector3)

## An actor's health reached zero.
signal actor_defeated(actor: Node)


# --- Combo / expression ----------------------------------------------------

## The player extended a combo. `length` is the number of connected hits.
## Consumed by UI (combo counter) and by resonance accounting.
signal combo_extended(actor: Node, length: int)

## A combo ended, either by dropping it or by the route terminating.
signal combo_ended(actor: Node, length: int, was_dropped: bool)


# --- Soul (M3) -------------------------------------------------------------
#
# Declared now, emitted from M3. They are listed here rather than added later
# because audio, VFX, camera and UI all hook the same events, and discovering
# that at M3 tends to produce a scramble of ad-hoc references.

## Soul resonance changed. `delta` is signed so feedback can distinguish
## gaining resonance from spending it.
signal resonance_changed(actor: Node, current: float, maximum: float, delta: float)

## A Soul passive entered or left its active state — e.g. Infiroar's
## FURY IGNITION igniting after a clean three-hit melee sequence.
signal soul_passive_state_changed(actor: Node, soul_id: StringName, state: StringName)

signal manifestation_begun(actor: Node, soul_id: StringName)
signal manifestation_ended(actor: Node, soul_id: StringName)


# --- World / progression (M4+) ---------------------------------------------

## A world-state flag changed. The mechanism by which defeating a Prime Beast
## permanently alters NPC dialogue, merchants, routes and environment.
signal world_state_changed(key: StringName, value: Variant)

signal region_entered(region_id: StringName)
signal region_exited(region_id: StringName)


# --- Debug -----------------------------------------------------------------

## Raised when a system detects a state it believes impossible. Routed through
## the bus so the debug overlay can surface it on screen during playtesting
## rather than letting it scroll past in the console unnoticed.
signal assertion_failed(source: String, message: String)


## Report a violated invariant. Prefer this over a bare `push_error` for
## gameplay-state problems: it reaches the on-screen overlay, which is where a
## problem gets noticed during a playtest.
func report_assertion(source: String, message: String) -> void:
	push_error("[%s] %s" % [source, message])
	assertion_failed.emit(source, message)
