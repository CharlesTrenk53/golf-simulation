extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")

const START_AGE := 16
const END_AGE := 76
const CHECKPOINT_AGES := [16, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 76]
const STARTING_CAPACITIES := [50.0, 70.0, 90.0]
const FIXED_SKILL := 70.0
const CLUB_IDS := [
	"DRIVER", "3_WOOD", "5_WOOD", "4_HYBRID", "4_IRON",
	"5_IRON", "7_IRON", "9_IRON", "PITCHING_WEDGE", "SAND_WEDGE", "PUTTER"
]

func _init() -> void:
	print("BAGAGECSV,start_capacity,club,family,physical_sensitivity,forgiveness,age,power,mobility,coordination,endurance,carry,pct_carry_change_from_16")
	for starting_capacity in STARTING_CAPACITIES:
		_run_trajectory(float(starting_capacity))
	print("POC-08 FULL BAG AGE CALIBRATION DIAGNOSTIC COMPLETE")
	quit(0)


func _run_trajectory(starting_capacity: float) -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.age = START_AGE
	golfer.driving = FIXED_SKILL
	golfer.approach = FIXED_SKILL
	golfer.short_game = FIXED_SKILL
	golfer.putting = FIXED_SKILL
	golfer.physical_power = starting_capacity
	golfer.mobility = starting_capacity
	golfer.coordination = starting_capacity
	golfer.endurance = starting_capacity

	var lifecycle = GolferLifecycle.new()
	var bag = GolfBag.new()
	var selected: Dictionary = {}
	var carry_at_16: Dictionary = {}
	var peak_carry: Dictionary = {}
	var peak_age: Dictionary = {}

	for club_id in CLUB_IDS:
		var club: Dictionary = bag.get_club(club_id)
		selected[club_id] = club
		var surface := _surface_for(club_id)
		var initial_carry: float = bag.effective_carry(club, golfer, surface, 1.0)
		carry_at_16[club_id] = initial_carry
		peak_carry[club_id] = initial_carry
		peak_age[club_id] = START_AGE

	_record_if_checkpoint(golfer, bag, selected, starting_capacity, carry_at_16)
	while golfer.age < END_AGE:
		lifecycle.advance_year(golfer)
		for club_id in CLUB_IDS:
			var club: Dictionary = selected[club_id]
			var current_carry: float = bag.effective_carry(club, golfer, _surface_for(club_id), 1.0)
			if current_carry > float(peak_carry[club_id]):
				peak_carry[club_id] = current_carry
				peak_age[club_id] = int(golfer.age)
		_record_if_checkpoint(golfer, bag, selected, starting_capacity, carry_at_16)

	for club_id in CLUB_IDS:
		var club: Dictionary = selected[club_id]
		var carry_at_76: float = bag.effective_carry(club, golfer, _surface_for(club_id), 1.0)
		var initial_carry: float = float(carry_at_16[club_id])
		print("BAGAGESUMMARY,start_capacity=%.1f,club=%s,family=%s,sensitivity=%.2f,forgiveness=%.2f,peak_age=%d,peak_carry=%.6f,carry_age_16=%.6f,carry_age_76=%.6f,pct_change_16_to_76=%.6f,pct_change_peak_to_76=%.6f" % [
			starting_capacity,
			club_id,
			String(club["family"]),
			float(club["physical_sensitivity"]),
			float(club["forgiveness"]),
			int(peak_age[club_id]),
			float(peak_carry[club_id]),
			initial_carry,
			carry_at_76,
			((carry_at_76 - initial_carry) / initial_carry) * 100.0,
			((carry_at_76 - float(peak_carry[club_id])) / float(peak_carry[club_id])) * 100.0
		])
	golfer.free()


func _record_if_checkpoint(golfer: Node, bag, selected: Dictionary, starting_capacity: float, carry_at_16: Dictionary) -> void:
	if not CHECKPOINT_AGES.has(int(golfer.age)):
		return
	for club_id in CLUB_IDS:
		var club: Dictionary = selected[club_id]
		var carry: float = bag.effective_carry(club, golfer, _surface_for(club_id), 1.0)
		var initial_carry: float = float(carry_at_16[club_id])
		var pct_change: float = ((carry - initial_carry) / initial_carry) * 100.0
		print("BAGAGECSV,%.1f,%s,%s,%.2f,%.2f,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
			starting_capacity,
			club_id,
			String(club["family"]),
			float(club["physical_sensitivity"]),
			float(club["forgiveness"]),
			int(golfer.age),
			float(golfer.physical_power),
			float(golfer.mobility),
			float(golfer.coordination),
			float(golfer.endurance),
			carry,
			pct_change
		])


func _surface_for(club_id: String) -> String:
	if club_id == "DRIVER":
		return "TEE"
	if club_id == "PUTTER":
		return "GREEN"
	return "FAIRWAY"
