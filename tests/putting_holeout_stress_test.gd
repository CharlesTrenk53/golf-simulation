extends SceneTree

const PuttingPipeline = preload("res://simulation/putting_pipeline.gd")

const START_DISTANCES_FEET: Array[float] = [10.0, 20.0, 30.0, 40.0]
const ABILITY_LEVELS: Array[float] = [30.0, 50.0, 70.0, 85.0, 95.0]
const TRIALS_PER_CELL: int = 1200
const MAX_PUTTS_PER_TRIAL: int = 8

class StressGolfer:
	extends Node
	var putting: float = 70.0
	var coordination: float = 75.0
	var confidence: float = 70.0
	var risk_tolerance: float = 50.0

	func get_shot_ability(shot_type: int) -> float:
		if shot_type == 3:
			return putting
		return 50.0

var failures: int = 0
var pipeline = PuttingPipeline.new()


func _init() -> void:
	print("POC-15G: multi-putt hole-out stress test")
	print("Trials per ability-distance cell: %d" % TRIALS_PER_CELL)
	print("Conditions: level green, speed 10.0; neutral personality; continue until holed")
	print("")

	var rows: Array = []
	for ability in ABILITY_LEVELS:
		var golfer := StressGolfer.new()
		golfer.putting = ability
		get_root().add_child(golfer)
		for distance in START_DISTANCES_FEET:
			rows.append(_simulate_holeout_cell(golfer, ability, distance, int(ability * 100000.0 + distance * 1000.0)))
		golfer.queue_free()

	_print_summary(rows)
	_validate_behavior(rows)

	if failures == 0:
		print("")
		print("POC-15G PUTTING HOLE-OUT STRESS TEST COMPLETED")
		quit(0)
	else:
		push_error("POC-15G PUTTING HOLE-OUT STRESS TEST FAILED: %d" % failures)
		quit(1)


func _simulate_holeout_cell(golfer: Node, ability: float, start_distance: float, seed_base: int) -> Dictionary:
	var one_putts: int = 0
	var two_putts: int = 0
	var three_putts: int = 0
	var four_plus_putts: int = 0
	var total_putts: int = 0
	var capped_trials: int = 0
	var second_putt_distance_total: float = 0.0
	var second_putt_samples: int = 0

	for trial in range(TRIALS_PER_CELL):
		var distance: float = start_distance
		var putts: int = 0
		var holed: bool = false

		while not holed and putts < MAX_PUTTS_PER_TRIAL:
			var seed_value: int = seed_base + trial * 31 + putts * 1000003
			var result: Dictionary = pipeline.resolve(golfer, distance, seed_value, 0.0, 0.0, 10.0)
			putts += 1
			holed = bool(result.get("holed", false))
			if not holed:
				distance = maxf(0.0, float(result.get("finish_distance_from_hole_feet", 0.0)))
				if putts == 1:
					second_putt_distance_total += distance
					second_putt_samples += 1

		if not holed:
			capped_trials += 1

		total_putts += putts
		match putts:
			1: one_putts += 1
			2: two_putts += 1
			3: three_putts += 1
			_: four_plus_putts += 1

	var trials: float = float(TRIALS_PER_CELL)
	return {
		"ability": ability,
		"start_distance_feet": start_distance,
		"avg_putts": float(total_putts) / trials,
		"one_putt_pct": float(one_putts) / trials * 100.0,
		"two_putt_pct": float(two_putts) / trials * 100.0,
		"three_putt_pct": float(three_putts) / trials * 100.0,
		"four_plus_putt_pct": float(four_plus_putts) / trials * 100.0,
		"avg_second_putt_feet": second_putt_distance_total / maxf(float(second_putt_samples), 1.0),
		"capped_pct": float(capped_trials) / trials * 100.0
	}


func _print_summary(rows: Array) -> void:
	print("=== HOLE-OUT SUMMARY ===")
	print("ability,start_distance_ft,avg_putts,one_putt_pct,two_putt_pct,three_putt_pct,four_plus_putt_pct,avg_second_putt_ft,capped_pct")
	for row in rows:
		print("%.0f,%.0f,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [
			float(row["ability"]),
			float(row["start_distance_feet"]),
			float(row["avg_putts"]),
			float(row["one_putt_pct"]),
			float(row["two_putt_pct"]),
			float(row["three_putt_pct"]),
			float(row["four_plus_putt_pct"]),
			float(row["avg_second_putt_feet"]),
			float(row["capped_pct"])
		])
	print("")


func _validate_behavior(rows: Array) -> void:
	for distance in START_DISTANCES_FEET:
		var low: Dictionary = _find_row(rows, 30.0, distance)
		var high: Dictionary = _find_row(rows, 95.0, distance)
		_expect(float(high["avg_putts"]) <= float(low["avg_putts"]), "ability 95 averages no more putts than ability 30 from %.0f ft" % distance)
		_expect(float(high["one_putt_pct"]) >= float(low["one_putt_pct"]), "ability 95 one-putt rate is at least ability 30 from %.0f ft" % distance)
		_expect(float(high["three_putt_pct"]) + float(high["four_plus_putt_pct"]) <= float(low["three_putt_pct"]) + float(low["four_plus_putt_pct"]) + 0.50, "ability 95 creates no more 3+ putts than ability 30 from %.0f ft" % distance)

	var skill_70_10: Dictionary = _find_row(rows, 70.0, 10.0)
	var skill_70_20: Dictionary = _find_row(rows, 70.0, 20.0)
	var skill_70_40: Dictionary = _find_row(rows, 70.0, 40.0)
	_expect(float(skill_70_10["avg_putts"]) < float(skill_70_20["avg_putts"]), "average putts rise from 10 ft to 20 ft")
	_expect(float(skill_70_20["avg_putts"]) < float(skill_70_40["avg_putts"]), "average putts rise from 20 ft to 40 ft")
	_expect(float(skill_70_40["three_putt_pct"]) > float(skill_70_10["three_putt_pct"]), "40-foot starts produce more three-putts than 10-foot starts")

	var worst_cap: float = 0.0
	for row in rows:
		worst_cap = maxf(worst_cap, float(row["capped_pct"]))
	_expect(worst_cap <= 0.25, "virtually all trials hole out within the safety cap")


func _find_row(rows: Array, ability: float, distance: float) -> Dictionary:
	for row in rows:
		if absf(float(row["ability"]) - ability) < 0.001 and absf(float(row["start_distance_feet"]) - distance) < 0.001:
			return row
	return {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
