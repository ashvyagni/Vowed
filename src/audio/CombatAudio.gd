extends Node

## Combat sound feedback. Autoload singleton: `CombatAudio`.
##
## Listens to `GameEvents` and never touches combat — combat resolves a hit and
## is finished; this is one of the observers that reacts
## (docs/ARCHITECTURE.md §2.1).
##
## WHY SOUND IS NOT DECORATION HERE
##
## The master directive is explicit: the player should be able to understand
## successful actions partly through SOUND. In practice audio is the fastest
## feedback channel a player has — faster to register than a visual flash — and
## it is how the difference between hitting, being blocked, and whiffing becomes
## legible without looking at any UI. A hit with no sound reads as a hit that
## did not land, however good the animation is.
##
## TWO RULES THAT MATTER MORE THAN THE SOUNDS THEMSELVES
##
## 1. VARIATION. A combo fires this several times per second. One sample
##    repeated is worse than silence — it turns a flurry into a machine-gun
##    artefact. Every category has several variants, and pitch is jittered on
##    top, so no two hits in a string are identical.
##
## 2. DISTINCTNESS. Hit, guard and parry must be instantly separable by ear
##    alone. They use different materials (flesh, plate, bell) rather than the
##    same sample at different volumes, because volume differences do not
##    survive a noisy mix.

const SOUND_DIR: String = "res://assets/audio/kenney_impact_sounds/"

## Simultaneous 3D voices. Beyond this the oldest is reused — a combo can
## trigger many overlapping impacts and running out mid-string would drop
## exactly the hits the player is listening for.
const VOICE_COUNT: int = 16

## Pitch jitter applied to every one-shot. Small enough to read as the same
## sound, large enough that repeats do not sound mechanical.
const PITCH_JITTER: float = 0.11

## Distance at which a sound is at full volume; beyond it, attenuation begins.
const UNIT_SIZE: float = 6.0

## Category -> loaded variants.
var _sets: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_sets()
	_build_voices()

	GameEvents.hit_landed.connect(_on_hit_landed)
	GameEvents.hit_guarded.connect(_on_hit_guarded)
	GameEvents.parry_succeeded.connect(_on_parry)
	GameEvents.attack_dodged.connect(_on_dodged)
	GameEvents.actor_staggered.connect(_on_staggered)
	GameEvents.actor_defeated.connect(_on_defeated)


## Load every `.ogg` in the sound directory, grouped by its category prefix
## (`impactPunch_medium_003.ogg` -> `impactPunch_medium`).
##
## Discovered rather than listed, so adding a variant file is enough to put it
## in rotation — content should not require a code change.
func _load_sets() -> void:
	var dir: DirAccess = DirAccess.open(SOUND_DIR)
	if dir == null:
		GameEvents.report_assertion("CombatAudio",
			"sound directory %s is missing; combat will be silent" % SOUND_DIR)
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		# Godot exports .ogg imports with a trailing .import in the editor; the
		# raw name is what load() wants.
		if entry.ends_with(".ogg"):
			var category: String = entry.get_basename()
			var underscore: int = category.rfind("_")
			if underscore > 0:
				category = category.substr(0, underscore)
			var stream: AudioStream = load(SOUND_DIR + entry) as AudioStream
			if stream != null:
				if not _sets.has(category):
					_sets[category] = [] as Array[AudioStream]
				(_sets[category] as Array[AudioStream]).append(stream)
		entry = dir.get_next()
	dir.list_dir_end()


func _build_voices() -> void:
	for i: int in VOICE_COUNT:
		var player := AudioStreamPlayer3D.new()
		player.bus = &"SFX"
		player.unit_size = UNIT_SIZE
		player.max_polyphony = 1
		# Combat sound should stay audible across the arena; realistic falloff
		# would make a fight two metres away inaudible, which costs the player
		# information they need.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_voices.append(player)


# --- events -----------------------------------------------------------------

func _on_hit_landed(_attacker: Node, _victim: Node, hit: HitResult) -> void:
	var heavy: bool = hit.reaction != null \
		and (hit.reaction.kind == CombatTypes.ReactionKind.HEAVY
			or CombatTypes.reaction_is_airborne(hit.reaction.kind)
			or hit.reaction.causes_knockdown)

	# A heavy hit layers a punch with a body impact, so weight is audible rather
	# than merely louder — loudness alone does not survive a busy mix.
	if heavy:
		play(&"impactPunch_heavy", hit.position, 0.0)
		play(&"impactSoft_heavy", hit.position, -4.0)
	else:
		play(&"impactPunch_medium", hit.position, -1.0)


func _on_hit_guarded(_attacker: Node, _victim: Node, hit: HitResult) -> void:
	# Metallic and bright: unmistakably NOT a clean hit, so a player knows they
	# were blocked without watching a health bar.
	play(&"impactMetal_light", hit.position, -2.0)


func _on_parry(_defender: Node, _attacker: Node, hit: HitResult) -> void:
	# The most distinctive sound in the game. A perfect parry is the highest-
	# skill defensive action and must be unmistakable the instant it lands.
	play(&"impactBell_heavy", hit.position, 1.0)


func _on_dodged(defender: Node, _attacker: Node) -> void:
	var node := defender as Node3D
	if node != null:
		play(&"impactGeneric_light", node.global_position, -9.0)


func _on_staggered(actor: Node) -> void:
	var node := actor as Node3D
	if node != null:
		play(&"impactSoft_heavy", node.global_position, -1.0)


func _on_defeated(actor: Node) -> void:
	var node := actor as Node3D
	if node != null:
		play(&"impactSoft_heavy", node.global_position, 0.0)


# --- playback ---------------------------------------------------------------

## Play a random variant of `category` at a world position.
## `volume_db` is relative; `pitch_scale` of 0 means "jitter automatically".
func play(category: StringName, position: Vector3, volume_db: float = 0.0,
		pitch_scale: float = 0.0) -> void:
	var variants: Array = _sets.get(String(category), [])
	if variants.is_empty():
		return

	var voice: AudioStreamPlayer3D = _acquire_voice()
	voice.stream = variants[_rng.randi_range(0, variants.size() - 1)]
	voice.global_position = position
	voice.volume_db = volume_db
	voice.pitch_scale = pitch_scale if pitch_scale > 0.0 \
		else _rng.randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	voice.play()


## Round-robin rather than "first free": reusing the oldest voice means a long
## combo degrades by dropping its oldest impact instead of refusing to play the
## newest one, and the newest is the one the player is listening for.
func _acquire_voice() -> AudioStreamPlayer3D:
	var voice: AudioStreamPlayer3D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return voice


## Categories loaded, for the debug overlay and the content validator.
func available_categories() -> Array[String]:
	var names: Array[String] = []
	for key: String in _sets:
		names.append("%s (%d)" % [key, (_sets[key] as Array).size()])
	names.sort()
	return names
