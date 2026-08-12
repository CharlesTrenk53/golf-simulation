extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const CourseContext = preload("res://simulation/course_context.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")

const ABILITIES := [30, 50, 70, 85, 95]
const TRIALS_PER_ABILITY := 25
const PAR := 4
const PUTT := 3

var failures: int = 0


func _init() -> void:
	print("POC-16B: repeated full-hole scoring behavior")
	print("ability,holes,finish_pct,avg_score,birdie_or_better_pct,par_pct,bogey_pct,double_plus_pct,avg_putts")

	var summaries: Dictionary = {}
	for ability in ABILITIES:
		var summary := _run_ability(int(ability))
		summaries[int(ability)] = summary
		print("%d,%d,%.2f,%.3f,%.2f,%.2f,%.2f,%.2f,%.3f" % [
			int(ability),
			TRIALS_PER_ABILITY,
			float(summary["finish_pct"]),
			float(summary["avg_score"]),
			float(summary["birdie_or_better_pct"]),
			float(summary["par_pct"]),
			float(summary["bogey_pct"]),
			float(summary["double_plus_pct"]),
			float(summary["avg_putts"])
		])

	_validate_behavior(summaries)
	if failures == 0:
		print("POC-16B FULL-HOLE SCORING STRESS TEST PASSED")
		quit(0)
	else:
		push_error("POC-16B FULL-HOLE SCORING STRESS TEST FAILED: %d" % failures)
		quit(1)


func _run_ability(ability: int) -> Dictionary:
	var total_score: float = 0.0
	var total_putts: float = 0.0
	var finished: int = 0
	var birdie_or_better: int = 0
	var pars: int = 0
	var bogeys: int = 0
	var double_plus: int = 0

	for trial in range(TRIALS_PER_ABILITY):
		var golfer := _build_golfer(ability)
		var simulation := AutonomousHole.new()
		simulation.bag.use_literal_yardages(true)
		simulation.option_generator.bag.use_literal_yardages(true)
		var result: Dictionary = simulation.play_hole(
			golfer,
			Vector3(0, 0, 410),
			Vector3.ZERO,
			[],
			PAR,
			160100 + ability * 100 + trial,
			_build_par4_context()
		)

		var score := int(result.get("strokes", 12))
		total_score += score
		if bool(result.get("finished", false)):
			finished += 1
		var putts := 0
		for shot in result.get("history", []):
			if int(shot.get("shot_type", -1)) == PUTT:
				putts += 1
		total_putts += putts

		if score <= PAR - 1:
			birdie_or_better += 1
		elif score == PAR:
			pars += 1
		elif score == PAR + 1:
			bogeys += 1
		else:
			double_plus += 1
		golfer.free()

	return {
		"finish_pct": 100.0 * finished / TRIALS_PER_ABILITY,
		"avg_score": total_score / TRIALS_PER_ABILITY,
		"birdie_or_better_pct": 100.0 * birdie_or_better / TRIALS_PER_ABILITY,
		"par_pct": 100.0 * pars / TRIALS_PER_ABILITY,
		"bogey_pct": 100.0 * bogeys / TRIALS_PER_ABILITY,
		"double_plus_pct": 100.0 * double_plus / TRIALS_PER_ABILITY,
		"avg_putts": total_putts / TRIALS_PER_ABILITY
	}


func _build_golfer(ability: int) -> Node:
	var golfer := GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.golfer_name = "Ability %d" % ability
	golfer.driving = ability
	golfer.approach = ability
	golfer.short_game = ability
	golfer.putting = ability
	golfer.risk_tolerance = 50.0
	golfer.confidence = 70.0
	golfer.decision_variability = 0.0
	golfer.physical_power = 70.0
	golfer.mobility = 70.0
	golfer.coordination = 70.0
	golfer.endurance = 70.0
	return golfer


func _build_par4_context() -> RefCounted:
	var context := CourseContext.new()
	context.explicit_hole_out_required = true
	context.add_zone("Fairway", CourseContext.Surface.FAIRWAY, Vector3(0, 0, 205), Vector2(20, 195))
	context.add_zone("Tee", CourseContext.Surface.TEE, Vector3(0, 0, 410), Vector2(10, 8))
	context.add_zone("Green", CourseContext.Surface.GREEN, Vector3(0, 0, 0), Vector2(16, 14))
	return context


func _validate_behavior(summaries: Dictionary) -> void:
	var low: Dictionary = summaries[30]
	var high: Dictionary = summaries[95]
	_assert_true(float(high["avg_score"]) <= float(low["avg_score"]), "highest-ability golfer scores no worse on average than lowest-ability golfer")
	_assert_true(float(high["double_plus_pct"]) <= float(low["double_plus_pct"]), "highest-ability golfer produces no more doubles+ than lowest-ability golfer")
	_assert_true(float(high["finish_pct"]) >= 96.0, "highest-ability golfer virtually always holes out before safety cap")
	_assert_true(float(low["finish_pct"]) >= 80.0, "lowest-ability golfer usually holes out before safety cap")


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
