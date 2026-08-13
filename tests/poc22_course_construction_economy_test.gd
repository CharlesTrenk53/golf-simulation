extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const CourseConstructionEconomy = preload("res://simulation/course_construction_economy.gd")

var failures: int = 0


func _init() -> void:
	print("POC-22B: course construction economy")
	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(6, 4, 5.0), "construction grid configures")

	var economy = CourseConstructionEconomy.new()
	_assert_true(economy.configure(grid, 500), "economy configures with starting cash")
	_assert_equal(economy.cash_balance, 500, "starting cash preserved")

	var fairway_quote: Dictionary = economy.quote_surface_change(1, 1, "fairway")
	_assert_true(bool(fairway_quote.get("valid", false)), "fairway construction can be quoted")
	_assert_equal(int(fairway_quote.get("cost", -1)), 80, "fairway quote uses deterministic tile price")
	_assert_true(bool(fairway_quote.get("affordable", false)), "affordable quote is identified")

	var fairway_build: Dictionary = economy.build_surface(1, 1, "FAIRWAY")
	_assert_true(bool(fairway_build.get("built", false)), "affordable fairway is constructed")
	_assert_equal(grid.surface_at(1, 1), "FAIRWAY", "paid construction updates authoritative grid")
	_assert_equal(economy.cash_balance, 420, "construction deducts cash")
	_assert_equal(economy.lifetime_construction_spend, 80, "construction spend accumulates")

	var duplicate_build: Dictionary = economy.build_surface(1, 1, "FAIRWAY")
	_assert_true(bool(duplicate_build.get("built", false)), "reapplying existing surface is a valid no-op")
	_assert_equal(int(duplicate_build.get("cost", -1)), 0, "existing surface costs nothing to retain")
	_assert_equal(economy.cash_balance, 420, "no-op construction does not charge twice")

	var water_build: Dictionary = economy.build_surface(2, 1, "WATER")
	_assert_true(bool(water_build.get("built", false)), "water can be constructed when affordable")
	_assert_equal(economy.cash_balance, 160, "water construction deducts its price")

	var green_build: Dictionary = economy.build_surface(3, 1, "GREEN")
	_assert_true(not bool(green_build.get("built", false)), "unaffordable construction is rejected")
	_assert_equal(str(green_build.get("reason", "")), "INSUFFICIENT_FUNDS", "rejection explains insufficient funds")
	_assert_equal(grid.surface_at(3, 1), "ROUGH", "rejected construction leaves grid unchanged")
	_assert_equal(economy.cash_balance, 160, "rejected construction leaves cash unchanged")

	_assert_true(economy.add_revenue(200, "GREEN_FEES"), "course revenue can replenish construction cash")
	_assert_equal(economy.cash_balance, 360, "revenue increases cash")
	var green_after_revenue: Dictionary = economy.build_surface(3, 1, "GREEN")
	_assert_true(bool(green_after_revenue.get("built", false)), "previously unaffordable green can be built after revenue")
	_assert_equal(economy.cash_balance, 140, "green construction charges after revenue")
	_assert_equal(economy.lifetime_construction_spend, 560, "lifetime spend tracks all paid construction")

	var bad_quote: Dictionary = economy.quote_surface_change(99, 99, "TEE")
	_assert_true(not bool(bad_quote.get("valid", true)), "out-of-bounds quote is rejected")
	_assert_equal(str(bad_quote.get("reason", "")), "OUT_OF_BOUNDS", "out-of-bounds quote has reason")

	var saved: Dictionary = economy.to_dictionary()
	var restored = CourseConstructionEconomy.from_dictionary(saved)
	_assert_true(restored != null, "economy round-trips through save data")
	if restored != null:
		_assert_equal(restored.cash_balance, 140, "restored cash survives serialization")
		_assert_equal(restored.lifetime_construction_spend, 560, "restored spend survives serialization")
		_assert_equal(restored.grid.surface_at(1, 1), "FAIRWAY", "restored grid preserves fairway")
		_assert_equal(restored.grid.surface_at(2, 1), "WATER", "restored grid preserves water")
		_assert_equal(restored.grid.surface_at(3, 1), "GREEN", "restored grid preserves green")
		_assert_equal(restored.transaction_history.size(), economy.transaction_history.size(), "transaction history survives serialization")

	print("POC22_ECONOMY_SUMMARY balance=%d spent=%d transactions=%d" % [
		economy.cash_balance,
		economy.lifetime_construction_spend,
		economy.transaction_history.size()
	])
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-22B COURSE CONSTRUCTION ECONOMY PASSED")
		quit(0)
	else:
		push_error("POC-22B COURSE CONSTRUCTION ECONOMY FAILED: %d" % failures)
		quit(1)
