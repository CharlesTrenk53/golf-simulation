extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

var created_golfers: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27C DIAGNOSTIC: first live clock advance")
	var course = POC27Course.build()
	if course == null:
		push_error("DIAG FAIL: course did not build")
		quit(1)
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	if not runtime.configure(course):
		push_error("DIAG FAIL: runtime did not configure")
		quit(1)
		return

	var golfers: Array = []
	var profiles := [
		Golfer.GolferProfile.CAREFUL_CARL,
		Golfer.GolferProfile.WILD_BILL,
		Golfer.GolferProfile.RECKLESS_RICK,
		Golfer.GolferProfile.CAREFUL_CARL
	]
	for profile in profiles:
		golfers.append(_new_golfer(int(profile)))

	if not runtime.add_group("group_1", golfers, "default", -1, 27000):
		push_error("DIAG FAIL: group did not join")
		quit(1)
		return
	var opening: Dictionary = runtime.release_next_group()
	if not bool(opening.get("released", false)):
		push_error("DIAG FAIL: group did not release")
		quit(1)
		return

	print("DIAG BEFORE 29s time=%.1f events=%d live_sessions=%d" % [runtime.current_time_seconds, runtime.event_history.size(), runtime.live_sessions.size()])
	var before_due: Array = runtime.advance_time(29.0)
	print("DIAG AFTER 29s time=%.1f processed=%d events=%d" % [runtime.current_time_seconds, before_due.size(), runtime.event_history.size()])

	print("DIAG BEFORE FIRST DUE SHOT time=%.1f" % runtime.current_time_seconds)
	var first_due: Array = runtime.advance_time(1.1)
	print("DIAG AFTER FIRST DUE SHOT time=%.1f processed=%d events=%d" % [runtime.current_time_seconds, first_due.size(), runtime.event_history.size()])

	var session = runtime.live_sessions.get("group_1", null)
	if session == null:
		push_error("DIAG FAIL: live session disappeared after first shot")
		_cleanup_and_quit(1)
		return
	if session.has_failed():
		var snapshot: Dictionary = session.snapshot()
		push_error("DIAG FAIL: first live turn failed reason=%s member=%d" % [str(snapshot.get("failure_reason", "")), int(snapshot.get("failed_member_index", -1))])
		_cleanup_and_quit(1)
		return

	var shot_events: int = 0
	for event_value in runtime.event_history:
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == "LIVE_SHOT":
			shot_events += 1
	if shot_events != 1:
		push_error("DIAG FAIL: expected exactly one live shot, got %d" % shot_events)
		_cleanup_and_quit(1)
		return

	print("POC27C_FIRST_CLOCK_DIAG_SUMMARY time=%.1f live_shots=%d" % [runtime.current_time_seconds, shot_events])
	print("POC-27C FIRST LIVE CLOCK DIAGNOSTIC PASSED")
	_cleanup_and_quit(0)


func _new_golfer(profile: int):
	var golfer = QuietGolfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_golfers.append(golfer)
	return golfer


func _cleanup_and_quit(code: int) -> void:
	for golfer in created_golfers:
		if golfer != null and is_instance_valid(golfer):
			golfer.queue_free()
	quit(code)
