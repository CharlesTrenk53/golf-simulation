extends RefCounted

# POC-12C: Autonomous Round
# -------------------------
# Orchestrates independently playable data-defined holes through RoundState.
# The same golfer instance is supplied for every hole; this object owns course
# progression, not golfer identity or shot logic.
#
# POC-20C added a read-only round-context seam. POC-20D now derives bounded,
# transient behavior adjustments from those signals before each hole. Persistent
# golfer traits remain untouched.
#
# POC-26A opens the same authoritative hole pipeline at a one-shot-at-a-time
# seam. Whole-hole callers remain supported through play_current_hole(), which
# simply drives the incremental state until the hole attempt ends.

const RoundState = preload("res://simulation/round_state.gd")
const RoundContext = preload("res://simulation/round_context.gd")
const RoundAdaptationModel = preload("res://simulation/round_adaptation_model.gd")
const RoundBehaviorAdjustmentModel = preload("res://simulation/round_behavior_adjustment_model.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var course = null
var tee_id: String = "default"
var round_state = null
var hole_results: Array = []
var round_context_model = RoundContext.new()
var round_adaptation_model = RoundAdaptationModel.new()
var round_behavior_model = RoundBehaviorAdjustmentModel.new()

var active_playable = null
var active_hole_state = null
var active_hole_number: int = 0
var active_hole_name: String = ""
var active_pre_hole_context: Dictionary = {}
var active_pre_hole_adaptation: Dictionary = {}
var active_pre_hole_behavior: Dictionary = {}


func _init(course_definition = null, selected_tee_id: String = "default") -> void:
	course = course_definition
	tee_id = selected_tee_id
	round_state = RoundState.new(course_definition, selected_tee_id)


func restore_snapshot(saved: Dictionary) -> bool:
	_clear_active_hole()
	if round_state == null or not round_state.restore_snapshot(saved):
		return false
	var saved_results: Array = saved.get("hole_results", [])
	if saved_results.size() < round_state.holes_completed():
		return false
	hole_results = saved_results.duplicate(true)
	return true


func begin_current_hole(golfer: Node, seed_value: int = 1) -> Dictionary:
	if golfer == null or round_state == null or round_state.complete or has_active_hole():
		return {}
	var hole = round_state.current_hole()
	if hole == null:
		return {}

	active_pre_hole_context = round_context_model.build(round_state)
	active_pre_hole_adaptation = round_adaptation_model.interpret(golfer, active_pre_hole_context)
	active_pre_hole_behavior = round_behavior_model.build(golfer, active_pre_hole_adaptation)
	active_playable = DataDefinedAutonomousHole.new(hole, tee_id)
	active_playable.set_round_context(
		active_pre_hole_context,
		active_pre_hole_adaptation,
		active_pre_hole_behavior
	)
	active_hole_state = active_playable.create_state(seed_value)
	if active_hole_state == null:
		_clear_active_hole()
		return {}

	active_hole_number = int(hole.hole_number)
	active_hole_name = str(hole.hole_name)
	var started: Dictionary = active_hole_snapshot()
	started["begun"] = true
	return started


func has_active_hole() -> bool:
	return active_playable != null and active_hole_state != null


func active_hole_snapshot() -> Dictionary:
	if not has_active_hole():
		return {}
	return {
		"hole_number": active_hole_number,
		"hole_name": active_hole_name,
		"tee_id": tee_id,
		"strokes": int(active_hole_state.strokes),
		"ball_position": active_hole_state.ball_position,
		"remaining_distance": active_hole_state.remaining_distance(),
		"surface": active_hole_state.surface_name(),
		"finished": bool(active_hole_state.finished),
		"can_continue": bool(active_hole_state.can_continue())
	}


func play_current_hole_step(golfer: Node) -> Dictionary:
	if golfer == null or not has_active_hole() or not active_hole_state.can_continue():
		return {}

	var shot: Dictionary = active_playable.play_step(golfer, active_hole_state)
	if shot.is_empty():
		return {}

	var response := {
		"shot": shot.duplicate(true),
		"hole_ended": false,
		"recorded": false,
		"hole_result": {},
		"active_state": active_hole_snapshot()
	}

	if not active_hole_state.can_continue():
		var final_result: Dictionary = _finalize_active_hole_attempt()
		response["hole_ended"] = true
		response["recorded"] = bool(final_result.get("recorded", false))
		response["hole_result"] = final_result.duplicate(true)
		response["active_state"] = {}

	return response


func play_current_hole(golfer: Node, seed_value: int = 1) -> Dictionary:
	if not begin_current_hole(golfer, seed_value).get("begun", false):
		return {}

	var final_result: Dictionary = {}
	while has_active_hole():
		var step_result: Dictionary = play_current_hole_step(golfer)
		if step_result.is_empty():
			break
		if bool(step_result.get("hole_ended", false)):
			final_result = step_result.get("hole_result", {}).duplicate(true)

	return final_result


func play_round(golfer: Node, seed_value: int = 1) -> Dictionary:
	if golfer == null or round_state == null:
		return snapshot()

	while not round_state.complete:
		var hole = round_state.current_hole()
		if hole == null:
			break
		var hole_seed: int = seed_value + int(hole.hole_number) - 1
		var result: Dictionary = play_current_hole(golfer, hole_seed)
		if result.is_empty() or not bool(result.get("recorded", false)):
			break
	return snapshot()


func snapshot() -> Dictionary:
	var state_snapshot: Dictionary = round_state.snapshot() if round_state != null else {}
	state_snapshot["tee_id"] = tee_id
	state_snapshot["hole_results"] = hole_results.duplicate(true)
	state_snapshot["active_hole"] = active_hole_snapshot()
	state_snapshot["round_finished"] = bool(state_snapshot.get("complete", false))
	state_snapshot["stopped_on_unfinished_hole"] = (
		not bool(state_snapshot.get("complete", false))
		and not hole_results.is_empty()
		and not bool(hole_results[-1].get("finished", false))
	)
	return state_snapshot


func _finalize_active_hole_attempt() -> Dictionary:
	if not has_active_hole():
		return {}

	var result := {
		"finished": bool(active_hole_state.finished),
		"strokes": int(active_hole_state.strokes),
		"par": int(active_hole_state.par),
		"remaining_distance": active_hole_state.remaining_distance(),
		"final_position": active_hole_state.ball_position,
		"final_surface": active_hole_state.surface_name(),
		"history": active_playable.autonomous.shot_history.duplicate(true),
		"round_context": active_pre_hole_context.duplicate(true),
		"round_adaptation": active_pre_hole_adaptation.duplicate(true),
		"round_behavior": active_pre_hole_behavior.duplicate(true),
		"hole_number": active_hole_number,
		"hole_name": active_hole_name,
		"tee_id": tee_id,
		"recorded": false,
		"pre_hole_round_context": active_pre_hole_context.duplicate(true),
		"pre_hole_adaptation": active_pre_hole_adaptation.duplicate(true),
		"pre_hole_behavior": active_pre_hole_behavior.duplicate(true)
	}

	# A safety stroke limit is not a golf-hole completion. Only a genuinely
	# holed-out result can advance RoundState.
	if bool(result.get("finished", false)):
		result["recorded"] = round_state.record_current_hole(int(result.get("strokes", 0)))

	hole_results.append(result.duplicate(true))
	_clear_active_hole()
	return result


func _clear_active_hole() -> void:
	active_playable = null
	active_hole_state = null
	active_hole_number = 0
	active_hole_name = ""
	active_pre_hole_context.clear()
	active_pre_hole_adaptation.clear()
	active_pre_hole_behavior.clear()
