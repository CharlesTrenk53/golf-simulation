extends RefCounted

# POC-12C: Autonomous Round
# -------------------------
# Orchestrates independently playable data-defined holes through RoundState.
# The same golfer instance is supplied for every hole; this object owns course
# progression, not golfer identity or shot logic.

const RoundState = preload("res://simulation/round_state.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var course = null
var tee_id: String = "default"
var round_state = null
var hole_results: Array = []


func _init(course_definition = null, selected_tee_id: String = "default") -> void:
	course = course_definition
	tee_id = selected_tee_id
	round_state = RoundState.new(course_definition, selected_tee_id)


func restore_snapshot(saved: Dictionary) -> bool:
	if round_state == null or not round_state.restore_snapshot(saved):
		return false
	var saved_results: Array = saved.get("hole_results", [])
	if saved_results.size() < round_state.holes_completed():
		return false
	hole_results = saved_results.duplicate(true)
	return true


func play_current_hole(golfer: Node, seed_value: int = 1) -> Dictionary:
	if golfer == null or round_state == null or round_state.complete:
		return {}
	var hole = round_state.current_hole()
	if hole == null:
		return {}

	var playable = DataDefinedAutonomousHole.new(hole, tee_id)
	var result: Dictionary = playable.play_hole(golfer, seed_value)
	result["hole_number"] = int(hole.hole_number)
	result["hole_name"] = str(hole.hole_name)
	result["tee_id"] = tee_id
	result["recorded"] = false

	# A safety stroke limit is not a golf-hole completion. Only a genuinely
	# holed-out result can advance RoundState.
	if bool(result.get("finished", false)):
		result["recorded"] = round_state.record_current_hole(int(result.get("strokes", 0)))

	hole_results.append(result.duplicate(true))
	return result


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
	state_snapshot["round_finished"] = bool(state_snapshot.get("complete", false))
	state_snapshot["stopped_on_unfinished_hole"] = (
		not bool(state_snapshot.get("complete", false))
		and not hole_results.is_empty()
		and not bool(hole_results[-1].get("finished", false))
	)
	return state_snapshot
