extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")
const ClubCandidateGenerator = preload("res://simulation/club_candidate_generator.gd")

var failures: int = 0


func _init() -> void:
	print("POC-13A/F: bag-derived club + target candidates")
	var hole = HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")
	_assert_true(hole != null, "Decision Point loads")
	if hole == null:
		quit(1)
		return

	var playable = DataDefinedAutonomousHole.new(hole)
	var state = playable.create_state(1313)
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()

	var generator = ClubCandidateGenerator.new()
	generator.bag.use_literal_yardages(true)
	var candidates: Array = generator.generate(golfer, state)

	_assert_true(candidates.size() >= 18, "tee produces a real menu of club-target combinations")
	_assert_true(_has_club(candidates, "DRIVER"), "driver is independently considered")
	_assert_true(_has_club(candidates, "3_WOOD"), "3 wood is independently considered")
	_assert_true(_has_club(candidates, "5_WOOD"), "5 wood is independently considered")
	_assert_true(_has_club(candidates, "4_HYBRID"), "hybrid is independently considered")
	_assert_true(_has_club(candidates, "5_IRON"), "5 iron is independently considered")
	_assert_true(not _has_club(candidates, "PUTTER"), "putter is excluded from tee advances")

	var unique_ids: Dictionary = {}
	var last_carry: float = INF
	for candidate in candidates:
		var club_id: String = str(candidate.get("club_id", ""))
		_assert_true(not club_id.is_empty(), "every candidate identifies its club")
		unique_ids[club_id] = true
		var carry: float = float(candidate.get("effective_carry", 0.0))
		_assert_true(carry > 0.0, "%s has golfer-specific effective carry" % club_id)
		_assert_true(carry <= last_carry + 0.001, "candidate groups are ordered longest to shortest")
		last_carry = carry
		_assert_true(candidate.has("target"), "%s has an explicit target" % club_id)
		_assert_true(candidate.has("target_variant"), "%s identifies its spatial target variant" % club_id)
		_assert_true(candidate.has("lateral_offset"), "%s exposes target lateral offset" % club_id)
		_assert_true(candidate.has("remaining_after_target"), "%s exposes next-shot distance" % club_id)
		_assert_true(candidate.has("expected_surface"), "%s resolves expected landing surface" % club_id)
		_assert_true(candidate.has("corridor_hazard_count"), "%s inspects authoritative hazard corridor" % club_id)
		_assert_true(candidate.has("dispersion"), "%s carries golfer/club dispersion" % club_id)

	_assert_true(unique_ids.size() >= 6, "multiple feasible bag clubs survive target expansion")

	var driver_targets: Array = _candidates_for(candidates, "DRIVER")
	_assert_true(driver_targets.size() == 3, "driver receives center, left, and right spatial targets")
	_assert_true(_has_variant(driver_targets, "CENTER"), "driver has center target")
	_assert_true(_has_variant(driver_targets, "LEFT"), "driver has left target")
	_assert_true(_has_variant(driver_targets, "RIGHT"), "driver has right target")
	if driver_targets.size() == 3:
		var center := _variant(driver_targets, "CENTER")
		var left := _variant(driver_targets, "LEFT")
		var right := _variant(driver_targets, "RIGHT")
		_assert_true(Vector3(left.get("target", Vector3.ZERO)).distance_to(Vector3(center.get("target", Vector3.ZERO))) > 5.0, "left target is spatially distinct from center")
		_assert_true(Vector3(right.get("target", Vector3.ZERO)).distance_to(Vector3(center.get("target", Vector3.ZERO))) > 5.0, "right target is spatially distinct from center")
		var consequence_signatures: Dictionary = {}
		for option in driver_targets:
			var signature := "%s|%d|%s" % [str(option.get("expected_surface", "")), int(option.get("corridor_hazard_count", 0)), str(option.get("out_of_bounds", false))]
			consequence_signatures[signature] = true
		_assert_true(consequence_signatures.size() >= 2, "Decision Point geometry gives driver targets different spatial consequences")

	var driver: Dictionary = _variant(driver_targets, "CENTER")
	var five_iron: Dictionary = _variant(_candidates_for(candidates, "5_IRON"), "CENTER")
	if not driver.is_empty() and not five_iron.is_empty():
		_assert_true(float(driver.get("effective_carry", 0.0)) > float(five_iron.get("effective_carry", 0.0)), "driver and 5 iron remain distinct physical choices")
		_assert_true(Vector3(driver.get("target", Vector3.ZERO)).distance_to(state.ball_position) > Vector3(five_iron.get("target", Vector3.ZERO)).distance_to(state.ball_position), "clubs create distinct landing distances in addition to target variants")

	golfer.free()
	if failures == 0:
		print("POC-13A/F CLUB TARGET GENERATOR TESTS PASSED")
		quit(0)
	else:
		push_error("POC-13A/F CLUB TARGET GENERATOR TESTS FAILED: %d" % failures)
		quit(1)


func _has_club(candidates: Array, club_id: String) -> bool:
	return not _candidates_for(candidates, club_id).is_empty()


func _candidates_for(candidates: Array, club_id: String) -> Array:
	var result: Array = []
	for candidate in candidates:
		if str(candidate.get("club_id", "")) == club_id:
			result.append(candidate)
	return result


func _has_variant(candidates: Array, variant_id: String) -> bool:
	return not _variant(candidates, variant_id).is_empty()


func _variant(candidates: Array, variant_id: String) -> Dictionary:
	for candidate in candidates:
		if str(candidate.get("target_variant", "")) == variant_id:
			return candidate
	return {}


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
