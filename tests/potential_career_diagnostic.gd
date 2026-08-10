extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")

const START_AGE := 16
const END_AGE := 45
const SHOTS_PER_YEAR := 1100
const EXECUTION_MEAN := 68.0
const EXECUTION_SD := 6.0
const POTENTIAL_LEVELS := [58.0, 68.0, 78.0, 88.0, 96.0]
const CHECKPOINTS := [16, 20, 25, 30, 35, 40, 45]
const OUTPUT_PATH := "res://poc09_potential_careers.csv"

var output_rows: Array[String] = []

func _init() -> void:
	print("=== POC-09 POTENTIAL CAREER DIAGNOSTIC ===")
	print("Same start, aptitude, age, experience, and execution stream; only latent driving potential differs.")
	print("potential,age,effective_skill,delta,potential_resistance")
	output_rows.append("potential,age,effective_skill,delta,potential_resistance")

	for potential in POTENTIAL_LEVELS:
		_run_profile(float(potential))

	_write_output()
	print("=== END POC-09 POTENTIAL CAREER DIAGNOSTIC ===")
	quit(0)

func _run_profile(potential: float) -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 1
	golfer.apply_profile()
	golfer.age = START_AGE
	golfer.driving = 48.0
	golfer.career_shot_experience[0] = 800
	golfer.skill_learning_rates[0] = 1.0

	var development = TechniqueSkillDevelopment.new()
	development.initialize_from_golfer(golfer)
	development.set_skill_potential(0, potential)

	# Reset the stream for every potential profile so potential is the only source
	# of between-profile divergence in this diagnostic.
	seed(99017)

	for age in range(START_AGE, END_AGE + 1):
		development.set_current_age(float(age))
		if age in CHECKPOINTS:
			_emit_state(potential, age, development)
		if age == END_AGE:
			break
		for _shot in range(SHOTS_PER_YEAR):
			var persistent_score = clamp(randfn(EXECUTION_MEAN, EXECUTION_SD), 0.0, 100.0)
			development.record_execution(0, persistent_score, 0.0, 0.0, persistent_score)

	golfer.free()

func _emit_state(potential: float, age: int, development: RefCounted) -> void:
	var state = development.development_state(0)
	var row = "%.1f,%d,%.4f,%.4f,%.4f" % [
		potential,
		age,
		float(state["effective_skill"]),
		float(state["skill_delta"]),
		float(state["potential_resistance"])
	]
	print(row)
	output_rows.append(row)

func _write_output() -> void:
	var output = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("Could not write POC-09 career diagnostic CSV: %s" % OUTPUT_PATH)
		quit(1)
		return
	for row in output_rows:
		output.store_line(row)
	output.close()
	print("Wrote POC-09 career diagnostic CSV: %s" % OUTPUT_PATH)
