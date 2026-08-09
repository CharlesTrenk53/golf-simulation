extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")

const RUNS_PER_GOLFER := 1000
const START_POSITION := Vector3(0, 0.9, 55)
const HOLE_POSITION := Vector3(0, 0.55, -55)
const PAR := 4

var hazards: Array = [
	{
		"name": "Water",
		"position": Vector3(0, 0.25, 5),
		"radius": 10.0,
		"risk": 90.0
	}
]

var profiles: Array = [
	{"profile": 0, "name": "Wild Bill"},
	{"profile": 1, "name": "Reckless Rick"},
	{"profile": 2, "name": "Careful Carl"}
]


func _init() -> void:
	print("============================================================")
	print("POC-05F MONTE CARLO GOLFER SIMULATION")
	print("Runs per golfer: ", RUNS_PER_GOLFER)
	print("Same hole geometry; seeds 1 through ", RUNS_PER_GOLFER)
	print("============================================================")

	for profile_data in profiles:
		var summary = _run_profile(
			profile_data["profile"],
			profile_data["name"]
		)
		_print_summary(summary)

	print("POC-05F MONTE CARLO COMPLETE")
	quit(0)


func _run_profile(profile_value: int, profile_name: String) -> Dictionary:
	var strokes: Array[int] = []
	var finished_count: int = 0
	var total_water: int = 0
	var total_shots: int = 0
	var option_counts := {
		"ATTACK": 0,
		"LAYUP": 0,
		"BAILOUT": 0,
		"PITCH": 0,
		"SAFE_PITCH": 0,
		"PUTT": 0
	}
	var score_counts := {}

	for run_number in range(1, RUNS_PER_GOLFER + 1):
		var golfer = QuietGolfer.new()
		golfer.profile = profile_value
		golfer.apply_profile()

		var simulation = AutonomousHole.new()
		var result = simulation.play_hole(
			golfer,
			START_POSITION,
			HOLE_POSITION,
			hazards,
			PAR,
			run_number
		)

		var score: int = result["strokes"]
		strokes.append(score)
		if result["finished"]:
			finished_count += 1
		total_water += golfer.water_balls

		for shot in result["history"]:
			total_shots += 1
			var option_name: String = shot["option"]
			if not option_counts.has(option_name):
				option_counts[option_name] = 0
			option_counts[option_name] += 1

		if not score_counts.has(score):
			score_counts[score] = 0
		score_counts[score] += 1
		golfer.free()

	strokes.sort()

	return {
		"name": profile_name,
		"mean": _mean(strokes),
		"median": _percentile(strokes, 0.50),
		"p95": _percentile(strokes, 0.95),
		"best": strokes.front(),
		"worst": strokes.back(),
		"finish_rate": float(finished_count) / RUNS_PER_GOLFER * 100.0,
		"water_per_hole": float(total_water) / RUNS_PER_GOLFER,
		"attack_rate": _option_rate(option_counts, "ATTACK", total_shots),
		"layup_rate": _option_rate(option_counts, "LAYUP", total_shots),
		"bailout_rate": _option_rate(option_counts, "BAILOUT", total_shots),
		"pitch_rate": _option_rate(option_counts, "PITCH", total_shots),
		"putt_rate": _option_rate(option_counts, "PUTT", total_shots),
		"score_counts": score_counts
	}


func _mean(values: Array[int]) -> float:
	var total: int = 0
	for value in values:
		total += value
	return float(total) / values.size()


func _percentile(values: Array[int], proportion: float) -> int:
	var index = int(round((values.size() - 1) * proportion))
	return values[clamp(index, 0, values.size() - 1)]


func _option_rate(counts: Dictionary, option_name: String, total: int) -> float:
	if total == 0:
		return 0.0
	return float(counts.get(option_name, 0)) / total * 100.0


func _score_percent(score_counts: Dictionary, score: int) -> float:
	return float(score_counts.get(score, 0)) / RUNS_PER_GOLFER * 100.0


func _print_summary(summary: Dictionary) -> void:
	print("")
	print("-------------------- ", summary["name"], " --------------------")
	print("Mean strokes: %.3f" % summary["mean"])
	print("Median strokes: ", summary["median"])
	print("Best score: ", summary["best"])
	print("Worst score: ", summary["worst"])
	print("P95 strokes: ", summary["p95"])
	print("Finished holes: %.1f%%" % summary["finish_rate"])
	print("Water balls per hole: %.3f" % summary["water_per_hole"])
	print("Score 2: %.1f%%" % _score_percent(summary["score_counts"], 2))
	print("Score 3: %.1f%%" % _score_percent(summary["score_counts"], 3))
	print("Score 4: %.1f%%" % _score_percent(summary["score_counts"], 4))
	print("Score 5+: %.1f%%" % _score_5_plus(summary["score_counts"]))
	print("Attack rate: %.1f%%" % summary["attack_rate"])
	print("Layup rate: %.1f%%" % summary["layup_rate"])
	print("Bailout rate: %.1f%%" % summary["bailout_rate"])
	print("Pitch rate: %.1f%%" % summary["pitch_rate"])
	print("Putt rate: %.1f%%" % summary["putt_rate"])


func _score_5_plus(score_counts: Dictionary) -> float:
	var count: int = 0
	for score in score_counts.keys():
		if int(score) >= 5:
			count += int(score_counts[score])
	return float(count) / RUNS_PER_GOLFER * 100.0
