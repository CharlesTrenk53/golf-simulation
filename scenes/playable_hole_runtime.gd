extends Node3D

# POC-21D: One Complete Visible Hole
# -----------------------------------
# Runtime orchestration layer connecting the existing authoritative autonomous
# hole simulation to the POC-21 visual projections. HoleDefinition, course state,
# strategy, execution, penalties, relief, and scoring remain owned by simulation
# code. This node only sequences those results into visible course/ball/golfer
# state so the same golfer logic can be watched playing a real rendered hole.

const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")
const AuthoredHoleRenderer = preload("res://scenes/authored_hole_renderer.gd")
const RuntimeBallVisual = preload("res://scenes/runtime_ball_visual.gd")
const RuntimeGolferVisual = preload("res://scenes/runtime_golfer_visual.gd")

var hole_definition = null
var golfer = null
var tee_id: String = "default"
var seed_value: int = 1
var playable = null
var state = null
var renderer = null
var ball_visual = null
var golfer_visual = null
var presented_history: Array = []


func configure(definition, golfer_value, selected_tee_id: String = "default", seed: int = 1) -> bool:
	if definition == null or golfer_value == null or not definition.is_valid():
		return false

	clear_runtime()
	hole_definition = definition
	golfer = golfer_value
	tee_id = selected_tee_id
	seed_value = seed
	playable = DataDefinedAutonomousHole.new(definition, selected_tee_id)
	state = playable.create_state(seed)
	if state == null:
		return false

	renderer = AuthoredHoleRenderer.new()
	renderer.name = "CourseRenderer"
	add_child(renderer)
	if not renderer.render_hole(definition, selected_tee_id):
		return false

	ball_visual = RuntimeBallVisual.new()
	ball_visual.name = "BallVisual"
	add_child(ball_visual)
	ball_visual.place_at(state.ball_position)

	golfer_visual = RuntimeGolferVisual.new()
	golfer_visual.name = "GolferVisual"
	add_child(golfer_visual)
	if not golfer_visual.configure_golfer(golfer_value):
		return false
	golfer_visual.place_at_ball(state.ball_position)

	presented_history.clear()
	return true


func play_next_shot(animate: bool = false) -> Dictionary:
	if playable == null or state == null or golfer == null or not state.can_continue():
		return {}

	var result: Dictionary = playable.play_step(golfer, state)
	if result.is_empty():
		return {}

	golfer_visual.observe_shot_result(result)
	ball_visual.present_shot(result, animate)
	if not animate:
		_apply_resolved_post_shot_position(result)

	presented_history.append(_presentation_snapshot(result))
	return result


func finish_visual_resolution(result: Dictionary) -> void:
	# Called after an animated flight completes. The landing point is shown first;
	# only then do simulation-resolved penalty/relief coordinates become the new lie.
	_apply_resolved_post_shot_position(result)


func play_to_completion(animate: bool = false) -> Dictionary:
	if state == null:
		return {}
	var last_result: Dictionary = {}
	while state.can_continue():
		last_result = play_next_shot(animate)
		if last_result.is_empty():
			break
		# Headless/diagnostic mode resolves immediately. Interactive animation is
		# intentionally one-shot-at-a-time so callers can wait for flight_finished.
		if animate:
			break

	return runtime_snapshot(last_result)


func runtime_snapshot(last_result: Dictionary = {}) -> Dictionary:
	if state == null:
		return {}
	return {
		"finished": state.finished,
		"strokes": state.strokes,
		"par": state.par,
		"score_to_par": state.strokes - state.par if state.finished else 0,
		"ball_position": state.ball_position,
		"visual_ball_position": ball_visual.course_position if ball_visual != null else Vector3.ZERO,
		"visual_golfer_position": golfer_visual.course_position if golfer_visual != null else Vector3.ZERO,
		"shots_presented": presented_history.size(),
		"presented_history": presented_history.duplicate(true),
		"simulation_history": playable.autonomous.shot_history.duplicate(true) if playable != null else [],
		"last_result": last_result.duplicate(true)
	}


func clear_runtime() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	playable = null
	state = null
	renderer = null
	ball_visual = null
	golfer_visual = null
	presented_history.clear()


func _apply_resolved_post_shot_position(result: Dictionary) -> void:
	if ball_visual == null or golfer_visual == null:
		return
	if ball_visual.has_relief:
		ball_visual.apply_simulation_relief()
	golfer_visual.move_to_resolved_ball(result)


func _presentation_snapshot(result: Dictionary) -> Dictionary:
	var resolved_position: Vector3 = result.get("landing_position", Vector3.ZERO)
	if str(result.get("outcome", "")).to_upper() == "WATER" and result.has("relief_position"):
		resolved_position = result.get("relief_position", resolved_position)
	return {
		"shot_number": int(result.get("shot_number", 0)),
		"start_position": result.get("start_position", Vector3.ZERO),
		"landing_position": result.get("landing_position", Vector3.ZERO),
		"resolved_position": resolved_position,
		"outcome": str(result.get("outcome", "")),
		"club_id": str(result.get("club_id", "")),
		"intent_signature": str(result.get("intent_signature", ""))
	}
