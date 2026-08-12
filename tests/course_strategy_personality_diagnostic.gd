extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0
var profile_choices: Dictionary = {}


func _init() -> void:
	print("POC-18F: personality risk-reward strategy diagnostic")
	var hole = _build_risk_reward_hole()
	_assert_true(hole != null, "risk-reward hole builds")
	if hole == null:
		_finish()
		return

	for profile in [
		GolferScript.GolferProfile.WILD_BILL,
		GolferScript.GolferProfile.RECKLESS_RICK,
		GolferScript.GolferProfile.CAREFUL_CARL
	]:
		_run_profile(hole, profile)

	var rick: Dictionary = profile_choices.get("Reckless Rick", {})
	var carl: Dictionary = profile_choices.get("Careful Carl", {})
	_assert_true(int(rick.get("aggressive_candidates", 0)) > 0, "Reckless Rick sees aggressive alternatives")
	_assert_true(int(rick.get("standard_candidates", 0)) > 0, "Reckless Rick sees bailout alternatives")
	_assert_true(int(carl.get("aggressive_candidates", 0)) > 0, "Careful Carl sees aggressive alternatives")
	_assert_true(int(carl.get("standard_candidates", 0)) > 0, "Careful Carl sees bailout alternatives")
	_assert_true(bool(rick.get("chosen_aggressive", false)), "Reckless Rick takes the close aggressive tradeoff")
	_assert_true(not bool(carl.get("chosen_aggressive", true)), "Careful Carl takes the safer bailout")

	_finish()


func _run_profile(hole, profile: int) -> void:
	var golfer = GolferScript.new()
	golfer.profile = profile
	golfer.apply_profile()
	var playable = DataDefinedAutonomousHole.new(hole, "back")
	var state = playable.create_state(181900 + profile)
	var selection: Dictionary = playable.choose_course_strategy(golfer, state)
	var chosen: Dictionary = selection.get("chosen", {})
	var evaluated: Array = selection.get("evaluated", [])

	_assert_true(not chosen.is_empty(), "%s receives a strategy choice" % golfer.golfer_name)
	var aggressive_candidates: int = 0
	var standard_candidates: int = 0
	for candidate in evaluated:
		if bool(candidate.get("is_aggressive", false)):
			aggressive_candidates += 1
		else:
			standard_candidates += 1

	_assert_true(standard_candidates > 0, "%s sees at least one playable standard alternative" % golfer.golfer_name)

	profile_choices[golfer.golfer_name] = {
		"chosen_aggressive": bool(chosen.get("is_aggressive", false)),
		"aggressive_candidates": aggressive_candidates,
		"standard_candidates": standard_candidates
	}

	print("STRATEGY_PROFILE,%s,risk_tolerance=%.0f,choice=%s,club=%s,target=%s,posture=%s,surface=%s,downside=%.3f,leave=%.1f,decision_expected=%.3f,aggressive_candidates=%d,standard_candidates=%d" % [
		golfer.golfer_name,
		float(golfer.risk_tolerance),
		str(chosen.get("name", "")),
		str(chosen.get("club_name", "")),
		str(chosen.get("target_variant", "")),
		str(chosen.get("strategy_posture", "")),
		str(chosen.get("expected_surface", "")),
		float(chosen.get("downside_exposure", 0.0)),
		float(chosen.get("remaining_after_target", 0.0)),
		float(chosen.get("decision_expected_strokes", 0.0)),
		aggressive_candidates,
		standard_candidates
	])

	var best_aggressive: Dictionary = {}
	var best_standard: Dictionary = {}
	for candidate in evaluated:
		if bool(candidate.get("is_aggressive", false)):
			if best_aggressive.is_empty() or float(candidate.get("decision_expected_strokes", INF)) < float(best_aggressive.get("decision_expected_strokes", INF)):
				best_aggressive = candidate
		else:
			if best_standard.is_empty() or float(candidate.get("decision_expected_strokes", INF)) < float(best_standard.get("decision_expected_strokes", INF)):
				best_standard = candidate
	_print_candidate(golfer.golfer_name, "BEST_AGGRESSIVE", best_aggressive)
	_print_candidate(golfer.golfer_name, "BEST_STANDARD", best_standard)
	_print_bailout_geometry(golfer.golfer_name, evaluated)
	golfer.free()


func _print_candidate(golfer_name: String, label: String, candidate: Dictionary) -> void:
	if candidate.is_empty():
		print("STRATEGY_CANDIDATE,%s,%s,NONE" % [golfer_name, label])
		return
	print("STRATEGY_CANDIDATE,%s,%s,club=%s,target=%s,posture=%s,surface=%s,downside=%.3f,leave=%.1f,perceived=%.3f,personality_adjustment=%+.3f,decision_expected=%.3f" % [
		golfer_name,
		label,
		str(candidate.get("club_name", "")),
		str(candidate.get("target_variant", "")),
		str(candidate.get("strategy_posture", "")),
		str(candidate.get("expected_surface", "")),
		float(candidate.get("downside_exposure", 0.0)),
		float(candidate.get("remaining_after_target", 0.0)),
		float(candidate.get("perceived_expected_strokes_to_hole", 0.0)),
		float(candidate.get("personality_risk_adjustment", 0.0)),
		float(candidate.get("decision_expected_strokes", 0.0))
	])


func _print_bailout_geometry(golfer_name: String, evaluated: Array) -> void:
	for candidate in evaluated:
		var club_id: String = str(candidate.get("club_id", ""))
		if club_id not in ["3_WOOD", "5_WOOD", "4_HYBRID"]:
			continue
		var target: Vector3 = candidate.get("target", Vector3.ZERO)
		print("STRATEGY_GEOMETRY,%s,club=%s,target=%s,x=%.1f,z=%.1f,surface=%s,posture=%s,downside=%.3f,leave=%.1f,decision_expected=%.3f" % [
			golfer_name,
			str(candidate.get("club_name", "")),
			str(candidate.get("target_variant", "")),
			target.x,
			target.z,
			str(candidate.get("expected_surface", "")),
			str(candidate.get("strategy_posture", "")),
			float(candidate.get("downside_exposure", 0.0)),
			float(candidate.get("remaining_after_target", 0.0)),
			float(candidate.get("decision_expected_strokes", 0.0))
		])


func _build_risk_reward_hole():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_personality", 1, "Temptation", 4, 430.0)
	author.add_tee("back", "Back", Vector3(0, 0, 430), 430.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-21, -16, 21, 18))

	# The bailout is a real fairway centered on the FAR_LEFT 5-wood / 4-hybrid
	# landing cluster for Rick and Carl (roughly x=-26, z=260-264). It gives up
	# meaningful position versus driver but stays well away from the water line.
	author.add_surface_region("bailout_fairway", "Bailout Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-34, 256), Vector2(-18, 256), Vector2(-18, 266), Vector2(-34, 266)
	]))
	# The attack fairway is intentionally narrow in both width and depth. Driver
	# CENTER reaches it while shorter central lines finish in rough.
	author.add_surface_region("attack_fairway", "Attack Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-10, 205), Vector2(10, 205), Vector2(10, 247), Vector2(-10, 247)
	]))
	author.add_surface_region("approach_fairway", "Approach Fairway", "FAIRWAY", _rect(-34, 24, 34, 205))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 420, 10, 440))

	# Water sits just inside the low-skill driver's dispersion corridor, so the
	# aggressive line buys position by accepting meaningful penalty exposure.
	author.add_hazard("decision_lake", "Decision Lake", "WATER", PackedVector2Array([
		Vector2(10.0, 205), Vector2(56, 205), Vector2(56, 275), Vector2(10.0, 275)
	]), 1, "lateral")

	# The bailout bunker begins four yards left of the intended x=-26 landing line.
	# That is inside Rick/Carl's roughly five-yard 4-hybrid dispersion corridor but
	# leaves the target itself on fairway. The bailout therefore carries modest
	# bunker exposure while remaining substantially safer than challenging water.
	author.add_hazard("bailout_bunker", "Bailout Bunker", "BUNKER", PackedVector2Array([
		Vector2(-38, 252), Vector2(-30, 252), Vector2(-30, 270), Vector2(-38, 270)
	]), 1, "standard")
	return author.build_definition()


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


func _finish() -> void:
	if failures == 0:
		print("POC-18F PERSONALITY STRATEGY DIAGNOSTIC PASSED")
		quit(0)
	else:
		push_error("POC-18F PERSONALITY STRATEGY DIAGNOSTIC FAILED: %d" % failures)
		quit(1)
