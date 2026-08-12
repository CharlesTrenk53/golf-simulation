extends SceneTree

var failures: int = 0


func _init() -> void:
	print("POC-14G: shotmaking range visual diagnostic contract")
	var packed = load("res://scenes/shotmaking_range_demo.tscn")
	_assert_true(packed is PackedScene, "shotmaking range scene loads as a PackedScene")
	if packed is PackedScene:
		var instance = packed.instantiate()
		_assert_true(instance != null, "shotmaking range scene instantiates")
		if instance != null:
			_assert_true(instance.get_script() != null, "shotmaking range scene has its diagnostic script")
			instance.free()

	if failures == 0:
		print("POC-14G SHOTMAKING RANGE DEMO TESTS PASSED")
		quit(0)
	else:
		push_error("POC-14G SHOTMAKING RANGE DEMO TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
