extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const DevelopmentEvidenceBridge = preload("res://simulation/development_evidence_bridge.gd")
const TechnicalReadiness = preload("res://simulation/technical_readiness.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

const SHOT_TYPES := [0, 1, 2, 3]
const OUTPUT_PATH := "res://poc10_former_competitor_inactivity.csv"
const PLAY_EXECUTION_BASE := 67.0
const PRACTICE_EXECUTION_BASE := 69.0

var rows: Array[String] = []
var failures := 0

func _init() -> void:
	rows.append("phase,days_inactive,recovery_reps,durable_composite,usable_composite,avg_rust,drive_usable,approach_usable,short_game_usable,putt_usable")
	var development = _build_former_competitor_to_45()
	var durable := _durable_skills(development)
	var durable_composite := _average_dictionary(durable)

	var checkpoints := [7, 30, 90, 180, 365, 730, 1825]
	var previous_penalty := -1.0
	for days in checkpoints:
		var readiness = TechnicalReadiness.new()
		readiness.advance_days(float(days))
		var snapshot := _readiness_snapshot(durable, readiness)
		var avg_rust := float(snapshot["avg_rust"])
		if previous_penalty >= 0.0:
			_expect(avg_rust > previous_penalty, "rust increases as inactivity lengthens through %d days" % days)
		previous_penalty = avg_rust
		_append_row("LAYOFF", days, 0, durable_composite, snapshot)

	var one_year = TechnicalReadiness.new()
	one_year.advance_days(365.0)
	var one_year_before := _readiness_snapshot(durable, one_year)
	var recovery_checkpoints := [50, 100, 220, 500, 1000]
	var cumulative_reps := 0
	var previous_usable := float(one_year_before["usable_composite"])
	for target_reps in recovery_checkpoints:
		var added := target_reps - cumulative_reps
		for shot_type in SHOT_TYPES:
			one_year.record_activity(shot_type, added)
		cumulative_reps = target_reps
		var recovered := _readiness_snapshot(durable, one_year)
		_expect(float(recovered["usable_composite"]) > previous_usable, "usable skill recovers with %d reacquisition reps" % target_reps)
		previous_usable = float(recovered["usable_composite"])
		_append_row("RECOVERY_FROM_1Y", 365, target_reps, durable_composite, recovered)

	var final_recovery := _readiness_snapshot(durable, one_year)
	_expect(float(final_recovery["usable_composite"]) > float(one_year_before["usable_composite"]) + 0.75 * float(one_year_before["avg_rust"]), "1000 reps recover most one-year rust")
	_expect(abs(_average_dictionary(_durable_skills(development)) - durable_composite) < 0.000001, "rust and reacquisition do not alter durable technical skill")

	_write_output()
	print("POC-10 FORMER COMPETITOR INACTIVITY SUMMARY")
	print("Durable composite at age 45: ", durable_composite)
	print("Usable after 1 year inactive: ", one_year_before["usable_composite"], " avg rust: ", one_year_before["avg_rust"])
	print("Usable after 1000 reacquisition reps: ", final_recovery["usable_composite"], " avg rust: ", final_recovery["avg_rust"])
	if failures == 0:
		print("POC-10 FORMER COMPETITOR INACTIVITY DIAGNOSTIC PASSED")
		quit(0)
	else:
		push_error("POC-10 FORMER COMPETITOR INACTIVITY DIAGNOSTIC FAILED: %d" % failures)
		quit(1)

func _build_former_competitor_to_45():
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.golfer_name = "Former Competitor"
	golfer.age = 16
	golfer.driving = 48.0
	golfer.approach = 48.0
	golfer.short_game = 47.0
	golfer.putting = 48.0
	golfer.driving_distance = 55.0
	golfer.physical_power = 74.0
	golfer.mobility = 75.0
	golfer.coordination = 77.0
	golfer.endurance = 75.0
	golfer.career_shot_experience = {0: 400, 1: 600, 2: 450, 3: 700}
	golfer.skill_learning_rates = {0: 1.05, 1: 1.06, 2: 1.04, 3: 1.02}
	golfer.skill_potentials = {0: 76.0, 1: 78.0, 2: 77.0, 3: 76.0}

	var development = TechniqueSkillDevelopment.new()
	development.initialize_from_golfer(golfer)
	var bridge = DevelopmentEvidenceBridge.new()
	var lifecycle = GolferLifecycle.new()
	for age in range(16, 46):
		golfer.age = age
		development.set_current_age(age)
		var lifestyle := _former_competitor_lifestyle(age)
		var rounds := int(lifestyle["rounds"])
		var practice_reps := int(lifestyle["practice_reps"])
		var quality := float(lifestyle["quality"])
		var focus: Dictionary = lifestyle["focus"]
		var play_distribution := {0: rounds * 14, 1: rounds * 22, 2: rounds * 12, 3: rounds * 30}
		for shot_type in SHOT_TYPES:
			var play_score := clampf(PLAY_EXECUTION_BASE + _physical_modifier(golfer, shot_type), 0.0, 100.0)
			bridge.apply_play_exposure(development, shot_type, int(play_distribution[shot_type]), play_score, 0.0, 0.0, play_score)
		var allocations := _allocate_repetitions(practice_reps, focus)
		for shot_type in SHOT_TYPES:
			var reps := int(allocations[shot_type])
			if reps <= 0:
				continue
			var practice_score := clampf(PRACTICE_EXECUTION_BASE + _physical_modifier(golfer, shot_type), 0.0, 100.0)
			bridge.apply_practice_exposure(development, shot_type, reps, quality, practice_score, 0.0, 0.0, practice_score)
		if age < 45:
			development.advance_year()
			lifecycle.advance_year(golfer)
	golfer.free()
	return development

func _former_competitor_lifestyle(age: int) -> Dictionary:
	var rounds := 100
	var practice_reps := 5200
	var quality := 0.83
	if age > 24 and age <= 40:
		rounds = 105; practice_reps = 4300; quality = 0.82
	elif age > 40:
		rounds = 55; practice_reps = 1500; quality = 0.65
	return {"rounds": rounds, "practice_reps": practice_reps, "quality": quality, "focus": {0: 0.24, 1: 0.31, 2: 0.25, 3: 0.20}}

func _durable_skills(development) -> Dictionary:
	var values: Dictionary = {}
	for shot_type in SHOT_TYPES:
		values[shot_type] = float(development.development_state(shot_type)["effective_skill"])
	return values

func _readiness_snapshot(durable: Dictionary, readiness) -> Dictionary:
	var usable: Dictionary = {}
	var rust_sum := 0.0
	var usable_sum := 0.0
	for shot_type in SHOT_TYPES:
		usable[shot_type] = readiness.usable_skill(float(durable[shot_type]), shot_type)
		usable_sum += float(usable[shot_type])
		rust_sum += float(readiness.state_for(shot_type)["rust_penalty"])
	return {
		"usable": usable,
		"usable_composite": usable_sum / 4.0,
		"avg_rust": rust_sum / 4.0
	}

func _append_row(phase: String, days: int, recovery_reps: int, durable_composite: float, snapshot: Dictionary) -> void:
	var usable: Dictionary = snapshot["usable"]
	rows.append("%s,%d,%d,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f" % [
		phase, days, recovery_reps, durable_composite,
		float(snapshot["usable_composite"]), float(snapshot["avg_rust"]),
		float(usable[0]), float(usable[1]), float(usable[2]), float(usable[3])
	])

func _physical_modifier(golfer, shot_type: int) -> float:
	var factor := float(golfer.physical_distance_factor(shot_type))
	var sensitivity := 0.0
	match shot_type:
		0: sensitivity = 1.5
		1: sensitivity = 0.8
		2: sensitivity = 0.25
		3: sensitivity = 0.05
	return (factor - 1.0) * sensitivity

func _allocate_repetitions(repetitions: int, focus: Dictionary) -> Dictionary:
	var allocations: Dictionary = {}
	var allocated := 0
	var remainders: Array = []
	for shot_type in SHOT_TYPES:
		var exact := float(repetitions) * float(focus.get(shot_type, 0.0))
		var base := int(floor(exact))
		allocations[shot_type] = base
		allocated += base
		remainders.append({"shot_type": shot_type, "remainder": exact - float(base)})
	remainders.sort_custom(func(a, b): return float(a["remainder"]) > float(b["remainder"]))
	for i in range(repetitions - allocated):
		var shot_type := int(remainders[i % remainders.size()]["shot_type"])
		allocations[shot_type] = int(allocations[shot_type]) + 1
	return allocations

func _average_dictionary(values: Dictionary) -> float:
	var total := 0.0
	for shot_type in SHOT_TYPES:
		total += float(values[shot_type])
	return total / 4.0

func _write_output() -> void:
	var output = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("Could not write POC-10 former competitor inactivity CSV: %s" % OUTPUT_PATH)
		failures += 1
		return
	for row in rows:
		output.store_line(row)
	output.close()
	print("Wrote POC-10 former competitor inactivity CSV: ", OUTPUT_PATH)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
