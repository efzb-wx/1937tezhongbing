extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var mobile := root.get_node("MobileContent")
	_expect(await mobile.prepare_content(), "Bundled content extracts into the app sandbox")
	var paths: Script = preload("res://scripts/mobile_content.gd")
	var levels: Script = preload("res://scripts/imported_level_data.gd")
	for index: int in range(12):
		_expect(not levels.load_level("m%03d" % index).is_empty(), "Mission %d loads from the sandbox" % index)
	var content_root: String = paths.resolve("res://../LocalAssets/converted")
	var validation: Dictionary = preload("res://scripts/content_package_validator.gd").validate(
		content_root.get_base_dir().path_join("content-manifest.json"), content_root,
		"repository-mod-12-level-20260729", false,
	)
	_expect(bool(validation.get("ok", false)), "Portable content integrity passes after extraction")
	var main = preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	await process_frame
	_expect(main.terrain_loaded, "First mission terrain loads")
	_expect(not main.units.is_empty(), "First mission player units load")
	mobile.pointer_button = MOUSE_BUTTON_MIDDLE
	main._unhandled_input(_touch_mouse(true))
	_expect(main.camera_dragging, "Touch pan mode begins camera dragging")
	main._unhandled_input(_touch_mouse(false))
	_expect(not main.camera_dragging, "Touch pan mode releases camera dragging")
	mobile.pointer_button = MOUSE_BUTTON_RIGHT
	main._unhandled_input(_touch_mouse(true))
	_expect(main.right_dragging, "Touch selection mode begins a selection box")
	main._unhandled_input(_touch_mouse(false))
	_expect(not main.right_dragging, "Touch selection mode releases the selection box")
	main.clear_selection()
	mobile._send_key(KEY_F4, true)
	mobile._send_key(KEY_F4, false)
	await process_frame
	_expect(main.selected_units.size() == 1, "Touch toolbar key selects a player through the game input pipeline")
	var previous_zoom: float = main.level_camera.zoom.x
	mobile._zoom(MOUSE_BUTTON_WHEEL_DOWN)
	await process_frame
	_expect(main.level_camera.zoom.x < previous_zoom, "Touch zoom button changes the world camera zoom")
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("Mobile port tests passed: 12 missions, content integrity, terrain, units, touch pan/selection, toolbar selection")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _touch_mouse(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(640, 260)
	event.pressed = pressed
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
