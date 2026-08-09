extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")
const CourseContext = preload("res://simulation/course_context.gd")

const RUNS_PER_GOLFER := 1000
const START_POSITION := Vector3(0, 0.9, 55)
const HOLE_POSITION := Vector3(0, 0.55, -55)
const PAR := 4

var hazards: Array = [{"name": "Water", "position": Vector3(0, 0.25, 5), "radius": 10.0, "risk": 90.0}]
var profiles: Array = [
	{"profile": 0, "name": "Wild Bill"},
	{"profile": 1, "name": "Reckless Rick"},
	{"profile": 2, "name": "Careful Carl"}
]


func _init() -> void:
	print("============================================================")
	print("POC-07 CLUB-AWARE MONTE CARLO GOLFER SIMULATION")
	print("Runs per golfer: ", RUNS_PER_GOLFER)
	print("Same course context; seeds 1 through ", RUNS_PER_GOLFER)
	print("============================================================")
	for profile_data in profiles:
		_print_summary(_run_profile(profile_data["profile"], profile_data["name"]))
	print("POC-07 MONTE CARLO COMPLETE")
	quit(0)


func _build_course_context():
	var context = CourseContext.new()
	context.add_zone("Fairway", CourseContext.Surface.FAIRWAY, Vector3(0, 0, 5), Vector2(11, 45))
	context.add_zone("Tee", CourseContext.Surface.TEE, START_POSITION, Vector2(8, 5))
	context.add_zone("Green", CourseContext.Surface.GREEN, HOLE_POSITION, Vector2(14, 11))
	context.add_zone("Front Bunker", CourseContext.Surface.BUNKER, Vector3(11, 0, -39), Vector2(6, 7))
	context.add_zone("Water", CourseContext.Surface.WATER, Vector3(0, 0, 5), Vector2(16, 6))
	return context


func _run_profile(profile_value: int, profile_name: String) -> Dictionary:
	var strokes: Array[int] = []
	var finished_count := 0
	var total_water := 0
	var total_shots := 0
	var option_counts := {}
	var club_counts := {}
	var surface_counts := {}
	var score_counts := {}

	for run_number in range(1, RUNS_PER_GOLFER + 1):
		var golfer = QuietGolfer.new()
		golfer.profile = profile_value
		golfer.apply_profile()
		var simulation = AutonomousHole.new()
		var result = simulation.play_hole(golfer, START_POSITION, HOLE_POSITION, hazards, PAR, run_number, _build_course_context())
		var score: int = result["strokes"]
		strokes.append(score)
		if result["finished"]:
			finished_count += 1
		total_water += golfer.water_balls
		for shot in result["history"]:
			total_shots += 1
			var option_name: String = shot["option"]
			option_counts[option_name] = int(option_counts.get(option_name, 0)) + 1
			var club_name: String = shot.get("club_name", "UNASSIGNED")
			if club_name.is_empty():
				club_name = "UNASSIGNED"
			club_counts[club_name] = int(club_counts.get(club_name, 0)) + 1
			var surface_name: String = shot["surface_after"]
			surface_counts[surface_name] = int(surface_counts.get(surface_name, 0)) + 1
		score_counts[score] = int(score_counts.get(score, 0)) + 1
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
		"total_shots": total_shots,
		"option_counts": option_counts,
		"club_counts": club_counts,
		"surface_counts": surface_counts,
		"score_counts": score_counts
	}


func _mean(values: Array[int]) -> float:
	var total := 0
	for value in values:
		total += value
	return float(total) / values.size()


func _percentile(values: Array[int], proportion: float) -> int:
	var index = int(round((values.size() - 1) * proportion))
	return values[clamp(index, 0, values.size() - 1)]


func _rate(counts: Dictionary, name: String, total: int) -> float:
	if total == 0:
		return 0.0
	return float(counts.get(name, 0)) / total * 100.0


func _score_percent(score_counts: Dictionary, score: int) -> float:
	return float(score_counts.get(score, 0)) / RUNS_PER_GOLFER * 100.0


func _score_5_plus(score_counts: Dictionary) -> float:
	var count := 0
	for score in score_counts.keys():
		if int(score) >= 5:
			count += int(score_counts[score])
	return float(count) / RUNS_PER_GOLFER * 100.0


func _print_summary(summary: Dictionary) -> void:
	var options: Dictionary = summary["option_counts"]
	var clubs: Dictionary = summary["club_counts"]
	var surfaces: Dictionary = summary["surface_counts"]
	var total: int = summary["total_shots"]
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
	print("-- Decisions --")
	for option_name in ["ATTACK", "LAYUP", "BAILOUT", "ADVANCE_FROM_ROUGH", "BUNKER_EXIT", "SPLASH_OUT", "SAFE_BUNKER_EXIT", "PITCH", "SAFE_PITCH", "PUTT"]:
		var count: int = int(options.get(option_name, 0))
		if count > 0:
			print("%s: %.1f%% (%d)" % [option_name, _rate(options, option_name, total), count])
	print("-- Clubs --")
	for club_name in ["Driver", "3 Wood", "5 Iron", "7 Iron", "9 Iron", "Pitching Wedge", "Sand Wedge", "Putter", "UNASSIGNED"]:
		var count: int = int(clubs.get(club_name, 0))
		if count > 0:
			print("%s: %.1f%% (%d)" % [club_name, _rate(clubs, club_name, total), count])
	print("-- Landing surfaces --")
	for surface_name in ["TEE", "FAIRWAY", "ROUGH", "BUNKER", "GREEN", "WATER"]:
		var count: int = int(surfaces.get(surface_name, 0))
		if count > 0:
			print("%s: %.1f%% (%d)" % [surface_name, _rate(surfaces, surface_name, total), count])
