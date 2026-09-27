# VOWED — generate the audio bus layout.
#
#     godot --headless --path . -s tools/generate_audio_buses.gd
#
# Buses exist from the start because retrofitting them is painful: every
# AudioStreamPlayer already in the project has to be revisited, and the settings
# menu's volume sliders have nothing to bind to until they exist. Creating them
# now costs nothing and makes the M16 accessibility work a wiring job rather
# than a refactor.
#
# Layout:
#   Master
#   ├── SFX       combat impacts, footsteps, world
#   ├── Music     adaptive music layers (M3+)
#   ├── Dialogue  voice (M6+) — separated because subtitle/volume accessibility
#   │             settings require dialogue to be independently adjustable
#   └── UI        menu and HUD feedback

extends SceneTree

const BUSES: Array[String] = ["SFX", "Music", "Dialogue", "UI"]


func _initialize() -> void:
	# Bus 0 is always Master and cannot be removed.
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)

	for bus_name: String in BUSES:
		var index: int = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")

	var layout: AudioBusLayout = AudioServer.generate_bus_layout()
	var err: int = ResourceSaver.save(layout, "res://default_bus_layout.tres")
	if err != OK:
		printerr("failed to save bus layout: %d" % err)
		quit(1)
		return

	print("Wrote default_bus_layout.tres with %d bus(es): Master, %s"
		% [AudioServer.bus_count, ", ".join(BUSES)])
	quit(0)
