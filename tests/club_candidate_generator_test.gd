extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")
const ClubCandidateGenerator = preload("res://simulation/club_candidate_generator.gd")

var failures: int = 0


func _init() -> void:
	print("POC-13A: bag-derived club candidates")
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

	_assert_true(candidates.size() >= 6, "tee produces a real menu of bag-derived candidates")
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
		_assert_true(carry <= last_carry + 0.001, "candidates are ordered longest to shortest")
		last_carry = carry
		_assert_true(candidate.has("target"), "%s has an explicit target" % club_id)
		_assert_true(candidate.has("remaining_after_target"), "%s exposes next-shot distance" % club_id)
		_assert_true(candidate.has("expected_surface"), "%s resolves expected landing surface" % club_id)
		_assert_true(candidate.has("corridor_hazard_count"), "%s inspects authoritative hazard corridor" % club_id)
		_assert_true(candidate.has("dispersion"), "%s carries golfer/club dispersion" % club_id)

	_assert_true(unique_ids.size() == candidates.size(), "one candidate is generated per feasible bag club")

	var driver: Dictionary = _candidate(candidates, "DRIVER")
	var five_iron: Dictionary = _candidate(candidates, "5_IRON")
	if not driver.is_empty() and not five_iron.is_empty():
		_assert_true(float(driver.get("effective_carry", 0.0)) > float(five_iron.get("effective_carry", 0.0)), "driver and 5 iron remain distinct physical choices")
		_assert_true(Vector3(driver.get("target", Vector3.ZERO)).distance_to(state.ball_position) > Vector3(five_iron.get("target", Vector3.ZERO)).distance_to(state.ball_position), "clubs create distinct landing positions rather than semantic templates")

	golfer.free()
	if failures == 0:
		print("POC-13A CLUB CANDIDATE GENERATOR TESTS PASSED")
		quit(0)
	else:
		push_error("POC-13A CLUB CANDIDATE GENERATOR TESTS FAILED: %d" % failures)
		quit(1)


func _has_club(candidates: Array, club_id: String) -> bool:
	return not _candidate(candidates, club_id).is_empty()


func _candidate(candidates: Array, club_id: String) -> Dictionary:
	for candidate in candidates:
		if str(candidate.get("club_id", "")) == club_id:
			return candidate
	return {}


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
