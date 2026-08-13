extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const QuietGolfer = preload("res://tests/fixtures/poc19_quiet_golfer.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")
const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")

const ROUNDS_PER_PROFILE := 100
const BASE_SEED := 191900

var failures: int = 0


func _init() -> void:
	print("POC-19D: 100-round profile stress test")
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

	print("POC19_ROUND,profile,round,seed,total_score,score_to_par,birdies,pars,bogeys,double_plus,aggressive_attempts,aggressive_holes,strategic_aggressive_holes,water_balls")
	print("POC19_HOLE_AVG,profile,hole,par,avg_strokes,avg_to_par,birdie_pct,par_pct,bogey_pct,double_plus_pct,aggressive_round_pct,avg_aggressive_attempts,water_round_pct")
	print("POC19_PROFILE_100,profile,rounds,avg_score,avg_to_par,best,worst,aggressive_attempts,aggressive_holes,strategic_aggressive_holes,water_balls")

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
	var strategic_holes: Array = fixture.strategic_hole_numbers()
	var hole_stats := {}
	for hole_number in range(1, 19):
		hole_stats[hole_number] = {
			"par": 0,
			"strokes": 0,
			"birdies": 0,
			"pars": 0,
			"bogeys": 0,
			"double_plus": 0,
			"aggressive_rounds": 0,
			"aggressive_attempts": 0,
			"water_rounds": 0
		}

	for round_index in range(ROUNDS_PER_PROFILE):
		var golfer = QuietGolfer.new()
		golfer.profile = profile_id
		golfer.apply_profile()
		profile_name = golfer.golfer_name
		var round = AutonomousRound.new(course, "back")
		var seed_value := BASE_SEED + round_index * 101
		var result: Dictionary = round.play_round(golfer, seed_value)
		if not bool(result.get("round_finished", false)):
			failures += 1
			push_error("FAIL: %s round %d did not complete" % [profile_name, round_index + 1])
			golfer.free()
			continue

		completed_rounds += 1
		var strokes := int(result.get("total_strokes", 0))
		total_strokes += strokes
		best_score = mini(best_score, strokes)
		worst_score = maxi(worst_score, strokes)
		total_aggressive_attempts += golfer.aggressive_attempts
		total_water_balls += golfer.water_balls

		var birdies := 0
		var pars := 0
		var bogeys := 0
		var double_plus := 0
		var round_aggressive_holes := 0
		var round_strategic_aggressive_holes := 0
		var scorecard: Array = result.get("scorecard", [])
		var hole_results: Array = result.get("hole_results", [])

		for row in scorecard:
			var hole_number := int(row.get("hole_number", 0))
			var par := int(row.get("par", 0))
			var hole_strokes := int(row.get("strokes", 0))
			var relative := hole_strokes - par
			var stats: Dictionary = hole_stats[hole_number]
			stats["par"] = par
			stats["strokes"] += hole_strokes
			if relative <= -1:
				birdies += 1
				stats["birdies"] += 1
			elif relative == 0:
				pars += 1
				stats["pars"] += 1
			elif relative == 1:
				bogeys += 1
				stats["bogeys"] += 1
			else:
				double_plus += 1
				stats["double_plus"] += 1

		for hole_result in hole_results:
			var hole_number := int(hole_result.get("hole_number", 0))
			var history: Array = hole_result.get("history", [])
			var aggressive_attempts_on_hole := 0
			var hit_water := false
			for shot in history:
				if bool(shot.get("was_aggressive", false)):
					aggressive_attempts_on_hole += 1
				if str(shot.get("outcome", "")) == "WATER":
					hit_water = true
			var stats: Dictionary = hole_stats[hole_number]
			stats["aggressive_attempts"] += aggressive_attempts_on_hole
			if aggressive_attempts_on_hole > 0:
				stats["aggressive_rounds"] += 1
				round_aggressive_holes += 1
				if hole_number in strategic_holes:
					round_strategic_aggressive_holes += 1
			if hit_water:
				stats["water_rounds"] += 1

		total_aggressive_holes += round_aggressive_holes
		total_strategic_aggressive_holes += round_strategic_aggressive_holes
		print("POC19_ROUND,%s,%d,%d,%d,%+d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			profile_name,
			round_index + 1,
			seed_value,
			strokes,
			strokes - 72,
			birdies,
			pars,
			bogeys,
			double_plus,
			golfer.aggressive_attempts,
			round_aggressive_holes,
			round_strategic_aggressive_holes,
			golfer.water_balls
		])
		golfer.free()

	_assert_equal(completed_rounds, ROUNDS_PER_PROFILE, "%s completes all stress-test rounds" % profile_name)
	for hole_number in range(1, 19):
		var stats: Dictionary = hole_stats[hole_number]
		var par := int(stats["par"])
		var avg_strokes := float(stats["strokes"]) / float(ROUNDS_PER_PROFILE)
		print("POC19_HOLE_AVG,%s,%d,%d,%.3f,%+.3f,%.1f,%.1f,%.1f,%.1f,%.1f,%.3f,%.1f" % [
			profile_name,
			hole_number,
			par,
			avg_strokes,
			avg_strokes - float(par),
			100.0 * float(stats["birdies"]) / float(ROUNDS_PER_PROFILE),
			100.0 * float(stats["pars"]) / float(ROUNDS_PER_PROFILE),
			100.0 * float(stats["bogeys"]) / float(ROUNDS_PER_PROFILE),
			100.0 * float(stats["double_plus"]) / float(ROUNDS_PER_PROFILE),
			100.0 * float(stats["aggressive_rounds"]) / float(ROUNDS_PER_PROFILE),
			float(stats["aggressive_attempts"]) / float(ROUNDS_PER_PROFILE),
			100.0 * float(stats["water_rounds"]) / float(ROUNDS_PER_PROFILE)
		])

	var avg_score := float(total_strokes) / float(ROUNDS_PER_PROFILE)
	print("POC19_PROFILE_100,%s,%d,%.3f,%+.3f,%d,%d,%d,%d,%d,%d" % [
		profile_name,
		completed_rounds,
		avg_score,
		avg_score - 72.0,
		best_score,
		worst_score,
		total_aggressive_attempts,
		total_aggressive_holes,
		total_strategic_aggressive_holes,
		total_water_balls
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
		print("POC-19D 100-ROUND PROFILE STRESS TEST PASSED")
		quit(0)
	else:
		push_error("POC-19D 100-ROUND PROFILE STRESS TEST FAILED: %d" % failures)
		quit(1)
