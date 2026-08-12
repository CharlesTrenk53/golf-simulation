extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const CourseContext = preload("res://simulation/course_context.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")

const ABILITIES := [30, 70, 95]
const TRIALS_PER_CELL := 15
const PUTT := 3

const HOLES := [
	{"name": "PAR3_165", "par": 3, "length": 165.0},
	{"name": "PAR4_410", "par": 4, "length": 410.0},
	{"name": "PAR5_525", "par": 5, "length": 525.0}
]

var failures: int = 0


func _init() -> void:
	print("POC-16C: hole-type scoring variety")
	print("hole,par,length,ability,holes,finish_pct,avg_score,avg_to_par,birdie_or_better_pct,par_pct,bogey_pct,double_plus_pct,avg_putts")

	var summaries: Dictionary = {}
	for hole in HOLES:
		var hole_name := str(hole["name"])
		summaries[hole_name] = {}
		for ability in ABILITIES:
			var summary := _run_cell(hole, int(ability))
			summaries[hole_name][int(ability)] = summary
			print("%s,%d,%.0f,%d,%d,%.2f,%.3f,%+.3f,%.2f,%.2f,%.2f,%.2f,%.3f" % [
				hole_name,
				int(hole["par"]),
				float(hole["length"]),
				int(ability),
				TRIALS_PER_CELL,
				float(summary["finish_pct"]),
				float(summary["avg_score"]),
				float(summary["avg_to_par"]),
				float(summary["birdie_or_better_pct"]),
				float(summary["par_pct"]),
				float(summary["bogey_pct"]),
				float(summary["double_plus_pct"]),
				float(summary["avg_putts"])
			])

	_validate_behavior(summaries)
	_print_birdie_diagnostic(summaries)
	if failures == 0:
		print("POC-16C HOLE-TYPE SCORING STRESS TEST PASSED")
		quit(0)
	else:
		push_error("POC-16C HOLE-TYPE SCORING STRESS TEST FAILED: %d" % failures)
		quit(1)


func _run_cell(hole: Dictionary, ability: int) -> Dictionary:
	var total_score: float = 0.0
	var total_putts: float = 0.0
	var finished: int = 0
	var birdie_or_better: int = 0
	var pars: int = 0
	var bogeys: int = 0
	var double_plus: int = 0
	var par_value := int(hole["par"])
	var length := float(hole["length"])

	for trial in range(TRIALS_PER_CELL):
		var golfer := _build_golfer(ability)
		var simulation := AutonomousHole.new()
		simulation.bag.use_literal_yardages(true)
		simulation.option_generator.bag.use_literal_yardages(true)
		var seed_value := 160200 + par_value * 10000 + ability * 100 + trial
		var result: Dictionary = simulation.play_hole(
			golfer,
			Vector3(0, 0, length),
			Vector3.ZERO,
			[],
			par_value,
			seed_value,
			_build_context(length)
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

		if score <= par_value - 1:
			birdie_or_better += 1
		elif score == par_value:
			pars += 1
		elif score == par_value + 1:
			bogeys += 1
		else:
			double_plus += 1
		golfer.free()

	var avg_score := total_score / TRIALS_PER_CELL
	return {
		"finish_pct": 100.0 * finished / TRIALS_PER_CELL,
		"avg_score": avg_score,
		"avg_to_par": avg_score - par_value,
		"birdie_or_better_pct": 100.0 * birdie_or_better / TRIALS_PER_CELL,
		"par_pct": 100.0 * pars / TRIALS_PER_CELL,
		"bogey_pct": 100.0 * bogeys / TRIALS_PER_CELL,
		"double_plus_pct": 100.0 * double_plus / TRIALS_PER_CELL,
		"avg_putts": total_putts / TRIALS_PER_CELL
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


func _build_context(length: float) -> RefCounted:
	var context := CourseContext.new()
	context.explicit_hole_out_required = true
	var midpoint := length * 0.5
	# Simple straight holes deliberately remove hazards/course-design complexity so
	# this slice isolates whether scoring behavior generalizes across par and length.
	context.add_zone("Fairway", CourseContext.Surface.FAIRWAY, Vector3(0, 0, midpoint), Vector2(24, max(20.0, midpoint - 10.0)))
	context.add_zone("Tee", CourseContext.Surface.TEE, Vector3(0, 0, length), Vector2(10, 8))
	context.add_zone("Green", CourseContext.Surface.GREEN, Vector3(0, 0, 0), Vector2(16, 14))
	return context


func _validate_behavior(summaries: Dictionary) -> void:
	for hole in HOLES:
		var hole_name := str(hole["name"])
		var low: Dictionary = summaries[hole_name][30]
		var mid: Dictionary = summaries[hole_name][70]
		var high: Dictionary = summaries[hole_name][95]
		_assert_true(float(high["avg_score"]) <= float(low["avg_score"]), "%s: high ability scores no worse than low ability" % hole_name)
		_assert_true(float(high["avg_putts"]) <= float(low["avg_putts"]), "%s: high ability takes no more putts than low ability" % hole_name)
		_assert_true(float(high["finish_pct"]) >= 93.0, "%s: high ability almost always completes the hole" % hole_name)
		_assert_true(float(mid["finish_pct"]) >= 80.0, "%s: mid ability usually completes the hole" % hole_name)


func _print_birdie_diagnostic(summaries: Dictionary) -> void:
	var high_birdie_cells := 0
	for hole in HOLES:
		var hole_name := str(hole["name"])
		if float(summaries[hole_name][95]["birdie_or_better_pct"]) > 0.0:
			high_birdie_cells += 1
	print("BIRDIE_DIAGNOSTIC high_ability_hole_types_with_birdie=%d_of_%d" % [high_birdie_cells, HOLES.size()])
	if high_birdie_cells == 0:
		print("BIRDIE_DIAGNOSTIC YELLOW: no Ability 95 birdies emerged on any representative hole type")
	else:
		print("BIRDIE_DIAGNOSTIC GREEN: birdies emerge naturally on at least one representative hole type")


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
