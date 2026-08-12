extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-17C: authored course variety stress test")
	var golfer = _build_golfer()
	var cases := [
		{"label": "STRAIGHT_PAR4", "definition": _build_straight_par4(), "seed": 170301},
		{"label": "WATER_PAR3", "definition": _build_water_par3(), "seed": 170302},
		{"label": "RISK_REWARD_PAR5", "definition": _build_risk_reward_par5(), "seed": 170303}
	]

	var summaries: Array = []
	for case in cases:
		var definition = case["definition"]
		_assert_true(definition != null, "%s authored definition is valid" % case["label"])
		if definition == null:
			continue
		var simulation = DataDefinedAutonomousHole.new(definition, "back")
		var result: Dictionary = simulation.play_hole(golfer, int(case["seed"]))
		var summary := _summarize(case["label"], result)
		summaries.append(summary)
		_print_trace(case["label"], result.get("history", []))
		_assert_true(bool(result.get("finished", false)), "%s golfer holes out" % case["label"])
		_assert_true(not result.get("history", []).is_empty(), "%s produces shot history" % case["label"])
		_assert_true(_history_reaches_green(result.get("history", [])), "%s reaches authored green" % case["label"])
		_assert_true(_history_ends_holed(result.get("history", [])), "%s ends HOLED" % case["label"])

	_assert_equal(summaries.size(), 3, "all three authored hole types execute")
	if summaries.size() == 3:
		_assert_equal(int(summaries[0]["par"]), 4, "straight hole retains par 4")
		_assert_equal(int(summaries[1]["par"]), 3, "water hole retains par 3")
		_assert_equal(int(summaries[2]["par"]), 5, "risk-reward hole retains par 5")
		_assert_true(int(summaries[1]["hazard_exposed_shots"]) > 0, "water par 3 exposes hazard-aware candidate evaluation")
		_assert_true(int(summaries[2]["hazard_exposed_shots"]) > 0, "risk-reward par 5 exposes hazard-aware candidate evaluation")
		_assert_true(_distinct_opening_plans(summaries), "varied geometry produces distinct opening club/target plans")

	golfer.free()
	_finish()


func _build_straight_par4():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc17_variety", 1, "Straight Away", 4, 410.0)
	author.add_tee("back", "Back", Vector3(0, 0, 410), 410.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-18, -16, 18, 16))
	author.add_surface_region("fairway", "Fairway", "FAIRWAY", _rect(-32, 28, 32, 390))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 400, 10, 420))
	return author.build_definition()


func _build_water_par3():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc17_variety", 2, "Carry the Water", 3, 168.0)
	author.add_tee("back", "Back", Vector3(0, 0, 168), 168.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-20, -15, 20, 16))
	author.add_surface_region("approach_rough", "Approach Rough", "ROUGH", _rect(-42, 16, 42, 55))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 158, 10, 178))
	author.add_hazard("front_water", "Front Water", "WATER", _rect(-48, 55, 48, 118), 1, "lateral")
	return author.build_definition()


func _build_risk_reward_par5():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc17_variety", 3, "Split Decision", 5, 525.0)
	author.add_tee("back", "Back", Vector3(0, 0, 525), 525.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-22, -17, 22, 18))
	author.add_surface_region("left_fairway", "Left Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-58, 25), Vector2(-12, 25), Vector2(-8, 205), Vector2(-18, 360), Vector2(-45, 500), Vector2(-78, 500)
	]))
	author.add_surface_region("right_fairway", "Right Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(12, 25), Vector2(62, 25), Vector2(70, 205), Vector2(55, 365), Vector2(40, 500), Vector2(12, 500)
	]))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 515, 10, 535))
	author.add_hazard("center_lake", "Center Lake", "WATER", PackedVector2Array([
		Vector2(-16, 205), Vector2(18, 205), Vector2(24, 350), Vector2(-20, 350)
	]), 1, "lateral")
	return author.build_definition()


func _build_golfer() -> Node:
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.golfer_name = "POC17 Variety Golfer"
	golfer.driving = 78.0
	golfer.approach = 78.0
	golfer.short_game = 78.0
	golfer.putting = 78.0
	golfer.risk_tolerance = 35.0
	golfer.confidence = 72.0
	golfer.decision_variability = 0.0
	golfer.physical_power = 72.0
	golfer.mobility = 72.0
	golfer.coordination = 72.0
	golfer.endurance = 72.0
	return golfer


func _summarize(label: String, result: Dictionary) -> Dictionary:
	var history: Array = result.get("history", [])
	var first: Dictionary = history[0] if not history.is_empty() else {}
	var hazard_exposed := 0
	for shot in history:
		var candidates: Array = shot.get("strategy_candidates", [])
		for candidate in candidates:
			if int(candidate.get("corridor_hazard_count", 0)) > 0:
				hazard_exposed += 1
				break
	var summary := {
		"label": label,
		"finished": bool(result.get("finished", false)),
		"strokes": int(result.get("strokes", 0)),
		"par": int(result.get("par", 0)),
		"opening_club": str(first.get("club_name", first.get("option", ""))),
		"opening_target": first.get("target_position", Vector3.ZERO),
		"hazard_exposed_shots": hazard_exposed,
		"final_surface": str(result.get("final_surface", "UNKNOWN"))
	}
	print("VARIETY_SUMMARY %s finished=%s strokes=%d par=%d opening_club=%s hazard_exposed_shots=%d final_surface=%s" % [
		label,
		str(summary["finished"]),
		summary["strokes"],
		summary["par"],
		summary["opening_club"],
		summary["hazard_exposed_shots"],
		summary["final_surface"]
	])
	return summary


func _print_trace(label: String, history: Array) -> void:
	print("TRACE %s shot,surface_before,club,target_distance,landing_surface,remaining,outcome" % label)
	for shot in history:
		var start: Vector3 = shot.get("start_position", Vector3.ZERO)
		var target: Vector3 = shot.get("target_position", start)
		print("TRACE %s %d,%s,%s,%.2f,%s,%.2f,%s" % [
			label,
			int(shot.get("shot_number", 0)),
			str(shot.get("surface_before", "")),
			str(shot.get("club_name", shot.get("option", ""))),
			start.distance_to(target),
			str(shot.get("surface_after", "")),
			float(shot.get("remaining_after_shot", 0.0)),
			str(shot.get("outcome", ""))
		])


func _history_reaches_green(history: Array) -> bool:
	for shot in history:
		if str(shot.get("surface_after", "")).to_upper() == "GREEN":
			return true
	return false


func _history_ends_holed(history: Array) -> bool:
	return not history.is_empty() and str(history[-1].get("outcome", "")).to_upper() == "HOLED"


func _distinct_opening_plans(summaries: Array) -> bool:
	var signatures: Dictionary = {}
	for summary in summaries:
		var target: Vector3 = summary.get("opening_target", Vector3.ZERO)
		var signature := "%s|%.1f|%.1f" % [summary.get("opening_club", ""), target.x, target.z]
		signatures[signature] = true
	return signatures.size() >= 2


func _rect(left: float, near_z: float, right: float, far_z: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left, near_z), Vector2(right, near_z), Vector2(right, far_z), Vector2(left, far_z)
	])


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-17C AUTHORED COURSE VARIETY PASSED")
		quit(0)
	else:
		push_error("POC-17C AUTHORED COURSE VARIETY FAILED: %d" % failures)
		quit(1)
