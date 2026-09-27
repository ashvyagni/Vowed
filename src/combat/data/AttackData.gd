class_name AttackData
extends Resource

## One complete attack, authored entirely as data.
##
## This is the central content type of the combat system. Every attack in the
## game — player normals, Soul techniques, enemy moves, Manifestation and Beast
## attacks — is an instance of this resource in `data/attacks/`.
##
## NOTHING about an attack lives in code. The combat state machine reads this
## resource and executes it. That is the `src/` ⟂ `data/` rule
## (docs/ARCHITECTURE.md §1) at its most important: adding an attack must never
## mean writing a script, or a 100+ route move set is unreachable.
##
## ALL timing is in 60 Hz combat frames. Never seconds.
##
## The frame model:
##
##     frame:  0 ....... startup-1 | startup ... startup+active-1 | ... total-1
##             └── STARTUP ────────┘└── ACTIVE ─────────────────┘└── RECOVERY ┘
##               committed,           hitboxes can be live         vulnerable,
##               no hitboxes                                       cancellable
##
## Hitbox keyframes address frames within the whole attack, not within the
## active window, so an attack may deliberately have live frames that do not
## span its entire nominal active window.

# --- identity --------------------------------------------------------------

## Stable unique id, referenced by combo-graph edges, Souls and AI.
## `StringName` because it is compared every frame (docs/TECH_STACK.md §3.2).
## Renaming this breaks every reference to it — treat it as permanent.
@export var id: StringName = &""

## Name shown in the move list and debug overlay.
@export var display_name: String = ""

## Animation name in the actor's `AnimationPlayer`. The animation is SEEKED to
## match the combat frame — it never drives timing.
@export var animation: StringName = &""

## Which slice of that animation maps onto this attack, in SECONDS.
## `anim_end` of -1 means "to the end of the animation".
##
## Source animations are almost never the same length as the attack that uses
## them — Punch_Jab is 50 frames while jab_1 is 14 — so the attack's progress
## (0..1) is mapped linearly onto this window.
##
## Authored rather than stretched blindly, because the designer's real job here
## is to ALIGN THE IMPACT: the moment the fist extends in the animation should
## land on the attack's active frames. Get that wrong and the hit reads as
## early or late no matter how correct the frame data is — which is precisely
## the "combat feels off" complaint that is impossible to diagnose from
## numbers alone.
@export var anim_start: float = 0.0
@export var anim_end: float = -1.0

## Playback speed multiplier applied on top of the window mapping. Mainly for
## reusing one animation across a fast and a slow variant of the same motion.
@export_range(0.1, 4.0, 0.05) var anim_speed: float = 1.0

## True when `animation` is a stand-in that does not depict this attack —
## e.g. a sword swing standing in for a kick because no kick animation exists
## in the asset set yet.
##
## Recorded as data so the gap is VISIBLE and countable rather than a thing
## someone half-remembers. `tools/validate_content.gd` reports the total.
@export var anim_is_placeholder: bool = false


## Map an attack-relative frame onto a playback position in the animation,
## in seconds. `animation_length` is the source clip's length.
func animation_time(attack_frame: int, animation_length: float) -> float:
	var start: float = clampf(anim_start, 0.0, animation_length)
	var finish: float = animation_length if anim_end < 0.0 \
		else clampf(anim_end, start, animation_length)
	var span: float = finish - start
	if span <= 0.0:
		return start

	var total: int = maxi(1, total_frames() - 1)
	var progress: float = clampf(float(attack_frame) / float(total), 0.0, 1.0)
	return start + span * progress * anim_speed

@export_multiline var designer_notes: String = ""


# --- classification --------------------------------------------------------

@export_group("Classification")

@export var category: CombatTypes.Category = CombatTypes.Category.PUNCH
@export var height: CombatTypes.Height = CombatTypes.Height.MID
@export var stance: CombatTypes.Stance = CombatTypes.Stance.GROUNDED

## Trade priority when two attacks connect on the same frame. Higher wins; equal
## values trade and both actors take the hit. Explicit priority is only possible
## because hit resolution is an ordered pass rather than physics callbacks
## (docs/TECH_STACK.md §5.2).
@export_range(0, 10, 1) var priority: int = 1


# --- timing ----------------------------------------------------------------

@export_group("Timing (frames @ 60Hz)")

## Frames before the active window. The attack is committed and has no hitbox.
## This is the tell the opponent reads, so it is a readability value as much as
## a balance one: a 3-frame startup is unreactable and should be reserved for
## deliberately oppressive tools.
@export_range(1, 120, 1) var startup: int = 6

## Frames during which hitboxes may be live.
@export_range(1, 120, 1) var active: int = 3

## Frames after the active window before returning to neutral. The punish
## window when the attack whiffs.
@export_range(1, 180, 1) var recovery: int = 12

## Frames both actors freeze on a clean hit. Hitstop is what makes a hit feel
## like it has weight, and it is felt more than seen — a heavy hit with no
## hitstop reads as a hit that did not land.
@export_range(0, 30, 1) var hitstop: int = 5

## Hitstop when the attack is guarded. Usually shorter than a clean hit, so the
## difference between hitting and being blocked is legible through feel alone,
## with no UI.
@export_range(0, 30, 1) var guard_hitstop: int = 3


# --- volumes and effect ----------------------------------------------------

@export_group("Hitboxes and effect")

@export var hitboxes: Array[HitboxKeyframe] = []

## Reaction on a clean hit. Shared between attacks so that "medium stagger"
## means one consistent thing across the whole move set.
@export var on_hit: HitReaction

## Reaction when guarded. If null, the defender takes guard pushback only.
@export var on_guard: HitReaction

@export_range(0.0, 999.0, 0.5) var damage: float = 8.0

## Poise damage. Separate from damage so an attack can be weak but disruptive,
## or strong but easy to armour through — an independent axis for enemy design.
@export_range(0.0, 999.0, 0.5) var stagger_damage: float = 10.0

## Damage dealt through a guard.
@export_range(0.0, 99.0, 0.5) var chip_damage: float = 0.0

## Resonance granted on a clean hit. Contributes to the Soul economy (M3):
## resonance is earned by skilled play, so it is authored per attack rather
## than accrued passively.
@export_range(0.0, 100.0, 0.5) var resonance_on_hit: float = 1.0

## Resonance granted on a guarded hit — lower, because being blocked is a
## worse outcome and should pay less.
@export_range(0.0, 100.0, 0.5) var resonance_on_guard: float = 0.25


# --- cancels and motion ----------------------------------------------------

@export_group("Cancels and motion")

@export var cancel_windows: Array[CancelWindow] = []

## Authored displacement. See `MotionKeyframe` for why this is data rather than
## animation-extracted.
@export var motion: Array[MotionKeyframe] = []


# --- properties ------------------------------------------------------------

@export_group("Properties")

## Hits absorbed before this attack can be interrupted. Armour lets an attack
## be *committed* rather than merely slow — the main tool for making a heavy
## attack threatening without making it fast.
@export_range(0, 5, 1) var interrupt_armor: int = 0

## Invulnerability window, attack-relative `[first, last]` inclusive.
## `(-1, -1)` = none. Used by dodge-attacks and reversals.
@export var invulnerable_frames: Vector2i = Vector2i(-1, -1)

## Resonance required to use this attack. Non-zero only for Soul techniques.
@export_range(0.0, 100.0, 0.5) var resonance_cost: float = 0.0

## Requires an active Manifestation.
@export var requires_manifestation: bool = false

## Soul that grants this attack. Empty = available to everyone.
@export var required_soul: StringName = &""

## Does landing cut this attack short? True for most air attacks, so that air
## routes end on contact with the ground instead of playing out awkwardly.
@export var cancelled_by_landing: bool = true


# --- derived ---------------------------------------------------------------

## Total frames from initiation to neutral.
func total_frames() -> int:
	return startup + active + recovery


## First frame of the nominal active window.
func first_active_frame() -> int:
	return startup


## Last frame of the nominal active window.
func last_active_frame() -> int:
	return startup + active - 1


## Is the attack inside its nominal active window on this frame?
func is_active_window(attack_frame: int) -> bool:
	return attack_frame >= first_active_frame() \
		and attack_frame <= last_active_frame()


## Frames remaining until neutral. Used for frame-advantage calculations, which
## is how "is my follow-up guaranteed?" is answered.
func frames_remaining(attack_frame: int) -> int:
	return maxi(0, total_frames() - attack_frame)


## Is the actor invulnerable on this frame?
func is_invulnerable_on(attack_frame: int) -> bool:
	if invulnerable_frames.x < 0:
		return false
	return attack_frame >= invulnerable_frames.x \
		and attack_frame <= invulnerable_frames.y


## Hitbox volumes live on this frame.
func active_hitboxes_on(attack_frame: int) -> Array[HitboxKeyframe]:
	var result: Array[HitboxKeyframe] = []
	for box: HitboxKeyframe in hitboxes:
		if box != null and box.is_active_on(attack_frame):
			result.append(box)
	return result


## Motion keyframes that apply on this frame.
func motion_on(attack_frame: int) -> Array[MotionKeyframe]:
	var result: Array[MotionKeyframe] = []
	for key: MotionKeyframe in motion:
		if key != null and key.frame == attack_frame:
			result.append(key)
	return result


## The first cancel window permitting `action` on this frame, or null.
func find_cancel(action: CombatTypes.CancelInto, attack_frame: int,
		did_hit: bool, did_guard: bool) -> CancelWindow:
	for window: CancelWindow in cancel_windows:
		if window != null and window.permits(action, attack_frame, did_hit, did_guard):
			return window
	return null


func can_be_used_airborne() -> bool:
	return stance == CombatTypes.Stance.AIRBORNE \
		or stance == CombatTypes.Stance.EITHER


func can_be_used_grounded() -> bool:
	return stance == CombatTypes.Stance.GROUNDED \
		or stance == CombatTypes.Stance.EITHER


# --- validation ------------------------------------------------------------

## Validate authored data. Returns human-readable problems; empty means valid.
##
## Run over every attack by `tools/validate_content.gd`, so a malformed attack
## is caught by tooling in seconds rather than by a player wondering why a move
## does nothing. Content-as-data is only an advantage if the content is
## *checkable*, and this is what makes it checkable.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var label: String = str(id) if id != &"" else "<unnamed attack>"

	if id == &"":
		problems.append("%s: id is empty — combo edges cannot reference it" % label)
	if animation == &"":
		problems.append("%s: animation is empty — the actor would hold its "
			% label + "bind pose for the whole attack")
	if anim_end >= 0.0 and anim_end <= anim_start:
		problems.append("%s: anim_end (%.3f) is not after anim_start (%.3f), "
			% [label, anim_end, anim_start] + "so the clip would not advance")
	if on_hit == null:
		problems.append("%s: on_hit reaction is null — a connecting hit would "
			% label + "have no effect on the victim")

	if hitboxes.is_empty():
		problems.append("%s: has no hitboxes, so it can never connect" % label)

	var total: int = total_frames()
	for i: int in hitboxes.size():
		var box: HitboxKeyframe = hitboxes[i]
		if box == null:
			problems.append("%s: hitbox[%d] is null" % [label, i])
			continue
		for p: String in box.validate():
			problems.append("%s: hitbox[%d] %s" % [label, i, p])
		if box.last_frame >= total:
			problems.append("%s: hitbox[%d] stays live to frame %d, past the "
				% [label, i, box.last_frame]
				+ "attack's last frame (%d) — those frames never execute"
				% (total - 1))
		if box.first_frame < startup:
			problems.append("%s: hitbox[%d] goes live on frame %d, during "
				% [label, i, box.first_frame]
				+ "startup (ends frame %d). The attack has no tell."
				% (startup - 1))

	for i: int in cancel_windows.size():
		var window: CancelWindow = cancel_windows[i]
		if window == null:
			problems.append("%s: cancel_window[%d] is null" % [label, i])
			continue
		for p: String in window.validate():
			problems.append("%s: cancel_window[%d] %s" % [label, i, p])
		if window.last_frame >= total:
			problems.append("%s: cancel_window[%d] extends to frame %d, past "
				% [label, i, window.last_frame]
				+ "the attack's last frame (%d)" % (total - 1))

	for i: int in motion.size():
		var key: MotionKeyframe = motion[i]
		if key == null:
			problems.append("%s: motion[%d] is null" % [label, i])
			continue
		for p: String in key.validate():
			problems.append("%s: motion[%d] %s" % [label, i, p])
		if key.frame >= total:
			problems.append("%s: motion[%d] is on frame %d, past the attack's "
				% [label, i, key.frame] + "last frame (%d)" % (total - 1))

	if on_hit != null:
		for p: String in on_hit.validate():
			problems.append("%s: on_hit %s" % [label, p])

	if invulnerable_frames.x >= 0 and invulnerable_frames.y < invulnerable_frames.x:
		problems.append("%s: invulnerable_frames end (%d) is before its start (%d)"
			% [label, invulnerable_frames.y, invulnerable_frames.x])

	if resonance_cost > 0.0 and category != CombatTypes.Category.SOUL \
			and not requires_manifestation:
		problems.append("%s: costs resonance (%.1f) but is not a SOUL category "
			% [label, resonance_cost] + "attack and does not require "
			+ "Manifestation — probably a misclassification")

	return problems


## One-line summary for the debug overlay, in standard frame-data notation.
func frame_data_summary() -> String:
	return "%s  %d/%d/%d  dmg %.0f  hitstop %d" % [
		str(id), startup, active, recovery, damage, hitstop,
	]
