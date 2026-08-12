extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const CourseContext = preload("res://simulation/course_context.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")

const MAX_SEEDS := 40
const PAR := 4
const PUTT := 3

var failures: int = 0


func _init() -> void:
	print("POC-16D: penalty scoring integration")
	var penalty_result: Dictionary = {}
	var penalty_seed: int = -1

	for seed_offset in range(MAX_SEEDS):
		var golfer := _build_aggressive_golfer()
		var simulation := AutonomousHole.new()
		simulation.bag.use_literal_yardages(true)
		simulation.option_generator.bag.use_literal_yardages(true)
		var result: Dictionary = simulation.play_hole(
			golfer,
			Vector3(0, 0, 410),
			Vector3.ZERO,
			_build_hazards(),
			PAR,
			166000 + seed_offset,
			_build_water_par4_context()
		)
		golfer.free()
		if _penalty_strokes_in_history(result.get("history", [])) > 0:
			penalty_result = result
			penalty_seed = 166000 + seed_offset
			break

	_assert_true(not penalty_result.is_empty(), "representative water hole produces at least one penalty case within diagnostic seed window")
	if not penalty_result.is_empty():
		_print_trace(penalty_result, penalty_seed)
		_validate_penalty_hole(penalty_result)

	if failures == 0:
		print("POC-16D PENALTY SCORING INTEGRATION PASSED")
		quit(0)
	else:
		push_error("POC-16D PENALTY SCORING INTEGRATION FAILED: %d" % failures)
		quit(1)


func _build_aggressive_golfer() -> Node:
	var golfer := GolferScript.new()
	golfer.profile = golfer.GolferProfile.WILD_BILL
	golfer.apply_profile()
	golfer.golfer_name = "POC-16D Aggressive Golfer"
	golfer.driving = 85.0
	golfer.approach = 80.0
	golfer.short_game = 75.0
	golfer.putting = 80.0
	golfer.risk_tolerance = 100.0
	golfer.confidence = 95.0
	golfer.decision_variability = 0.0
	golfer.physical_power = 75.0
	golfer.mobility = 72.0
	golfer.coordination = 78.0
	golfer.endurance = 72.0
	return golfer


func _build_water_par4_context() -> RefCounted:
	var context := CourseContext.new()
	context.explicit_hole_out_required = true
	context.add_zone("Fairway", CourseContext.Surface.FAIRWAY, Vector3(0, 0, 205), Vector2(24, 195))
	context.add_zone("Tee", CourseContext.Surface.TEE, Vector3(0, 0, 410), Vector2(10, 8))
	# Narrow creek crossing the likely aggressive tee-shot landing area. It is
	# deliberately narrow laterally so the existing lateral-relief rule can place
	# the golfer back in play instead of trapping the simulation in the hazard.
	context.add_zone("Creek", CourseContext.Surface.WATER, Vector3(0, 0, 180), Vector2(3, 18))
	context.add_zone("Green", CourseContext.Surface.GREEN, Vector3(0, 0, 0), Vector2(16, 14))
	return context


func _build_hazards() -> Array:
	return [{"type": "WATER", "position": Vector3(0, 0, 180), "radius": 6.0}]


func _penalty_strokes_in_history(history: Array) -> int:
	var total := 0
	for shot in history:
		total += int(shot.get("penalty_strokes", 0))
	return total


func _print_trace(result: Dictionary, seed_value: int) -> void:
	print("PENALTY_CASE seed=%d" % seed_value)
	print("shot,surface_before,option,club,outcome,penalty,surface_after,remaining_yards")
	for shot in result.get("history", []):
		print("%d,%s,%s,%s,%s,%d,%s,%.2f" % [
			int(shot.get("shot_number", 0)),
			str(shot.get("surface_before", "")),
			str(shot.get("option", "")),
			str(shot.get("club_name", "")),
			str(shot.get("outcome", "")),
			int(shot.get("penalty_strokes", 0)),
			str(shot.get("surface_after", "")),
			float(shot.get("remaining_after_shot", 0.0))
		])
	print("PENALTY_SUMMARY finished=%s strokes=%d penalties=%d final_surface=%s remaining=%.3f" % [
		str(result.get("finished", false)),
		int(result.get("strokes", 0)),
		_penalty_strokes_in_history(result.get("history", [])),
		str(result.get("final_surface", "")),
		float(result.get("remaining_distance", 0.0))
	])


func _validate_penalty_hole(result: Dictionary) -> void:
	var history: Array = result.get("history", [])
	var penalties := _penalty_strokes_in_history(history)
	var expected_strokes := history.size() + penalties
	var saw_water := false
	var saw_relief := false
	var saw_putt := false
	var final_holed_putt := false

	for shot in history:
		if str(shot.get("outcome", "")) == "WATER":
			saw_water = true
			var landing: Vector3 = shot.get("landing_position", Vector3.ZERO)
			var relief: Vector3 = shot.get("relief_position", landing)
			if relief.distance_to(landing) > 0.01:
				saw_relief = true
		if int(shot.get("shot_type", -1)) == PUTT:
			saw_putt = true

	if not history.is_empty():
		var last_shot: Dictionary = history.back()
		final_holed_putt = int(last_shot.get("shot_type", -1)) == PUTT and bool(last_shot.get("putting_holed", false))

	_assert_true(penalties >= 1, "water outcome contributes at least one penalty stroke")
	_assert_true(saw_water, "trace records a WATER outcome")
	_assert_true(saw_relief, "water penalty applies a distinct relief position")
	_assert_true(int(result.get("strokes", -1)) == expected_strokes, "final score equals played shots plus penalty strokes")
	_assert_true(bool(result.get("finished", false)), "golfer completes the hole after penalty")
	_assert_true(saw_putt, "post-penalty play reaches autonomous putting")
	_assert_true(final_holed_putt, "post-penalty hole ends with a holed putt")


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
