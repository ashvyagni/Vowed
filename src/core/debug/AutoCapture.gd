class_name AutoCapture
extends Node

## Headless-friendly screenshot capture, driven from the command line.
##
##     godot --path . -- --capture=90 --capture-out=/tmp/lab.png
##
## Waits the given number of rendered frames, writes a PNG, then quits.
##
## This exists so that "does it actually look right?" can be answered
## automatically rather than only by a human sitting in front of the window. That
## matters for a solo project in two ways: a visual regression can be caught in a
## verification pass, and a change made in one sitting can be checked without
## re-staging the whole scenario by hand.
##
## Inert unless `--capture=` is passed, so it costs nothing in normal play.

const DEFAULT_OUTPUT: String = "user://capture.png"

var _frames_remaining: int = -1
var _output_path: String = DEFAULT_OUTPUT
var _armed: bool = false


func _ready() -> void:
	_parse_args()
	if not _armed:
		# Nothing requested — remove self so no per-frame cost remains.
		queue_free()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_frames_remaining = maxi(1, int(arg.substr("--capture=".length())))
			_armed = true
		elif arg.begins_with("--capture-out="):
			_output_path = arg.substr("--capture-out=".length())


func _process(_delta: float) -> void:
	if not _armed:
		return
	_frames_remaining -= 1
	if _frames_remaining > 0:
		return
	_armed = false
	_capture()


func _capture() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		printerr("[capture] no viewport")
		get_tree().quit(1)
		return

	var image: Image = viewport.get_texture().get_image()
	if image == null:
		printerr("[capture] viewport produced no image (running headless?)")
		get_tree().quit(1)
		return

	var err: int = image.save_png(_output_path)
	if err != OK:
		printerr("[capture] failed to write %s (error %d)" % [_output_path, err])
		get_tree().quit(1)
		return

	print("[capture] wrote %s (%dx%d)" % [
		ProjectSettings.globalize_path(_output_path),
		image.get_width(), image.get_height()])
	get_tree().quit(0)
