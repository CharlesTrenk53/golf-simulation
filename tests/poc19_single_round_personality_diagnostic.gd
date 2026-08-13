extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")
const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")

var failures: int = 0


func _init() -> void:
	print("POC-19B: single-round personality diagnostic")
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
	var summaries: Dictionary = {}

	print("POC19_HOLE,profile,hole,par,strokes,score_to_par,aggressive_attempts,water_balls")
	for profile_id in profiles:
		var golfer = GolferScript.new()
		golfer.profile = profile_id
		golfer.apply_profile()
		var profile_name: String = golfer.golfer_name
		var round = AutonomousRound.new(course, "back")
		var result: Dictionary = round.play_round(golfer, 191900)
		var scorecard: Array = result.get("scorecard", [])
		var hole_results: Array = result.get("hole_results", [])

		_assert_true(bool(result.get("round_finished", false)), "%s completes 18 holes" % profile_name)
		_assert_equal(scorecard.size(), 18, "%s retains 18 scorecard rows" % profile_name)
		_assert_equal(hole_results.size(), 18, "%s retains 18 hole histories" % profile_name)

		var aggressive_holes := 0
		var strategic_aggressive_holes := 0
		var water_holes_hit := 0
		for index in range(min(scorecard.size(), hole_results.size())):
			var row: Dictionary = scorecard[index]
			var hole_result: Dictionary = hole_results[index]
			var history: Array = hole_result.get("history", [])
			var hole_aggressive := 0
			var hole_water := 0
			for shot in history:
				if bool(shot.get("was_aggressive", false)):
					hole_aggressive += 1
				if str(shot.get("outcome", "")) == "WATER":
					hole_water += 1
			if hole_aggressive > 0:
				aggressive_holes += 1
				if int(row.get("hole_number", 0)) in fixture.strategic_hole_numbers():
					strategic_aggressive_holes += 1
			if hole_water > 0:
				water_holes_hit += 1
			print("POC19_HOLE,%s,%d,%d,%d,%+d,%d,%d" % [
				profile_name,
				int(row.get("hole_number", 0)),
				int(row.get("par", 0)),
				int(row.get("strokes", 0)),
				int(row.get("score_to_par", 0)),
				hole_aggressive,
				hole_water
			])

		summaries[profile_name] = {
			"strokes": int(result.get("total_strokes", 0)),
			"score_to_par": int(result.get("score_to_par", 0)),
			"aggressive_attempts": golfer.aggressive_attempts,
			"aggressive_holes": aggressive_holes,
			"strategic_aggressive_holes": strategic_aggressive_holes,
			"water_balls": golfer.water_balls,
			"water_holes_hit": water_holes_hit,
			"shots_attempted": golfer.shots_attempted
		}
		print("POC19_PROFILE_SUMMARY,%s,strokes=%d,score_to_par=%+d,aggressive_attempts=%d,aggressive_holes=%d,strategic_aggressive_holes=%d,water_balls=%d,water_holes_hit=%d,shots=%d" % [
			profile_name,
			int(result.get("total_strokes", 0)),
			int(result.get("score_to_par", 0)),
			golfer.aggressive_attempts,
			aggressive_holes,
			strategic_aggressive_holes,
			golfer.water_balls,
			water_holes_hit,
			golfer.shots_attempted
		])
		golfer.free()

	_assert_equal(summaries.size(), 3, "all three golfer profiles produce summaries")
	_finish()


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
		print("POC-19B SINGLE-ROUND PERSONALITY DIAGNOSTIC PASSED")
		quit(0)
	else:
		push_error("POC-19B SINGLE-ROUND PERSONALITY DIAGNOSTIC FAILED: %d" % failures)
		quit(1)
