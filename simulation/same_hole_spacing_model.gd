extends RefCounted

# POC-24E / POC-25D: Same-Hole Spacing Model
# -------------------------------------------
# Derives a lead group's tee clearance from authoritative resolved shot
# positions and compares that clearance with the following group's credible tee
# reach. POC-25D replaces the old numbered-shot-wave assumption with the real
# group order of play: the golfer farthest from the pin plays next.

const GolfBag = preload("res://simulation/golf_bag.gd")
const GroupPaceModel = preload("res://simulation/group_pace_model.gd")
const GroupShotOrderModel = preload("res://simulation/group_shot_order_model.gd")

var bag = GolfBag.new()
var pace_model = GroupPaceModel.new()
var shot_order_model = GroupShotOrderModel.new()

func _init() -> void:
	bag.use_literal_yardages(true)

func maximum_tee_reach(golfers: Array) -> float:
	if golfers.is_empty():
		return 0.0
	var driver: Dictionary = bag.get_club("DRIVER")
	if driver.is_empty():
		return 0.0
	var reach: float = 0.0
	for golfer in golfers:
		if golfer == null:
			continue
		var carry: float = bag.effective_carry(driver, golfer, "TEE", 1.0)
		var dispersion: float = bag.effective_dispersion(driver, golfer, "TEE", 1.0)
		reach = max(reach, carry + dispersion)
	return reach

func build_clearance_timeline(group_result: Dictionary, hole_definition, tee_id: String = "default") -> Array:
	if group_result.is_empty() or hole_definition == null:
		return []
	var member_results: Array = group_result.get("member_results", [])
	if member_results.is_empty() or pace_model.walking_yards_per_second <= 0.0:
		return []

	var order: Array = shot_order_model.build_order(group_result, hole_definition, tee_id)
	if order.is_empty():
		return []

	var tee: Vector3 = hole_definition.tee_position(tee_id)
	var positions: Array = []
	for _member in member_results:
		positions.append(tee)

	var timeline: Array = []
	var cumulative_shots: int = 0
	var cumulative_penalties: int = 0
	var previous_elapsed: float = 0.0
	for ordered_value in order:
		if typeof(ordered_value) != TYPE_DICTIONARY:
			continue
		var ordered: Dictionary = ordered_value
		var member_index: int = int(ordered.get("member_index", -1))
		if member_index < 0 or member_index >= positions.size():
			continue
		var resolved_position = ordered.get("resolved_position", positions[member_index])
		if typeof(resolved_position) == TYPE_VECTOR3:
			positions[member_index] = resolved_position
		cumulative_shots += 1
		cumulative_penalties += max(0, int(ordered.get("penalty_strokes", 0)))

		var clearance_yards: float = INF
		for position_value in positions:
			if typeof(position_value) == TYPE_VECTOR3:
				clearance_yards = min(clearance_yards, tee.distance_to(position_value))
		if clearance_yards == INF:
			clearance_yards = 0.0

		var elapsed: float = (
			float(cumulative_shots) * pace_model.shot_routine_seconds
			+ clearance_yards / pace_model.walking_yards_per_second
			+ float(cumulative_penalties) * pace_model.penalty_recovery_seconds
		)
		elapsed = max(previous_elapsed, elapsed)
		previous_elapsed = elapsed
		timeline.append({
			"sequence_index": int(ordered.get("sequence_index", timeline.size())),
			"member_index": member_index,
			"shot_index": int(ordered.get("shot_index", 0)),
			# Compatibility: existing POC-24 consumers call this shot_wave. It now
			# means the selected golfer's authoritative shot number at this milestone.
			"shot_wave": int(ordered.get("shot_number", int(ordered.get("shot_index", 0)) + 1)),
			"shot_number": int(ordered.get("shot_number", int(ordered.get("shot_index", 0)) + 1)),
			"elapsed_seconds": elapsed,
			"clearance_yards": clearance_yards,
			"cumulative_shots": cumulative_shots,
			"cumulative_penalties": cumulative_penalties,
			"distance_to_hole_yards": float(ordered.get("distance_to_hole_yards", 0.0))
		})
	return timeline

func earliest_safe_tee_time(group_result: Dictionary, hole_definition, following_golfers: Array, tee_id: String = "default") -> Dictionary:
	var credible_reach: float = maximum_tee_reach(following_golfers)
	var timeline: Array = build_clearance_timeline(group_result, hole_definition, tee_id)
	if credible_reach <= 0.0 or timeline.is_empty():
		return {"safe": false, "status": "INVALID", "credible_reach_yards": credible_reach}

	for index in range(timeline.size()):
		var remains_safe: bool = true
		for later_index in range(index, timeline.size()):
			if float(timeline[later_index].get("clearance_yards", 0.0)) <= credible_reach:
				remains_safe = false
				break
		if remains_safe:
			var milestone: Dictionary = timeline[index]
			return {
				"safe": true,
				"status": "SAFE_SAME_HOLE",
				"credible_reach_yards": credible_reach,
				"safe_time_seconds": float(milestone.get("elapsed_seconds", 0.0)),
				"safe_clearance_yards": float(milestone.get("clearance_yards", 0.0)),
				"shot_wave": int(milestone.get("shot_wave", 0)),
				"sequence_index": int(milestone.get("sequence_index", -1)),
				"member_index": int(milestone.get("member_index", -1)),
				"timeline": timeline.duplicate(true)
			}

	return {
		"safe": false,
		"status": "WAIT_FOR_HOLE_CLEAR",
		"credible_reach_yards": credible_reach,
		"timeline": timeline.duplicate(true)
	}
