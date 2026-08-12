extends SceneTree

const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotIntent = preload("res://simulation/shot_intent.gd")
const ShotIntentCatalog = preload("res://simulation/shot_intent_catalog.gd")

var failures: int = 0


func _init() -> void:
	print("POC-14A: composable shot intent feasibility")
	var bag = GolfBag.new()
	var catalog = ShotIntentCatalog.new()

	var driver: Dictionary = bag.get_club("DRIVER")
	var seven_iron: Dictionary = bag.get_club("7_IRON")
	var lob_wedge: Dictionary = bag.get_club("LOB_WEDGE")
	var sand_wedge: Dictionary = bag.get_club("SAND_WEDGE")
	var putter: Dictionary = bag.get_club("PUTTER")

	var driver_intents: Array[Dictionary] = catalog.intents_for(driver, "TEE")
	_assert_true(_has(driver_intents, "NORMAL|STRAIGHT|FULL|STOCK"), "driver has stock shot")
	_assert_true(_has(driver_intents, "NORMAL|DRAW|FULL|STOCK"), "driver can intentionally draw")
	_assert_true(_has(driver_intents, "NORMAL|FADE|FULL|STOCK"), "driver can intentionally fade")
	_assert_true(_has(driver_intents, "LOW|STRAIGHT|FULL|STOCK"), "driver can intentionally flight the ball low")
	_assert_true(_has(driver_intents, "HIGH|STRAIGHT|FULL|STOCK"), "driver can intentionally flight the ball high")
	_assert_true(_has(driver_intents, "LOW|STRAIGHT|FULL|STINGER"), "driver can attempt a stinger")
	_assert_true(not _technique_seen(driver_intents, ShotIntent.Technique.FLOP), "driver does not receive wedge-only flop technique")
	_assert_true(not _technique_seen(driver_intents, ShotIntent.Technique.BUNKER), "driver does not receive bunker technique")

	var iron_intents: Array[Dictionary] = catalog.intents_for(seven_iron, "FAIRWAY")
	_assert_true(_has(iron_intents, "LOW|STRAIGHT|THREE_QUARTER|PUNCH"), "7 iron supports controlled knockdown/punch construction")
	_assert_true(_has(iron_intents, "NORMAL|DRAW|FULL|STOCK"), "7 iron supports intentional shape")

	var wedge_intents: Array[Dictionary] = catalog.intents_for(lob_wedge, "ROUGH")
	_assert_true(_has(wedge_intents, "NORMAL|STRAIGHT|THREE_QUARTER|PITCH"), "lob wedge supports three-quarter pitch")
	_assert_true(_has(wedge_intents, "NORMAL|STRAIGHT|HALF|PITCH"), "lob wedge supports half pitch")
	_assert_true(_has(wedge_intents, "HIGH|STRAIGHT|TOUCH|FLOP"), "lob wedge supports high touch flop")
	_assert_true(_has(wedge_intents, "LOW|STRAIGHT|TOUCH|BUMP_AND_RUN"), "lob wedge supports low bump-and-run intent")

	var bunker_intents: Array[Dictionary] = catalog.intents_for(sand_wedge, "BUNKER")
	_assert_true(_has(bunker_intents, "HIGH|STRAIGHT|TOUCH|BUNKER"), "sand wedge supports dedicated bunker technique from sand")
	_assert_true(not _technique_seen(bunker_intents, ShotIntent.Technique.FLOP), "bunker lie does not masquerade as generic flop")

	var putter_intents: Array[Dictionary] = catalog.intents_for(putter, "GREEN")
	_assert_true(putter_intents.is_empty(), "putting remains separate from full-shot intent catalog")

	_assert_unique(driver_intents, "driver intent signatures are unique")
	_assert_unique(wedge_intents, "wedge intent signatures are unique")

	if failures == 0:
		print("POC-14A SHOT INTENT CATALOG TESTS PASSED")
		quit(0)
	else:
		push_error("POC-14A SHOT INTENT CATALOG TESTS FAILED: %d" % failures)
		quit(1)


func _has(intents: Array[Dictionary], signature: String) -> bool:
	for intent in intents:
		if str(intent.get("signature", "")) == signature:
			return true
	return false


func _technique_seen(intents: Array[Dictionary], technique: int) -> bool:
	for intent in intents:
		if int(intent.get("technique", -1)) == technique:
			return true
	return false


func _assert_unique(intents: Array[Dictionary], label: String) -> void:
	var seen: Dictionary = {}
	for intent in intents:
		seen[str(intent.get("signature", ""))] = true
	_assert_true(seen.size() == intents.size(), label)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
