extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")
const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")

const ROUNDS_PER_PROFILE := 10
const BASE_SEED := 191900

var failures: int = 0


func _init() -> void:
	print("POC-19C: multi-seed personality diagnostic")
	var fixture = StrategicCourseFixture.new()
	var course = fixture.build_course()
	_assert_true(course != null, "strategic proving course builds")
	if course == null:
		_finish()
		return

	var profiles := [
		GolferScript.GolferProfile.WILD_BILL,
		GolferScript.GolferProfile.RECKLESS_RICK,
		GolferScript.GolferProfile.CAREFUL_CARL
	]

	print("POC19_MULTI_SUMMARY,profile,rounds,avg_score,avg_to_par,best,worst,aggressive_attempts,aggressive_holes,strategic_aggressive_holes,water_balls,water_holes_hit")
	for profile_id in profiles:
		_run_profile(course, fixture, profile_id)

	_finish()


func _run_profile(course, fixture, profile_id: int) -> void:
	var profile_name := ""
	var total_strokes := 0
	var best_score := 999
	var worst_score := -999
	var completed_rounds := 0
	var total_aggressive_attempts := 0
	var total_aggressive_holes := 0
	var total_strategic_aggressive_holes := 0
	var total_water_balls := 0
	var total_water_holes_hit := 0
	var strategic_holes: Array = fixture.strategic_hole_numbers()

	for round_index in range(ROUNDS_PER_PROFILE):
		var golfer = GolferScript.new()
		golfer.profile = profile_id
		golfer.apply_profile()
		profile_name = golfer.golfer_name
		var round = AutonomousRound.new(course, "back")
		var seed_value := BASE_SEED + round_index * 101
		var result: Dictionary = round.play_round(golfer, seed_value)
		_assert_true(bool(result.get("round_finished", false)), "%s round %d completes" % [profile_name, round_index + 1])
		if bool(result.get("round_finished", false)):
			completed_rounds += 1

		var strokes := int(result.get("total_strokes", 0))
		total_strokes += strokes
		best_score = mini(best_score, strokes)
		worst_score = maxi(worst_score, strokes)
		total_aggressive_attempts += golfer.aggressive_attempts
		total_water_balls += golfer.water_balls

		var hole_results: Array = result.get("hole_results", [])
		for hole_result in hole_results:
			var hole_number := int(hole_result.get("hole_number", 0))
			var history: Array = hole_result.get("history", [])
			var hole_had_aggression := false
			var hole_hit_water := false
			for shot in history:
				if bool(shot.get("was_aggressive", false)):
					hole_had_aggression = true
				if str(shot.get("outcome", "")) == "WATER":
					hole_hit_water = true
			if hole_had_aggression:
				total_aggressive_holes += 1
				if hole_number in strategic_holes:
					total_strategic_aggressive_holes += 1
			if hole_hit_water:
				total_water_holes_hit += 1

		golfer.free()

	var avg_score := float(total_strokes) / float(ROUNDS_PER_PROFILE)
	var avg_to_par := avg_score - 72.0
	print("POC19_MULTI_SUMMARY,%s,%d,%.2f,%+.2f,%d,%d,%d,%d,%d,%d,%d" % [
		profile_name,
		completed_rounds,
		avg_score,
		avg_to_par,
		best_score,
		worst_score,
		total_aggressive_attempts,
		total_aggressive_holes,
		total_strategic_aggressive_holes,
		total_water_balls,
		total_water_holes_hit
	])


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	if failures == 0:
		print("POC-19C MULTI-SEED PERSONALITY DIAGNOSTIC PASSED")
		quit(0)
	else:
		push_error("POC-19C MULTI-SEED PERSONALITY DIAGNOSTIC FAILED: %d" % failures)
		quit(1)
