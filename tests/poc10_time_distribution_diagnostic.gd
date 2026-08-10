extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const DevelopmentEvidenceBridge = preload("res://simulation/development_evidence_bridge.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

# POC-10 time-distribution diagnostic
# ----------------------------------
# Two otherwise identical golfers accumulate exactly 10,000 high-quality Approach
# practice repetitions between ages 18 and 57. One receives nearly all of that
# opportunity early; the other spreads it across the full forty-year period.
# Both are evaluated at the same age so elapsed time, age plasticity, experience
# entrenchment, and annual retention can interact naturally.

const START_AGE := 18
const END_AGE := 57
const SHOT_TYPE := 1
const TOTAL_REPETITIONS := 10000
const QUALITY := 0.85
const EXECUTION_SCORE := 69.0
const OUTPUT_PATH := "res://poc10_time_distribution.csv"

var output_rows: Array[String] = []

func _init() -> void:
	output_rows.append("profile,age,annual_repetitions,cumulative_repetitions,evidence_count,total_experience,age_plasticity,skill_delta,effective_skill")
	var rapid := _run_profile("rapid", _rapid_schedule())
	var distributed := _run_profile("distributed", _distributed_schedule())
	_write_output()

	var failures := 0
	if int(rapid["cumulative_repetitions"]) != TOTAL_REPETITIONS:
		failures += 1
		push_error("Rapid profile did not preserve exactly 10,000 raw repetitions")
	if int(distributed["cumulative_repetitions"]) != TOTAL_REPETITIONS:
		failures += 1
		push_error("Distributed profile did not preserve exactly 10,000 raw repetitions")
	if int(rapid["evidence_count"]) != int(distributed["evidence_count"]):
		failures += 1
		push_error("Equal volume and quality should produce equal lifetime evidence counts")
	if abs(float(rapid["effective_skill"]) - float(distributed["effective_skill"])) < 0.0001:
		failures += 1
		push_error("Different timing should not collapse to identical final development")

	print("POC-10 TIME DISTRIBUTION SUMMARY")
	print("Rapid final skill: ", rapid["effective_skill"], " delta: ", rapid["skill_delta"])
	print("Distributed final skill: ", distributed["effective_skill"], " delta: ", distributed["skill_delta"])
	print("Both raw repetitions: ", TOTAL_REPETITIONS, " | both evidence count: ", rapid["evidence_count"])
	print("Wrote POC-10 time-distribution CSV: ", OUTPUT_PATH)

	if failures == 0:
		print("POC-10 TIME DISTRIBUTION DIAGNOSTIC PASSED")
		quit(0)
	else:
		push_error("POC-10 TIME DISTRIBUTION DIAGNOSTIC FAILED: %d" % failures)
		quit(1)

func _run_profile(label: String, schedule: Dictionary) -> Dictionary:
	var golfer = _create_golfer(label)
	var development = TechniqueSkillDevelopment.new()
	development.initialize_from_golfer(golfer)
	var bridge = DevelopmentEvidenceBridge.new()
	var cumulative := 0

	for age in range(START_AGE, END_AGE + 1):
		golfer.age = age
		development.set_current_age(age)
		var annual_repetitions := int(schedule.get(age, 0))
		if annual_repetitions > 0:
			bridge.apply_practice_exposure(development, SHOT_TYPE, annual_repetitions, QUALITY, EXECUTION_SCORE)
			cumulative += annual_repetitions
		var state: Dictionary = development.development_state(SHOT_TYPE)
		output_rows.append("%s,%d,%d,%d,%d,%d,%.4f,%.6f,%.6f" % [
			label,
			age,
			annual_repetitions,
			cumulative,
			int(state["evidence_count"]),
			int(state["total_experience"]),
			float(state["age_learning_plasticity"]),
			float(state["skill_delta"]),
			float(state["effective_skill"])
		])
		if age < END_AGE:
			development.advance_year()

	var final_state: Dictionary = development.development_state(SHOT_TYPE)
	golfer.free()
	return {
		"cumulative_repetitions": cumulative,
		"evidence_count": int(final_state["evidence_count"]),
		"total_experience": int(final_state["total_experience"]),
		"skill_delta": float(final_state["skill_delta"]),
		"effective_skill": float(final_state["effective_skill"])
	}

func _rapid_schedule() -> Dictionary:
	# 2,000 repetitions per year from ages 18 through 22, then no practice.
	var schedule: Dictionary = {}
	for age in range(START_AGE, END_AGE + 1):
		schedule[age] = 2000 if age <= 22 else 0
	return schedule

func _distributed_schedule() -> Dictionary:
	# 250 repetitions each year for forty years: 18 through 57 inclusive.
	var schedule: Dictionary = {}
	for age in range(START_AGE, END_AGE + 1):
		schedule[age] = 250
	return schedule

func _create_golfer(label: String):
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.golfer_name = "POC-10 " + label
	golfer.age = START_AGE
	golfer.driving = 48.0
	golfer.approach = 48.0
	golfer.short_game = 48.0
	golfer.putting = 48.0
	golfer.career_shot_experience = {0: 0, 1: 0, 2: 0, 3: 0}
	golfer.skill_learning_rates = {0: 1.0, 1: 1.0, 2: 1.0, 3: 1.0}
	golfer.skill_potentials = {0: 78.0, 1: 78.0, 2: 78.0, 3: 78.0}
	return golfer

func _write_output() -> void:
	var output = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("Could not write POC-10 time-distribution CSV: %s" % OUTPUT_PATH)
		return
	for row in output_rows:
		output.store_line(row)
	output.close()
