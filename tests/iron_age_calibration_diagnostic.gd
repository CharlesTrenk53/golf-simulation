extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")

const START_AGE := 16
const END_AGE := 76
const CHECKPOINT_AGES := [16, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 76]
const STARTING_CAPACITIES := [50.0, 70.0, 90.0]
const APPROACH_SKILL := 70.0
const IRON_IDS := ["5_IRON", "7_IRON", "9_IRON"]

func _init() -> void:
	print("IRONAGECSV,start_capacity,club,age,approach_skill,power,mobility,coordination,endurance,physical_factor,carry,carry_change_from_16,pct_carry_change_from_16")
	for starting_capacity in STARTING_CAPACITIES:
		_run_trajectory(float(starting_capacity))
	print("POC-08 IRON AGE CALIBRATION DIAGNOSTIC COMPLETE")
	quit(0)

func _run_trajectory(starting_capacity: float) -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.age = START_AGE
	golfer.driving = APPROACH_SKILL
	golfer.approach = APPROACH_SKILL
	golfer.short_game = APPROACH_SKILL
	golfer.putting = APPROACH_SKILL
	golfer.physical_power = starting_capacity
	golfer.mobility = starting_capacity
	golfer.coordination = starting_capacity
	golfer.endurance = starting_capacity

	var lifecycle = GolferLifecycle.new()
	var bag = GolfBag.new()
	var irons: Dictionary = {}
	var carry_at_16: Dictionary = {}
	var peak_carry: Dictionary = {}
	var peak_age: Dictionary = {}

	for club_id in IRON_IDS:
		var iron: Dictionary = bag.get_club(club_id)
		irons[club_id] = iron
		var initial_carry: float = bag.effective_carry(iron, golfer, "FAIRWAY", 1.0)
		carry_at_16[club_id] = initial_carry
		peak_carry[club_id] = initial_carry
		peak_age[club_id] = START_AGE

	_record_if_checkpoint(golfer, bag, irons, starting_capacity, carry_at_16)
	while golfer.age < END_AGE:
		lifecycle.advance_year(golfer)
		for club_id in IRON_IDS:
			var current_carry: float = bag.effective_carry(irons[club_id], golfer, "FAIRWAY", 1.0)
			if current_carry > float(peak_carry[club_id]):
				peak_carry[club_id] = current_carry
				peak_age[club_id] = int(golfer.age)
		_record_if_checkpoint(golfer, bag, irons, starting_capacity, carry_at_16)

	for club_id in IRON_IDS:
		var carry_at_76: float = bag.effective_carry(irons[club_id], golfer, "FAIRWAY", 1.0)
		var initial_carry: float = float(carry_at_16[club_id])
		print("IRONAGESUMMARY,start_capacity=%.1f,club=%s,peak_age=%d,peak_carry=%.6f,carry_age_16=%.6f,carry_age_76=%.6f,pct_change_16_to_76=%.6f,pct_change_peak_to_76=%.6f" % [
			starting_capacity,
			club_id,
			int(peak_age[club_id]),
			float(peak_carry[club_id]),
			initial_carry,
			carry_at_76,
			((carry_at_76 - initial_carry) / initial_carry) * 100.0,
			((carry_at_76 - float(peak_carry[club_id])) / float(peak_carry[club_id])) * 100.0
		])
	golfer.free()

func _record_if_checkpoint(golfer: Node, bag, irons: Dictionary, starting_capacity: float, carry_at_16: Dictionary) -> void:
	if not CHECKPOINT_AGES.has(int(golfer.age)):
		return
	var physical_factor: float = golfer.physical_distance_factor(1)
	for club_id in IRON_IDS:
		var carry: float = bag.effective_carry(irons[club_id], golfer, "FAIRWAY", 1.0)
		var initial_carry: float = float(carry_at_16[club_id])
		var carry_change: float = carry - initial_carry
		var pct_change: float = (carry_change / initial_carry) * 100.0
		print("IRONAGECSV,%.1f,%s,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
			starting_capacity,
			club_id,
			int(golfer.age),
			float(golfer.approach),
			float(golfer.physical_power),
			float(golfer.mobility),
			float(golfer.coordination),
			float(golfer.endurance),
			physical_factor,
			carry,
			carry_change,
			pct_change
		])
