class_name HitboxKeyframe
extends Resource

## One hitbox, active over a frame range within an attack.
##
## An attack owns an array of these rather than a single hitbox, because real
## attacks are not one static volume for their whole active window:
##
##   * A sweeping kick's volume moves with the leg.
##   * A multi-hit flurry needs several independent contacts.
##   * A launcher may have a weak early volume and a strong late one.
##
## Frames are **relative to the start of the attack** (0 = the attack's first
## frame), not absolute. Authoring is therefore independent of when the attack
## was initiated, which is what allows the same attack to be reused from any
## state.

## Which contact group this volume belongs to. Two keyframes sharing a
## `hit_group` can only connect **once** against the same victim.
##
## This is what distinguishes a genuine multi-hit attack from a bug: a moving
## sweep uses several keyframes with the SAME group (one hit, volume follows the
## limb), while a flurry uses DIFFERENT groups (several real hits). Without this
## distinction a moving hitbox would hit once per frame, which is the classic
## "my attack does 900 damage" defect.
@export var hit_group: int = 0

## First frame this volume is live, relative to attack start (0-based, inclusive).
@export_range(0, 240, 1) var first_frame: int = 0

## Last frame this volume is live, relative to attack start (inclusive).
@export_range(0, 240, 1) var last_frame: int = 0

## The volume queried against hurtboxes. A sphere or capsule is almost always
## correct — boxes produce corner cases at the edges of a swing that players
## experience as inconsistency.
@export var shape: Shape3D

## Offset from the actor's origin, in the actor's LOCAL space (+Z forward).
## Local space so the same authored data works at any facing.
@export var offset: Vector3 = Vector3(0.0, 1.0, 0.8)

## Per-volume damage multiplier against the attack's base damage. Lets one
## attack have a weak and a strong region — a "sweet spot" — which rewards
## spacing without needing a separate attack.
@export_range(0.0, 4.0, 0.05) var damage_scale: float = 1.0

## Per-volume stagger multiplier. Independent of damage so a volume can be
## weak but very disruptive, or vice versa.
@export_range(0.0, 4.0, 0.05) var stagger_scale: float = 1.0

## Overrides the attack's reaction for this volume only. Leave EMPTY to inherit.
## Used for attacks whose late frames launch while early frames merely stagger.
@export var override_reaction: HitReaction


## Is this volume live on the given attack-relative frame?
func is_active_on(attack_frame: int) -> bool:
	return attack_frame >= first_frame and attack_frame <= last_frame


## How many frames this volume is live for.
func duration() -> int:
	return maxi(0, last_frame - first_frame + 1)


## Validate authored data. Returns human-readable problems; empty means valid.
## Called by the content validator so a malformed hitbox is caught by tooling
## rather than by a player wondering why an attack does nothing.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if shape == null:
		problems.append("has no shape, so it can never connect")
	if last_frame < first_frame:
		problems.append("last_frame (%d) is before first_frame (%d)"
			% [last_frame, first_frame])
	if first_frame < 0:
		problems.append("first_frame is negative (%d)" % first_frame)
	if damage_scale < 0.0:
		problems.append("damage_scale is negative (%f)" % damage_scale)
	return problems
