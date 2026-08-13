extends Node3D

# POC-21E: Visible Multi-Hole Course
# ----------------------------------
# Visual projection of the authoritative AutonomousRound. AutonomousRound owns
# RoundState, round context/adaptation, hole simulation, scoring, and progression.
# This node renders the current authored hole and replays the already-resolved
# shot history without re-simulating or mutating golfer behavior a second time.

const AutonomousRound = preload("res://simulation/autonomous_round.gd")
const AuthoredHoleRenderer = preload("res://scenes/authored_hole_renderer.gd")
const RuntimeBallVisual = preload("res://scenes/runtime_ball_visual.gd")
const RuntimeGolferVisual = preload("res://scenes/runtime_golfer_visual.gd")

var course = null
var golfer = null
var tee_id: String = "default"
var seed_value: int = 1
var authoritative_round = null
var renderer = null
var ball_visual = null
var golfer_visual = null
var presented_holes: Array = []
var active_hole_number: int = 0


func configure(course_definition, golfer_value, selected_tee_id: String = "default", seed: int = 1) -> bool:
	if course_definition == null or golfer_value == null:
		return false

	clear_runtime()
	course = course_definition
	golfer = golfer_value
	tee_id = selected_tee_id
	seed_value = seed
	authoritative_round = AutonomousRound.new(course_definition, selected_tee_id)
	if authoritative_round.round_state == null or authoritative_round.round_state.complete:
		return false
	return _prepare_current_hole_visual()


func play_current_hole(animate: bool = false) -> Dictionary:
	if authoritative_round == null or authoritative_round.round_state == null:
		return {}
	if authoritative_round.round_state.complete:
		return {}

	var hole = authoritative_round.round_state.current_hole()
	if hole == null:
		return {}
	var hole_seed: int = seed_value + int(hole.hole_number) - 1
	var result: Dictionary = authoritative_round.play_current_hole(golfer, hole_seed)
	if result.is_empty():
		return {}

	var history: Array = result.get("history", [])
	var presented_shots: Array = []
	for shot_value in history:
		var shot: Dictionary = shot_value
		if not ball_visual.present_shot(shot, animate):
			continue
		golfer_visual.observe_shot_result(shot)
		if animate:
			# Interactive callers can later advance one flight at a time. POC-21E's
			# round-level contract is validated in immediate/headless presentation.
			ball_visual.set_flight_progress(1.0)
		if ball_visual.has_relief:
			ball_visual.apply_simulation_relief()
		golfer_visual.move_to_resolved_ball(shot)
		presented_shots.append(_shot_snapshot(shot))

	var hole_snapshot := {
		"hole_number": int(result.get("hole_number", hole.hole_number)),
		"hole_name": str(result.get("hole_name", hole.hole_name)),
		"par": int(result.get("par", hole.par)),
		"strokes": int(result.get("strokes", 0)),
		"finished": bool(result.get("finished", false)),
		"recorded": bool(result.get("recorded", false)),
		"shots_presented": presented_shots.size(),
		"simulation_shots": history.size(),
		"presented_shots": presented_shots,
		"final_position": result.get("final_position", Vector3.ZERO),
		"visual_ball_position": ball_visual.course_position,
		"visual_golfer_position": golfer_visual.course_position
	}
	presented_holes.append(hole_snapshot.duplicate(true))

	if bool(result.get("recorded", false)) and not authoritative_round.round_state.complete:
		_prepare_current_hole_visual()
	return hole_snapshot


func play_course(animate: bool = false) -> Dictionary:
	if authoritative_round == null:
		return {}
	while not authoritative_round.round_state.complete:
		var hole_result: Dictionary = play_current_hole(animate)
		if hole_result.is_empty() or not bool(hole_result.get("recorded", false)):
			break
	return runtime_snapshot()


func runtime_snapshot() -> Dictionary:
	if authoritative_round == null:
		return {}
	var round_snapshot: Dictionary = authoritative_round.snapshot()
	return {
		"round_finished": bool(round_snapshot.get("round_finished", false)),
		"holes_completed": authoritative_round.round_state.holes_completed(),
		"total_strokes": authoritative_round.round_state.total_strokes(),
		"par_played": authoritative_round.round_state.par_played(),
		"score_to_par": authoritative_round.round_state.score_to_par(),
		"scorecard": authoritative_round.round_state.scorecard(),
		"presented_holes": presented_holes.duplicate(true),
		"active_hole_number": active_hole_number,
		"authoritative_round": round_snapshot
	}


func clear_runtime() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	renderer = null
	ball_visual = null
	golfer_visual = null
	presented_holes.clear()
	active_hole_number = 0
	authoritative_round = null


func _prepare_current_hole_visual() -> bool:
	if authoritative_round == null or authoritative_round.round_state == null:
		return false
	var hole = authoritative_round.round_state.current_hole()
	if hole == null:
		return false

	for child in get_children():
		remove_child(child)
		child.queue_free()

	renderer = AuthoredHoleRenderer.new()
	renderer.name = "CourseRenderer"
	add_child(renderer)
	if not renderer.render_hole(hole, tee_id):
		return false

	ball_visual = RuntimeBallVisual.new()
	ball_visual.name = "BallVisual"
	add_child(ball_visual)
	ball_visual.place_at(hole.tee_position(tee_id))

	golfer_visual = RuntimeGolferVisual.new()
	golfer_visual.name = "GolferVisual"
	add_child(golfer_visual)
	if not golfer_visual.configure_golfer(golfer):
		return false
	golfer_visual.place_at_ball(hole.tee_position(tee_id))

	active_hole_number = int(hole.hole_number)
	return true


func _shot_snapshot(result: Dictionary) -> Dictionary:
	var resolved: Vector3 = result.get("landing_position", Vector3.ZERO)
	if str(result.get("outcome", "")).to_upper() == "WATER" and result.has("relief_position"):
		resolved = result.get("relief_position", resolved)
	return {
		"shot_number": int(result.get("shot_number", 0)),
		"start_position": result.get("start_position", Vector3.ZERO),
		"landing_position": result.get("landing_position", Vector3.ZERO),
		"resolved_position": resolved,
		"outcome": str(result.get("outcome", "")),
		"club_id": str(result.get("club_id", ""))
	}
