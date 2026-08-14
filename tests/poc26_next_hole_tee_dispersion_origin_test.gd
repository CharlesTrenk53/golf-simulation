extends SceneTree

const ParticipateLiveGroupPlayback = preload("res://scenes/participate_live_group_playback.gd")


class FakeCourse:
	func hole_by_number(_hole_number: int):
		return {}


class FakeCourseWorld:
	var course = FakeCourse.new()

	func world_position(_hole_number: int, course_position: Vector3) -> Vector3:
		return course_position


class FakeGroup:
	var group_id: String = "player_group"


class FakeGolferVisual:
	var course_position: Vector3 = Vector3.ZERO

	func place_at_ball(value: Vector3) -> void:
		course_position = value

	func observe_shot_result(_shot: Dictionary) -> bool:
		return true

	func move_to_resolved_ball(shot: Dictionary) -> void:
		course_position = shot.get("landing_position", course_position)


class FakeBallVisual:
	var visible: bool = false
	var is_flying: bool = false
	var has_relief: bool = false

	func present_shot(_shot: Dictionary, animate: bool) -> bool:
		is_flying = animate
		return true

	func set_flight_progress(value: float) -> void:
		if value >= 1.0:
			is_flying = false

	func apply_simulation_relief() -> void:
		pass


class FakeGroupVisual:
	extends Node
	var course_world = FakeCourseWorld.new()
	var group = FakeGroup.new()
	var member_visuals: Array = []
	var member_ball_visuals: Array = []
	var active_member_shots: Dictionary = {}
	var presented_shot_counts: Dictionary = {}

	func _init() -> void:
		member_visuals = [FakeGolferVisual.new(), FakeGolferVisual.new()]
		member_ball_visuals = [FakeBallVisual.new(), FakeBallVisual.new()]
		presented_shot_counts = {0: 0, 1: 0}

	func sync_from_authority() -> bool:
		return true

	func member_world_positions() -> Array:
		var positions: Array = []
		for visual in member_visuals:
			positions.append(visual.course_position)
		return positions

	func has_active_inter_hole_transition() -> bool:
		return false


var failures: int = 0
var playback = null
var group_visual = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-26E: next-hole tee dispersion starts from next tee")
	group_visual = FakeGroupVisual.new()
	get_root().add_child(group_visual)

	var previous_green_positions: Array = [
		Vector3(4.0, 0.0, 392.0),
		Vector3(6.0, 0.0, 392.0)
	]
	for index in range(group_visual.member_visuals.size()):
		group_visual.member_visuals[index].place_at_ball(previous_green_positions[index])

	playback = ParticipateLiveGroupPlayback.new()
	get_root().add_child(playback)
	_assert_true(playback.configure(group_visual, "player_group", 2), "next-hole playback configures while visual still sits on previous green")
	_assert_vector_array_near(playback.tee_rest_positions, previous_green_positions, 0.0001, "configuration initially snapshots previous-hole visual positions")

	# This mirrors the real runtime: the next-hole playback exists before the
	# presentation-only inter-hole walk has finished. Once that walk finishes, the
	# visible group is physically on the new tee before any tee shot can present.
	var next_tee_positions: Array = [
		Vector3(1.0, 0.0, 520.0),
		Vector3(3.0, 0.0, 520.0)
	]
	for index in range(group_visual.member_visuals.size()):
		group_visual.member_visuals[index].place_at_ball(next_tee_positions[index])

	var first_shot := {
		"type": "LIVE_SHOT",
		"group_id": "player_group",
		"hole_number": 2,
		"member_index": 0,
		"time_seconds": 1000.0,
		"shot": {
			"shot_number": 1,
			"start_position": Vector3(2.0, 0.0, 520.0),
			"target_position": Vector3(2.0, 0.0, 700.0),
			"landing_position": Vector3(8.0, 0.0, 708.0),
			"outcome": "SUCCESS"
		}
	}
	_assert_true(playback.enqueue_authoritative_shot(first_shot), "first next-hole tee shot queues")
	var presented: Dictionary = playback.present_next(false)
	_assert_true(not presented.is_empty(), "first next-hole tee shot presents after inter-hole walk")
	_assert_vector_array_near(playback.tee_rest_positions, next_tee_positions, 0.0001, "first tee presentation refreshes tee-rest formation from actual next tee")
	_assert_vector_near(group_visual.member_visuals[0].course_position, next_tee_positions[0], 0.0001, "golfer returns to next tee after first tee shot instead of previous green")

	print("POC26E_NEXT_HOLE_TEE_ORIGIN_SUMMARY previous=%s next=%s retained=%s" % [
		str(previous_green_positions[0]),
		str(next_tee_positions[0]),
		str(group_visual.member_visuals[0].course_position)
	])
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_vector_near(actual: Vector3, expected: Vector3, tolerance: float, label: String) -> void:
	if actual.distance_to(expected) <= tolerance:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _assert_vector_array_near(actual: Array, expected: Array, tolerance: float, label: String) -> void:
	if actual.size() != expected.size():
		failures += 1
		push_error("FAIL: %s (size actual=%d expected=%d)" % [label, actual.size(), expected.size()])
		return
	for index in range(actual.size()):
		if typeof(actual[index]) != TYPE_VECTOR3 or typeof(expected[index]) != TYPE_VECTOR3 or actual[index].distance_to(expected[index]) > tolerance:
			failures += 1
			push_error("FAIL: %s (index=%d actual=%s expected=%s)" % [label, index, str(actual[index]), str(expected[index])])
			return
	print("PASS: ", label)


func _finish() -> void:
	if playback != null and is_instance_valid(playback):
		playback.queue_free()
	if group_visual != null and is_instance_valid(group_visual):
		group_visual.queue_free()
	if failures == 0:
		print("POC-26E NEXT-HOLE TEE DISPERSION ORIGIN PASSED")
		quit(0)
	else:
		push_error("POC-26E NEXT-HOLE TEE DISPERSION ORIGIN FAILED: %d" % failures)
		quit(1)
