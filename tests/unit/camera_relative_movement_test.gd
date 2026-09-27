extends TestCase

## Camera-relative movement direction.
##
## These encode the most basic contract the controls have: W goes the way the
## camera is looking, D goes to the screen's right. Getting it wrong makes the
## game unplayable, and it silently breaks dash, jump and every directional
## combo route too, because all of them read this same vector.
##
## Tested against `camera_relative_direction`, which takes a Basis rather than a
## camera node. That is deliberate: a `Node3D` parented to a headless root
## reports an IDENTITY global transform, so an earlier version of this suite
## built a real Camera3D, rotated it, measured nothing, and reported a failure
## that was purely an artefact of the test. A pure function has no such trap.


## A camera basis yawed `degrees` about Y. 0 looks down world -Z.
func _basis(degrees: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(degrees))


func test_forward_goes_where_the_camera_looks() -> void:
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(0.0, 1.0), _basis(0.0))
	assert_almost_eq(direction.z, -1.0, 0.01,
		"W must move AWAY from the camera, along its view direction")
	assert_almost_eq(direction.x, 0.0, 0.01)


func test_back_moves_toward_the_camera() -> void:
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(0.0, -1.0), _basis(0.0))
	assert_almost_eq(direction.z, 1.0, 0.01, "S must move TOWARD the camera")


func test_right_goes_to_the_screens_right() -> void:
	# Looking down -Z, the screen's right is world +X.
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(1.0, 0.0), _basis(0.0))
	assert_almost_eq(direction.x, 1.0, 0.01,
		"D must move to the RIGHT of the screen")


func test_left_goes_to_the_screens_left() -> void:
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(-1.0, 0.0), _basis(0.0))
	assert_almost_eq(direction.x, -1.0, 0.01,
		"A must move to the LEFT of the screen")


func test_movement_follows_a_rotated_camera() -> void:
	# The whole point of camera-relative movement: W is always "away from the
	# viewer", whichever way the viewer happens to be facing.
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(0.0, 1.0), _basis(180.0))
	assert_almost_eq(direction.z, 1.0, 0.01,
		"with the camera turned around, W must move the other way in world "
			+ "space")


func test_strafe_follows_a_rotated_camera() -> void:
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(1.0, 0.0), _basis(90.0))
	# Yawed +90 about Y, the camera's +X points toward world -Z.
	assert_almost_eq(direction.z, -1.0, 0.01,
		"D must stay the screen's right after the camera turns")


func test_camera_pitch_does_not_affect_ground_movement() -> void:
	var pitched := Basis(Vector3.RIGHT, deg_to_rad(-60.0))
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(0.0, 1.0), pitched)
	assert_almost_eq(direction.y, 0.0, 0.01,
		"ground movement must stay flat regardless of camera pitch")
	assert_almost_eq(direction.length(), 1.0, 0.01,
		"and must not lose magnitude to the pitch")
	assert_almost_eq(direction.z, -1.0, 0.01,
		"a downward-pitched camera still looks down -Z horizontally")


func test_looking_straight_down_still_produces_movement() -> void:
	# Degenerate case: the view direction has no horizontal component left.
	# Returning zero here would make the player freeze whenever the camera
	# reached its pitch limit.
	var straight_down := Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(0.0, 1.0), straight_down)
	assert_almost_eq(direction.length(), 1.0, 0.01,
		"movement must not stall when the camera looks straight down")


func test_diagonal_is_normalised() -> void:
	var direction: Vector3 = PlayerIntentSource.camera_relative_direction(
		Vector2(1.0, 1.0), _basis(0.0))
	assert_almost_eq(direction.length(), 1.0, 0.01,
		"diagonal movement must not be faster than cardinal movement")
