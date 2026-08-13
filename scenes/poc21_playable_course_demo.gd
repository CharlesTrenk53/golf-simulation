extends Node3D

# POC-21 interactive proof
# ------------------------
# Runs the existing authoritative autonomous round one shot at a time while
# projecting each resolved shot into the POC-21 renderer/ball/golfer visuals.

const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")
const GolferScript = preload("res://scenes/golfer.gd")
const PlayableCourseRuntime = preload("res://scenes/playable_course_runtime.gd")

@export var shot_pause_seconds: float = 0.55
@export var hole_pause_seconds: float = 1.0
@export var profile: GolferScript.GolferProfile = GolferScript.GolferProfile.WILD_BILL

var golfer = null
var runtime = null
var _running: bool = false

@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $UI/Margin/Status


func _ready() -> void:
	golfer = GolferScript.new()
	golfer.profile = profile
	golfer.apply_profile()
	add_child(golfer)

	var course = StrategicCourseFixture.new().build_course()
	if course == null:
		status_label.text = "Failed to build authored course"
		return

	runtime = PlayableCourseRuntime.new()
	runtime.name = "PlayableCourseRuntime"
	add_child(runtime)
	if not runtime.configure(course, golfer, "back", 6100):
		status_label.text = "Failed to configure playable course"
		return

	_frame_active_hole()
	_update_status("Ready")
	_running = true
	_play_round_visible()


func _play_round_visible() -> void:
	while _running and runtime != null and runtime.authoritative_round != null and not runtime.authoritative_round.round_state.complete:
		var hole_number: int = runtime.active_hole_number
		_update_status("Hole %d — preparing" % hole_number)
		_frame_active_hole()
		await get_tree().create_timer(hole_pause_seconds).timeout

		var result: Dictionary = runtime.authoritative_round.play_current_hole(golfer, runtime.seed_value + hole_number - 1)
		if result.is_empty() or not bool(result.get("recorded", false)):
			_update_status("Stopped on unfinished Hole %d" % hole_number)
			_running = false
			return

		var history: Array = result.get("history", [])
		for shot_value in history:
			var shot: Dictionary = shot_value
			_update_status("Hole %d — Shot %d — %s" % [hole_number, int(shot.get("shot_number", 0)), str(shot.get("club_name", shot.get("option", "Shot")))])
			runtime.golfer_visual.observe_shot_result(shot)
			runtime.ball_visual.present_shot(shot, true)
			await runtime.ball_visual.flight_finished
			_apply_resolved_post_shot_position(shot)
			_frame_shot(shot)
			await get_tree().create_timer(shot_pause_seconds).timeout

		_capture_presented_hole(result)
		if not runtime.authoritative_round.round_state.complete:
			runtime._prepare_current_hole_visual()

	var final: Dictionary = runtime.runtime_snapshot()
	_update_status("Round complete — %d (%+d)" % [int(final.get("total_strokes", 0)), int(final.get("score_to_par", 0))])


func _apply_resolved_post_shot_position(shot: Dictionary) -> void:
	if runtime.ball_visual.has_relief:
		runtime.ball_visual.apply_simulation_relief()
	runtime.golfer_visual.move_to_resolved_ball(shot)


func _capture_presented_hole(result: Dictionary) -> void:
	var history: Array = result.get("history", [])
	runtime.presented_holes.append({
		"hole_number": int(result.get("hole_number", runtime.active_hole_number)),
		"hole_name": str(result.get("hole_name", "")),
		"par": int(result.get("par", 0)),
		"strokes": int(result.get("strokes", 0)),
		"finished": bool(result.get("finished", false)),
		"recorded": bool(result.get("recorded", false)),
		"shots_presented": history.size(),
		"simulation_shots": history.size(),
		"final_position": result.get("final_position", Vector3.ZERO),
		"visual_ball_position": runtime.ball_visual.course_position,
		"visual_golfer_position": runtime.golfer_visual.course_position
	}.duplicate(true))


func _frame_active_hole() -> void:
	if runtime == null or runtime.authoritative_round == null or runtime.authoritative_round.round_state == null:
		return
	var hole = runtime.authoritative_round.round_state.current_hole()
	if hole == null:
		return
	var tee: Vector3 = hole.tee_position(runtime.tee_id)
	var pin: Vector3 = hole.pin_position
	var center: Vector3 = (tee + pin) * 0.5
	var length: float = max(120.0, tee.distance_to(pin))
	camera.position = Vector3(center.x + length * 0.52, max(95.0, length * 0.36), center.z + length * 0.08)
	camera.look_at(center, Vector3.UP)


func _frame_shot(shot: Dictionary) -> void:
	var start: Vector3 = shot.get("start_position", Vector3.ZERO)
	var landing: Vector3 = shot.get("relief_position", shot.get("landing_position", Vector3.ZERO))
	var center: Vector3 = (start + landing) * 0.5
	var distance: float = max(40.0, start.distance_to(landing))
	camera.position = Vector3(center.x + distance * 0.45, max(35.0, distance * 0.28), center.z + distance * 0.12)
	camera.look_at(center, Vector3.UP)


func _update_status(message: String) -> void:
	if runtime == null or runtime.authoritative_round == null or runtime.authoritative_round.round_state == null:
		status_label.text = message
		return
	var state = runtime.authoritative_round.round_state
	status_label.text = "%s\n%s | Hole %d | %d holes complete | %d strokes | %+d" % [
		message,
		str(golfer.golfer_name),
		int(runtime.active_hole_number),
		int(state.holes_completed()),
		int(state.total_strokes()),
		int(state.score_to_par())
	]
