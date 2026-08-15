extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const STEP_SECONDS := 30.0
const MAX_ITERATIONS := 5000

var created_golfers: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("POC-27C DIAGNOSTIC: single foursome full 18-hole progression")
	var course = POC27Course.build()
	if course == null:
		push_error("DIAG FAIL: course did not build")
		quit(1)
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	if not runtime.configure(course):
		push_error("DIAG FAIL: controller did not configure")
		quit(1)
		return

	var golfers: Array = [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL),
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	]
	if not runtime.add_group("solo_group", golfers, "default", -1, 27100):
		push_error("DIAG FAIL: group did not join")
		quit(1)
		return

	var release: Dictionary = runtime.release_next_group()
	if not bool(release.get("released", false)):
		push_error("DIAG FAIL: group did not release")
		quit(1)
		return

	var group = runtime.living_course.population.group_by_id("solo_group")
	var last_hole: int = group.current_hole_number()
	print("DIAG START hole=%d time=%.1f" % [last_hole, runtime.current_time_seconds])

	var iterations := 0
	while iterations < MAX_ITERATIONS and group != null and str(group.status) != "FINISHED":
		iterations += 1
		if iterations <= 20 or iterations % 50 == 0:
			print("DIAG BEFORE advance iteration=%d time=%.1f hole=%d events=%d" % [iterations, runtime.current_time_seconds, group.current_hole_number(), runtime.event_history.size()])
		var processed: Array = runtime.advance_time(STEP_SECONDS)
		if iterations <= 20 or iterations % 50 == 0:
			print("DIAG AFTER advance iteration=%d time=%.1f hole=%d processed=%d events=%d" % [iterations, runtime.current_time_seconds, group.current_hole_number(), processed.size(), runtime.event_history.size()])

		var current_hole: int = group.current_hole_number()
		if current_hole != last_hole:
			print("DIAG HOLE CHANGE from=%d to=%d time=%.1f iteration=%d" % [last_hole, current_hole, runtime.current_time_seconds, iterations])
			last_hole = current_hole

		if runtime.live_sessions.has("solo_group"):
			var session = runtime.live_sessions["solo_group"]
			if session != null and session.has_failed():
				var snap: Dictionary = session.snapshot()
				push_error("DIAG FAIL: live session failed hole=%d member=%d reason=%s" % [int(snap.get("hole_number", 0)), int(snap.get("failed_member_index", -1)), str(snap.get("failure_reason", ""))])
				_cleanup_and_quit(1)
				return

	if group == null:
		push_error("DIAG FAIL: group identity disappeared")
		_cleanup_and_quit(1)
		return
	if str(group.status) != "FINISHED":
		push_error("DIAG FAIL: bounded run ended before finish; hole=%d iterations=%d time=%.1f" % [group.current_hole_number(), iterations, runtime.current_time_seconds])
		_cleanup_and_quit(1)
		return

	var finish_events := 0
	var start_events := 0
	for event_value in runtime.event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "LIVE_HOLE_START":
			start_events += 1
		elif str(event.get("type", "")) == "LIVE_HOLE_FINISH":
			finish_events += 1

	print("POC27C_SINGLE_GROUP_DIAG_SUMMARY starts=%d finishes=%d time=%.1f iterations=%d events=%d" % [start_events, finish_events, runtime.current_time_seconds, iterations, runtime.event_history.size()])
	if start_events == 18 and finish_events == 18 and runtime.live_sessions.is_empty() and runtime.traffic.group_hole("solo_group") == 0:
		print("POC-27C SINGLE-GROUP FULL-ROUND DIAGNOSTIC PASSED")
		_cleanup_and_quit(0)
	else:
		push_error("DIAG FAIL: final authority cleanup mismatch")
		_cleanup_and_quit(1)

func _new_golfer(profile: int):
	var golfer = QuietGolfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_golfers.append(golfer)
	return golfer

func _cleanup_and_quit(exit_code: int) -> void:
	for golfer in created_golfers:
		if golfer != null and is_instance_valid(golfer):
			golfer.queue_free()
	quit(exit_code)
