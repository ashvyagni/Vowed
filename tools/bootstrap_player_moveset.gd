# VOWED — one-time bootstrap of the player's starting move set.
#
#     godot --headless --path . -s tools/bootstrap_player_moveset.gd
#
# WHAT THIS IS, AND WHAT IT IS NOT
#
# This is a BOOTSTRAP, not a build step. It writes the initial .tres resources so
# that the first move set exists in a guaranteed-valid format (hand-writing .tres
# with sub-resources is a needless source of parse errors). Once written, THE
# .TRES FILES ARE THE SOURCE OF TRUTH and are edited in the Godot editor like any
# other content. Re-running this OVERWRITES authored tuning, so it should not be
# re-run casually.
#
# It is kept in the repository because the frame-data reasoning below is worth
# preserving in a readable form, and because it documents the intended shape of a
# move set for anyone authoring the next one.
#
# ---------------------------------------------------------------------------
# FRAME DATA DESIGN
#
# The single most important relationship in the whole system:
#
#     frame advantage = victim hitstun - attacker's remaining frames at contact
#
# Positive means the follow-up is GUARANTEED. That is what makes a combo a combo
# rather than a hopeful guess. Every link below was checked against this.
#
# Worked example — jab_1 into jab_2:
#   jab_1 is 4/2/8 (14 total) and connects on frame 4.
#   Its cancel window opens on frame 6, so the player cancels 2 frames after
#   contact, with 14 - 2 = 12 frames of the victim's hitstun left.
#   jab_2 has 5 startup, so it connects 5 frames later. 12 > 5 -> guaranteed.
#
# The speed/risk curve is deliberate and consistent:
#   * fast pokes (4-6 startup) are safe but low reward
#   * mid attacks (7-9) trade reach and damage for commitment
#   * heavies (11-14) hit hard, are armoured, and are severely punishable on whiff
#
# Nothing here is final. It is a starting point built to be tuned from playtests,
# which is exactly why the frame-data debug readout exists.

extends SceneTree

const REACTION_DIR: String = "res://data/attacks/reactions/"
const ATTACK_DIR: String = "res://data/attacks/player/"
const DATA_DIR: String = "res://data/"
const ACTOR_DIR: String = "res://data/actors/"

var _reactions: Dictionary = {}
var _attacks: Dictionary = {}
var _library: AttackLibrary
var _graph: ComboGraph
var _written: int = 0


func _initialize() -> void:
	for dir: String in [REACTION_DIR, ATTACK_DIR, ACTOR_DIR,
			DATA_DIR + "combos/"]:
		DirAccess.make_dir_recursive_absolute(dir)

	_build_reactions()
	_build_attacks()
	_build_library()
	_build_graph()
	_build_motion_profile()

	print("\nWrote %d resource(s)." % _written)
	_report()
	quit(0)


# --- shared reactions -------------------------------------------------------
#
# Reactions are shared between attacks on purpose: "medium stagger" must mean one
# consistent thing across the whole move set, or the player can never build
# reliable intuition about what links into what.

func _build_reactions() -> void:
	# PUSHBACK IS A SPACING BUDGET, not a flavour value.
	#
	# The integration test caught this: at 2.5 m/s, jab_1's pushback moved the
	# target ~0.4 m during its own hitstun — past the 1.24 m reach of jab_2 — so
	# the basic three-hit string could not physically connect. The frame data was
	# correct and the combo was still impossible.
	#
	# Light attacks now barely move the target, so strings stay connected. Heavy
	# attacks push hard, which is what ENDS a string and forces the attacker to
	# re-establish position. Pushback is therefore the main tool deciding which
	# attacks continue pressure and which reset neutral.
	_reaction(&"light", CombatTypes.ReactionKind.LIGHT, 14, 0.9, 0.10)
	_reaction(&"medium", CombatTypes.ReactionKind.MEDIUM, 18, 1.8, 0.15)
	_reaction(&"heavy", CombatTypes.ReactionKind.HEAVY, 24, 5.5, 0.30)

	# LAUNCH is the gateway to every aerial route. float_frames is what makes an
	# air combo a SYSTEM rather than a frame-perfect trick: without hang time,
	# only a pixel-perfect input could follow up.
	var launch: HitReaction = _reaction(&"launch",
		CombatTypes.ReactionKind.LAUNCH, 34, 1.0, 0.25)
	launch.launch_velocity = Vector3(0.0, 9.0, 1.5)
	launch.float_frames = 26
	launch.float_gravity_scale = 0.32
	_save(launch, REACTION_DIR + "launch.tres")

	var crumple: HitReaction = _reaction(&"crumple",
		CombatTypes.ReactionKind.CRUMPLE, 40, 1.0, 0.20)
	_save(crumple, REACTION_DIR + "crumple.tres")

	var knockdown: HitReaction = _reaction(&"knockdown",
		CombatTypes.ReactionKind.KNOCKDOWN, 26, 5.0, 0.35)
	knockdown.causes_knockdown = true
	_save(knockdown, REACTION_DIR + "knockdown.tres")

	# A spinning reaction deliberately does NOT reorient the victim, which is
	# what makes back-hit routes possible.
	var spin: HitReaction = _reaction(&"spin",
		CombatTypes.ReactionKind.SPIN, 22, 2.0, 0.18)
	spin.reorients_victim = false
	_save(spin, REACTION_DIR + "spin.tres")


func _reaction(id: StringName, kind: CombatTypes.ReactionKind, hitstun: int,
		pushback: float, shake: float) -> HitReaction:
	var r := HitReaction.new()
	r.kind = kind
	r.hitstun_frames = hitstun
	r.pushback = pushback
	r.camera_shake = shake
	r.vulnerable_tail_frames = 4
	_reactions[id] = r
	if kind in [CombatTypes.ReactionKind.LIGHT, CombatTypes.ReactionKind.MEDIUM,
			CombatTypes.ReactionKind.HEAVY]:
		_save(r, REACTION_DIR + "%s.tres" % id)
	return r


# --- attacks ----------------------------------------------------------------

func _build_attacks() -> void:
	# HITSTOP VALUES
	#
	# Hitstop is the single strongest contributor to whether a hit reads as
	# having landed, and it is FELT rather than seen. The first pass used 3-8
	# frames, which is below the threshold where it registers at all — the fist
	# appeared to pass through the target.
	#
	# Roughly doubled and scaled by weight. Safe to raise only because hitstop
	# now freezes BOTH actors: freezing the attacker alone would subtract a
	# frame of advantage for every frame of hitstop and silently break the
	# combos that depend on it.

	# === GROUND PUNCH STRING (K) ============================================
	# The bread and butter: fast, safe, low reward. Where neutral play lives.

	var jab_1 := _attack(&"jab_1", "Jab", CombatTypes.Category.PUNCH,
		4, 2, 8, &"light", 6.0, 8.0, 6)
	_hitbox(jab_1, 4, 5, 0.42, Vector3(0.18, 1.32, 0.72))
	_cancel(jab_1, 6, 13, CombatTypes.CancelInto.ATTACK
		| CombatTypes.CancelInto.DASH | CombatTypes.CancelInto.GUARD)
	# A small step in. Combined with reduced light pushback, a string closes
	# distance slightly instead of drifting apart as it goes.
	_motion(jab_1, 4, Vector3(0.0, 0.0, 1.5))
	jab_1.designer_notes = "Fastest option. 4f startup keeps it reactable but " \
		+ "barely. Safe on block; the tool for contesting neutral."

	var jab_2 := _attack(&"jab_2", "Cross", CombatTypes.Category.PUNCH,
		5, 2, 10, &"light", 7.0, 9.0, 6)
	_hitbox(jab_2, 5, 6, 0.44, Vector3(-0.18, 1.34, 0.80))
	_cancel(jab_2, 7, 15, CombatTypes.CancelInto.ATTACK
		| CombatTypes.CancelInto.DASH | CombatTypes.CancelInto.JUMP
		| CombatTypes.CancelInto.GUARD)
	_motion(jab_2, 5, Vector3(0.0, 0.0, 2.2))

	# The string's ender: stronger, but its recovery means committing to it.
	var straight := _attack(&"straight", "Straight", CombatTypes.Category.PUNCH,
		7, 3, 15, &"medium", 12.0, 16.0, 9)
	_hitbox(straight, 7, 9, 0.50, Vector3(0.0, 1.32, 0.92))
	# ON_HIT only: a whiffed ender stays punishable, which is what stops the
	# string being a free mash.
	_cancel(straight, 10, 18, CombatTypes.CancelInto.ATTACK,
		CombatTypes.ContactRequirement.ON_HIT)
	_motion(straight, 7, Vector3(0.0, 0.0, 3.4))
	straight.designer_notes = "String ender. Only cancels ON HIT, so mashing " \
		+ "into it on block is punished."

	# === GROUND KICK STRING (J) ============================================
	# Slower, longer reach, more reward. The spacing tool.

	var low_kick := _attack(&"low_kick", "Low Kick", CombatTypes.Category.KICK,
		6, 3, 12, &"medium", 9.0, 12.0, 7)
	low_kick.height = CombatTypes.Height.LOW
	_hitbox(low_kick, 6, 8, 0.46, Vector3(0.0, 0.42, 0.88))
	_cancel(low_kick, 9, 16, CombatTypes.CancelInto.ATTACK
		| CombatTypes.CancelInto.DASH | CombatTypes.CancelInto.GUARD)
	low_kick.designer_notes = "Hits low. Beats a standing guard once crouch " \
		+ "guard exists at M2."

	var roundhouse := _attack(&"roundhouse", "Roundhouse",
		CombatTypes.Category.KICK, 9, 3, 19, &"heavy", 16.0, 22.0, 11)
	# Two keyframes, SAME hit group: the volume follows the leg through the arc
	# but still connects exactly once. Different groups here would be the classic
	# "my attack does 900 damage" bug.
	_hitbox(roundhouse, 9, 10, 0.52, Vector3(0.30, 1.05, 0.80), 0)
	_hitbox(roundhouse, 11, 11, 0.52, Vector3(-0.30, 1.05, 0.80), 0)
	_cancel(roundhouse, 12, 21, CombatTypes.CancelInto.ATTACK,
		CombatTypes.ContactRequirement.ON_HIT)
	_motion(roundhouse, 9, Vector3(0.0, 0.0, 2.6))
	roundhouse.designer_notes = "Big reward, 19f recovery. Whiffing it is a " \
		+ "full punish."

	# === LAUNCHER ==========================================================
	# The structural gateway to air combat: 12f startup is readable, and armour
	# is what makes it COMMITTED rather than merely slow.

	var uppercut := _attack(&"uppercut", "Rising Palm",
		CombatTypes.Category.PUNCH, 12, 4, 22, &"launch", 14.0, 26.0, 12)
	uppercut.priority = 3
	uppercut.interrupt_armor = 1
	_hitbox(uppercut, 12, 15, 0.56, Vector3(0.0, 1.55, 0.62))
	# Jump-cancellable ON HIT: the player follows their victim up. This single
	# window is what turns a launcher into an air combo.
	_cancel(uppercut, 14, 24, CombatTypes.CancelInto.JUMP
		| CombatTypes.CancelInto.ATTACK, CombatTypes.ContactRequirement.ON_HIT)
	_motion(uppercut, 12, Vector3(0.0, 0.0, 1.4))
	uppercut.designer_notes = "THE launcher. 1 armour point lets it trade " \
		+ "through a jab, so it is a real commitment rather than a slow poke."

	# === OVERHEAD / KNOCKDOWN ==============================================

	var axe_kick := _attack(&"axe_kick", "Axe Kick", CombatTypes.Category.KICK,
		14, 3, 24, &"knockdown", 18.0, 30.0, 12)
	axe_kick.height = CombatTypes.Height.OVERHEAD
	axe_kick.interrupt_armor = 1
	_hitbox(axe_kick, 14, 16, 0.50, Vector3(0.0, 0.95, 0.78))
	_motion(axe_kick, 14, Vector3(0.0, 0.0, 1.8))
	axe_kick.designer_notes = "Overhead, forces a knockdown. The answer to a " \
		+ "crouching turtle."

	# === COMMAND NORMALS (direction + button) ==============================
	# One button, several attacks, chosen by stick direction. This is how a large
	# move set comes out of a 7-key input language instead of an ability bar.

	var lunge_punch := _attack(&"lunge_punch", "Lunging Palm",
		CombatTypes.Category.SPECIAL, 10, 3, 18, &"medium", 13.0, 18.0, 9)
	_hitbox(lunge_punch, 10, 12, 0.48, Vector3(0.0, 1.28, 1.05))
	_motion(lunge_punch, 8, Vector3(0.0, 0.0, 9.5))
	_motion(lunge_punch, 13, Vector3(0.0, 0.0, 0.0), CombatTypes.MotionMode.DAMPEN)
	_cancel(lunge_punch, 13, 20, CombatTypes.CancelInto.ATTACK,
		CombatTypes.ContactRequirement.ON_HIT)
	lunge_punch.designer_notes = "Forward+K. Closes distance. Authored motion, " \
		+ "so its reach is a tunable number rather than an animation artifact."

	var sweep := _attack(&"sweep", "Sweep", CombatTypes.Category.SPECIAL,
		11, 3, 22, &"knockdown", 11.0, 20.0, 10)
	sweep.height = CombatTypes.Height.LOW
	_hitbox(sweep, 11, 13, 0.54, Vector3(0.0, 0.28, 0.85))
	sweep.designer_notes = "Back+J. Low knockdown with long recovery: a " \
		+ "read, not a poke."

	var spin_kick := _attack(&"spin_kick", "Spinning Heel",
		CombatTypes.Category.SPECIAL, 10, 4, 18, &"spin", 13.0, 20.0, 9)
	_hitbox(spin_kick, 10, 13, 0.58, Vector3(0.0, 1.10, 0.75), 0)
	_cancel(spin_kick, 14, 20, CombatTypes.CancelInto.ATTACK
		| CombatTypes.CancelInto.DASH, CombatTypes.ContactRequirement.ON_CONTACT)
	spin_kick.designer_notes = "Spins the victim without reorienting them, " \
		+ "which opens back-hit routes."

	# === AERIAL ============================================================
	# Air attacks end on landing, so routes resolve into the ground instead of
	# playing out awkwardly through the landing.

	var air_punch := _attack(&"air_punch", "Air Palm",
		CombatTypes.Category.PUNCH, 5, 3, 12, &"light", 8.0, 10.0, 7)
	air_punch.stance = CombatTypes.Stance.AIRBORNE
	_hitbox(air_punch, 5, 7, 0.46, Vector3(0.0, 1.10, 0.72))
	_cancel(air_punch, 7, 14, CombatTypes.CancelInto.ATTACK
		| CombatTypes.CancelInto.DASH)

	var air_kick := _attack(&"air_kick", "Air Kick", CombatTypes.Category.KICK,
		7, 3, 14, &"medium", 11.0, 14.0, 9)
	air_kick.stance = CombatTypes.Stance.AIRBORNE
	_hitbox(air_kick, 7, 9, 0.50, Vector3(0.0, 0.85, 0.80))
	_cancel(air_kick, 10, 16, CombatTypes.CancelInto.ATTACK,
		CombatTypes.ContactRequirement.ON_HIT)

	# The air-to-ground finisher: ends the aerial route decisively.
	var dive_kick := _attack(&"dive_kick", "Diving Heel",
		CombatTypes.Category.SPECIAL, 8, 6, 20, &"knockdown", 17.0, 26.0, 12)
	dive_kick.stance = CombatTypes.Stance.AIRBORNE
	_hitbox(dive_kick, 8, 13, 0.52, Vector3(0.0, 0.60, 0.68))
	_motion(dive_kick, 8, Vector3(0.0, -13.0, 6.0), CombatTypes.MotionMode.SET, true)
	dive_kick.designer_notes = "Air-to-ground finisher. Drives downward, so it " \
		+ "resolves an air combo into a knockdown on the ground."

	# === DASH ATTACKS ======================================================

	var dash_punch := _attack(&"dash_punch", "Dash Palm",
		CombatTypes.Category.SPECIAL, 6, 3, 16, &"medium", 12.0, 17.0, 9)
	_hitbox(dash_punch, 6, 8, 0.48, Vector3(0.0, 1.26, 0.95))
	_motion(dash_punch, 4, Vector3(0.0, 0.0, 7.5))
	_cancel(dash_punch, 9, 18, CombatTypes.CancelInto.ATTACK,
		CombatTypes.ContactRequirement.ON_HIT)

	var dash_kick := _attack(&"dash_kick", "Dash Heel",
		CombatTypes.Category.SPECIAL, 8, 3, 20, &"heavy", 15.0, 21.0, 10)
	_hitbox(dash_kick, 8, 10, 0.52, Vector3(0.0, 1.00, 0.98))
	_motion(dash_kick, 6, Vector3(0.0, 0.0, 8.5))

	# === COUNTER (guard cancel) ============================================
	# Fast, invulnerable on startup, and available only out of guard — the reward
	# for holding a block correctly rather than a universal reversal.

	var counter_palm := _attack(&"counter_palm", "Counter Palm",
		CombatTypes.Category.SPECIAL, 5, 3, 16, &"crumple", 14.0, 24.0, 14)
	counter_palm.priority = 5
	counter_palm.invulnerable_frames = Vector2i(0, 4)
	_hitbox(counter_palm, 5, 7, 0.50, Vector3(0.0, 1.30, 0.80))
	_motion(counter_palm, 5, Vector3(0.0, 0.0, 3.0))
	counter_palm.designer_notes = "Only reachable from guard. Invulnerable " \
		+ "through startup, crumples on hit — the payoff for blocking well."


# --- animation mapping ------------------------------------------------------
#
# Clip lengths and IMPACT times are measured, not guessed —
# `godot --headless --path . res://tools/ImpactProbe.tscn` samples the striking
# limb frame by frame and reports where it is furthest forward.
#
# Re-measure and update these if the animation set is ever replaced.

const CLIP_JAB: Array = ["Punch_Jab", 0.833, 0.233]
const CLIP_CROSS: Array = ["Punch_Cross", 1.000, 0.300]
const CLIP_SWING: Array = ["Sword_Attack", 1.500, 0.267]
const CLIP_THRUST: Array = ["Spell_Simple_Shoot", 0.500, 0.150]


## Map a clip onto an attack so the animation's IMPACT lands on the attack's
## first ACTIVE frame.
##
## The attack's progress (0..1) maps linearly onto [anim_start, anim_end], so
## placing the window is the whole job: solve for the start that puts `impact`
## at the moment the hitbox goes live. Without this the hit reads as early or
## late regardless of how correct the frame data is.
##
## `placeholder` marks a clip that does not depict the attack — recorded as data
## so the gap stays visible and countable rather than half-remembered.
func _anim(attack: AttackData, clip: Array, placeholder: bool = false,
		coverage: float = 0.8) -> void:
	var name: String = clip[0]
	var length: float = clip[1]
	var impact: float = clip[2]

	attack.animation = StringName(name)
	attack.anim_is_placeholder = placeholder

	var total: int = maxi(1, attack.total_frames() - 1)
	var progress_at_impact: float = float(attack.startup) / float(total)

	var span: float = length * coverage
	var start: float = clampf(impact - span * progress_at_impact, 0.0, length)
	attack.anim_start = start
	attack.anim_end = minf(start + span, length)


# --- builders ---------------------------------------------------------------

func _attack(id: StringName, display: String, category: CombatTypes.Category,
		startup: int, active: int, recovery: int, reaction: StringName,
		damage: float, stagger: float, hitstop: int) -> AttackData:
	var a := AttackData.new()
	a.id = id
	a.display_name = display
	a.animation = id
	a.category = category
	a.startup = startup
	a.active = active
	a.recovery = recovery
	a.damage = damage
	a.stagger_damage = stagger
	a.hitstop = hitstop
	a.guard_hitstop = maxi(1, hitstop - 2)
	a.chip_damage = damage * 0.08
	a.on_hit = _reactions[reaction]
	a.on_guard = _reactions[&"light"]
	a.resonance_on_hit = 1.0 + damage * 0.08
	a.resonance_on_guard = 0.3
	_attacks[id] = a
	return a


func _hitbox(a: AttackData, first: int, last: int, radius: float,
		offset: Vector3, group: int = 0) -> void:
	var box := HitboxKeyframe.new()
	box.hit_group = group
	box.first_frame = first
	box.last_frame = last
	var shape := SphereShape3D.new()
	shape.radius = radius
	box.shape = shape
	box.offset = offset
	a.hitboxes.append(box)


func _cancel(a: AttackData, first: int, last: int, into: int,
		requires: CombatTypes.ContactRequirement = \
			CombatTypes.ContactRequirement.ANY) -> void:
	var w := CancelWindow.new()
	w.first_frame = first
	w.last_frame = last
	w.cancel_into = into
	w.requires = requires
	a.cancel_windows.append(w)


func _motion(a: AttackData, frame: int, velocity: Vector3,
		mode: CombatTypes.MotionMode = CombatTypes.MotionMode.SET,
		vertical: bool = false) -> void:
	var m := MotionKeyframe.new()
	m.frame = frame
	m.velocity = velocity
	m.mode = mode
	m.affects_vertical = vertical
	m.dampen_factor = 0.35
	a.motion.append(m)


## Bind every attack to a clip.
##
## HONEST STATE OF THE ASSET SET: the free tier of the Universal Animation
## Library contains NO KICK ANIMATIONS AT ALL. Kick is half this game's input
## language (J), so all eight kick-family attacks are mapped to `Sword_Attack`
## — a big committed arm swing — purely so they have readable motion instead of
## a frozen bind pose. They are flagged as placeholders and counted in the
## report, because a known gap that is measured is manageable and one that is
## forgotten is not.
func _bind_animations() -> void:
	# --- punches: genuinely matching motion ---
	_anim(_attacks[&"jab_1"], CLIP_JAB)
	_anim(_attacks[&"jab_2"], CLIP_CROSS)
	_anim(_attacks[&"straight"], CLIP_CROSS, false, 0.95)
	_anim(_attacks[&"air_punch"], CLIP_JAB)
	_anim(_attacks[&"dash_punch"], CLIP_CROSS)
	_anim(_attacks[&"counter_palm"], CLIP_JAB)
	# A forward thrust reads convincingly as a lunging palm.
	_anim(_attacks[&"lunge_punch"], CLIP_THRUST)

	# --- placeholders: no matching motion exists in the free set ---
	# An uppercut is a rising strike; a jab is not. Marked as wrong.
	_anim(_attacks[&"uppercut"], CLIP_SWING, true, 0.95)
	for kick_id: StringName in [&"low_kick", &"roundhouse", &"axe_kick",
			&"spin_kick", &"sweep", &"air_kick", &"dive_kick", &"dash_kick"]:
		_anim(_attacks[kick_id], CLIP_SWING, true)


func _build_library() -> void:
	_bind_animations()

	_library = AttackLibrary.new()
	_library.id = &"player_base"
	_library.display_name = "Player — base Taijutsu"
	for id: StringName in _attacks:
		var attack: AttackData = _attacks[id]
		_save(attack, ATTACK_DIR + "%s.tres" % id)
		_library.attacks.append(attack)
	_save(_library, DATA_DIR + "attacks/player_base_library.tres")


# --- the route graph -------------------------------------------------------

func _build_graph() -> void:
	_graph = ComboGraph.new()
	_graph.id = &"player_base"
	_graph.display_name = "Player — base routes"

	# --- entries from neutral ---
	_route(&"", &"jab_1", CombatAction.Id.PUNCH, 0,
		CombatTypes.Direction.NEUTRAL)
	_route(&"", &"low_kick", CombatAction.Id.KICK, 0,
		CombatTypes.Direction.NEUTRAL)
	# Command normals outrank the neutral version, so holding a direction
	# reliably gets the directional attack.
	_route(&"", &"lunge_punch", CombatAction.Id.PUNCH, 5,
		CombatTypes.Direction.FORWARD)
	_route(&"", &"sweep", CombatAction.Id.KICK, 5, CombatTypes.Direction.BACK)
	_route(&"", &"spin_kick", CombatAction.Id.KICK, 5,
		CombatTypes.Direction.FORWARD)
	_route(&"", &"uppercut", CombatAction.Id.PUNCH, 6,
		CombatTypes.Direction.BACK)

	# --- punch string ---
	_route(&"jab_1", &"jab_2", CombatAction.Id.PUNCH)
	_route(&"jab_2", &"straight", CombatAction.Id.PUNCH)
	# Cross-string: the punch string can divert into kicks, which is what makes
	# the move set a graph rather than two parallel ladders.
	_route(&"jab_1", &"low_kick", CombatAction.Id.KICK)
	_route(&"jab_2", &"spin_kick", CombatAction.Id.KICK)
	_route(&"straight", &"axe_kick", CombatAction.Id.KICK, 2)

	# --- kick string ---
	_route(&"low_kick", &"roundhouse", CombatAction.Id.KICK)
	_route(&"low_kick", &"jab_1", CombatAction.Id.PUNCH)
	_route(&"roundhouse", &"axe_kick", CombatAction.Id.KICK, 2)
	_route(&"spin_kick", &"roundhouse", CombatAction.Id.KICK)
	_route(&"spin_kick", &"straight", CombatAction.Id.PUNCH)

	# --- into the launcher ---
	# Reachable from either string, so air combat is not gated behind one route.
	var from_jab2 := _route(&"jab_2", &"uppercut", CombatAction.Id.PUNCH, 4,
		CombatTypes.Direction.BACK)
	from_jab2.require_contact = CombatTypes.ContactRequirement.ON_HIT
	var from_low := _route(&"low_kick", &"uppercut", CombatAction.Id.PUNCH, 4,
		CombatTypes.Direction.BACK)
	from_low.require_contact = CombatTypes.ContactRequirement.ON_HIT

	# --- aerial routes ---
	_route(&"", &"air_punch", CombatAction.Id.PUNCH, 0,
		CombatTypes.Direction.ANY, CombatTypes.Stance.AIRBORNE)
	_route(&"", &"air_kick", CombatAction.Id.KICK, 0,
		CombatTypes.Direction.ANY, CombatTypes.Stance.AIRBORNE)
	_route(&"", &"dive_kick", CombatAction.Id.KICK, 5,
		CombatTypes.Direction.FORWARD, CombatTypes.Stance.AIRBORNE)
	_route(&"air_punch", &"air_kick", CombatAction.Id.KICK, 0,
		CombatTypes.Direction.ANY, CombatTypes.Stance.AIRBORNE)
	_route(&"air_punch", &"air_punch", CombatAction.Id.PUNCH, 0,
		CombatTypes.Direction.ANY, CombatTypes.Stance.AIRBORNE).max_combo_length = 6
	# The finisher: only against a launched target, which is what makes the air
	# route a consequence of the launcher rather than a free option.
	var finisher := _route(&"air_kick", &"dive_kick", CombatAction.Id.KICK, 3,
		CombatTypes.Direction.ANY, CombatTypes.Stance.AIRBORNE)
	finisher.require_target_state = CombatTypes.TargetState.LAUNCHED

	# --- dash attacks ---
	# Gated on dash RECENCY, not on an attack-relative frame window: these launch
	# from neutral, where there is no attack to be relative to, so a frame window
	# reads as frame 0 and would fire on EVERY press. 24 frames is comfortably
	# longer than the 11-frame dash, so the attack is live during it and just after.
	_route(&"", &"dash_punch", CombatAction.Id.PUNCH, 8,
		CombatTypes.Direction.ANY).max_frames_since_dash = 24
	_route(&"", &"dash_kick", CombatAction.Id.KICK, 8,
		CombatTypes.Direction.ANY).max_frames_since_dash = 24

	_save(_graph, DATA_DIR + "combos/player_base_graph.tres")


func _route(from: StringName, to: StringName, action: CombatAction.Id,
		priority: int = 0,
		direction: CombatTypes.Direction = CombatTypes.Direction.ANY,
		stance: CombatTypes.Stance = CombatTypes.Stance.GROUNDED) -> ComboEdge:
	var e := ComboEdge.new()
	e.from = from
	e.to = to
	e.action = action
	e.priority = priority
	e.require_direction = direction
	e.require_stance = stance
	_graph.edges.append(e)
	return e


func _build_motion_profile() -> void:
	var p := MotionProfile.new()
	p.id = &"player"
	# Tuned for a precision action game: quick to top speed, quicker to stop.
	p.max_speed = 6.4
	p.strafe_speed = 4.4
	p.acceleration = 58.0
	p.deceleration = 82.0
	p.turn_deceleration = 130.0
	p.turn_speed = 960.0
	p.attack_turn_speed = 85.0
	p.jump_height = 2.0
	p.rise_gravity_scale = 0.82
	p.fall_gravity_scale = 1.42
	p.air_control = 0.74
	p.max_fall_speed = 34.0
	p.coyote_frames = 5
	p.jump_buffer_frames = 6
	p.dash_speed = 13.5
	p.dash_frames = 11
	p.dash_cooldown_frames = 14
	p.air_dashes = 1
	_save(p, ACTOR_DIR + "player_motion.tres")


# --- io and reporting ------------------------------------------------------

func _save(resource: Resource, path: String) -> void:
	var err: int = ResourceSaver.save(resource, path)
	if err != OK:
		printerr("FAILED to save %s (error %d)" % [path, err])
		return
	resource.take_over_path(path)
	_written += 1


func _report() -> void:
	print("")
	print(_library.describe_frame_data())
	print("")
	print(_graph.describe_routes())
	print("")

	var problems: PackedStringArray = _library.validate()
	problems.append_array(_graph.validate(_library.attack_ids()))

	var placeholders: PackedStringArray = []
	for attack: AttackData in _library.all_attacks():
		if attack.anim_is_placeholder:
			placeholders.append(str(attack.id))

	if not placeholders.is_empty():
		print("PLACEHOLDER ANIMATIONS: %d of %d attacks do not have matching "
			% [placeholders.size(), _library.count()]
			+ "motion in the current asset set.")
		print("  %s" % ", ".join(placeholders))
		print("  The free Universal Animation Library contains no kicks. These "
			+ "play a sword swing so they read as SOMETHING rather than a")
		print("  frozen pose. See docs/ASSET_LICENSES.md.")
		print("")

	if problems.is_empty():
		print("VALIDATION OK — %d attacks, %d routes, no problems."
			% [_library.count(), _graph.route_count()])
	else:
		print("VALIDATION FOUND %d PROBLEM(S):" % problems.size())
		for p: String in problems:
			print("  - %s" % p)
