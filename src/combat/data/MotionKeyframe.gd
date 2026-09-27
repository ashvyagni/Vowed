class_name MotionKeyframe
extends Resource

## Authored movement applied to the attacker during an attack.
##
## Attack displacement is **authored data, not extracted from animation**
## (docs/TECH_STACK.md §7). This is a deliberate choice with real consequences:
##
##   * Attack spacing becomes a *design* value that can be tuned in seconds,
##     rather than requiring a re-export from a DCC tool.
##   * Movement stays deterministic and identical at every frame rate, which
##     animation-extracted root motion does not guarantee.
##   * External animations from mixed sources can be used without inheriting
##     whatever translation their original author baked in — essential when
##     prototyping on open-licence asset packs.
##
## The visual cost is that animation and authored motion must be tuned to agree.
## That is a smaller price than losing deterministic spacing.

## Attack-relative frame on which this impulse applies (0-based).
@export_range(0, 240, 1) var frame: int = 0

## Velocity in AUTHORING space: +Z is FORWARD, +Y is up.
##
## As with `HitboxKeyframe.offset`, this is NOT Godot's local space (where
## forward is -Z). `apply()` performs the conversion, so authored data reads the
## way a designer thinks: a lunge is a positive Z number.
@export var velocity: Vector3 = Vector3.ZERO

@export var mode: CombatTypes.MotionMode = CombatTypes.MotionMode.SET

## For DAMPEN: the factor existing velocity is scaled by.
@export_range(0.0, 1.0, 0.05) var dampen_factor: float = 0.5

## Whether the vertical component is applied. Most ground attacks should leave
## gravity alone; only deliberate hops and dive attacks set it.
@export var affects_vertical: bool = false


## Apply this keyframe to a velocity, given the actor's facing basis.
## Pure function of its inputs — no side effects — so it is directly unit-testable.
func apply(current: Vector3, basis: Basis) -> Vector3:
	# Authoring space (+Z forward) -> Godot local space (-Z forward) -> world.
	# Converted here rather than at call sites, so the convention lives in one
	# place and a caller cannot silently drive an attack backwards.
	var world_velocity: Vector3 = basis * Vector3(
		velocity.x, velocity.y, -velocity.z)
	var result: Vector3 = current

	match mode:
		CombatTypes.MotionMode.SET:
			result.x = world_velocity.x
			result.z = world_velocity.z
			if affects_vertical:
				result.y = world_velocity.y
		CombatTypes.MotionMode.ADD:
			result.x += world_velocity.x
			result.z += world_velocity.z
			if affects_vertical:
				result.y += world_velocity.y
		CombatTypes.MotionMode.DAMPEN:
			result.x *= dampen_factor
			result.z *= dampen_factor
			if affects_vertical:
				result.y *= dampen_factor

	return result


func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if frame < 0:
		problems.append("frame is negative (%d)" % frame)
	if mode != CombatTypes.MotionMode.DAMPEN and velocity.is_zero_approx():
		problems.append("velocity is zero on a %s keyframe, so it has no effect"
			% ("SET" if mode == CombatTypes.MotionMode.SET else "ADD"))
	return problems
