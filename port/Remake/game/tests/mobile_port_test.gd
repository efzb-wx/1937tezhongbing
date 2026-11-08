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
	_expect(is_equal_approx(main.level_camera.zoom.x, 1.28), "New missions start at 128 percent zoom")
	_expect(mobile.speed_percent == 60 and is_equal_approx(SquadUnit.mobile_movement_scale, 0.6), "New missions start at 60 percent movement speed")
	mobile.pointer_button = MOUSE_BUTTON_MIDDLE
	_screen_touch(5, Vector2(640, 260), true)
	_expect(main.camera_dragging, "Touch pan mode begins camera dragging")
	_screen_touch(5, Vector2(640, 260), false)
	_expect(not main.camera_dragging, "Touch pan mode releases camera dragging")
	mobile.pointer_button = MOUSE_BUTTON_RIGHT
	_screen_touch(5, Vector2(640, 260), true)
	_expect(main.right_dragging, "Touch selection mode begins a selection box")
	_screen_touch(5, Vector2(640, 260), false)
	_expect(not main.right_dragging, "Touch selection mode releases the selection box")
	mobile.pointer_button = MOUSE_BUTTON_LEFT
	main.level_camera.position = main.world_size * 0.5
	main.clamp_level_camera()
	main.level_camera.force_update_scroll()
	await process_frame
	var camera_before: Vector2 = main.level_camera.position
	var gesture_zoom: Vector2 = main.level_camera.zoom
	var gesture_commands: Array = []
	main.command_bus.command_issued.connect(func(command: Dictionary) -> void: gesture_commands.append(command))
	_screen_touch(5, Vector2(500, 260), true)
	main._unhandled_input(_touch_mouse(true))
	_expect(gesture_commands.is_empty(), "First finger and emulated mouse do not prematurely issue an order")
	_screen_touch(11, Vector2(700, 260), true)
	_screen_drag(5, Vector2(532, 284))
	_screen_drag(11, Vector2(732, 284))
	_expect(main.level_camera.position.is_equal_approx(camera_before - Vector2(32, 24) / gesture_zoom), "Two fingers pan horizontally and vertically using their centroid and camera zoom")
	_expect(main.level_camera.zoom == gesture_zoom, "Two-finger pan keeps the zoom unchanged")
	_screen_drag(5, Vector2(500, 260))
	_screen_drag(11, Vector2(700, 260))
	_expect(main.level_camera.position.is_equal_approx(camera_before), "Two fingers can also pan back up and left")
	_screen_touch(11, Vector2(700, 260), false)
	var after_pan: Vector2 = main.level_camera.position
	_screen_drag(5, Vector2(550, 300))
	_screen_touch(5, Vector2(550, 300), false)
	main._unhandled_input(_touch_mouse(false))
	_expect(main.level_camera.position == after_pan, "Lifting one finger cannot continue a two-finger pan")
	_expect(gesture_commands.is_empty(), "Two-finger pan and staggered release issue no world orders")
	_expect(mobile.touch_positions.is_empty(), "All contacts release the gesture")
	# Place the selection fixture away from map-edge clamping and the toolbar.
	main.units[0].position = main.world_size * 0.5
	main.level_camera.position = main.units[0].position
	main.clamp_level_camera()
	main.level_camera.force_update_scroll()
	await process_frame
	main.clear_selection()
	var unit_screen: Vector2 = main.get_global_transform_with_canvas() * main.units[0].position
	_screen_touch(3, unit_screen, true)
	_screen_touch(3, unit_screen, false)
	_expect(main.selected_units.size() == 1, "A normal one-finger tap still selects a player after a two-finger gesture")
	main.clear_selection()
	var selection_origin := unit_screen - Vector2(50, 50)
	var selection_end := unit_screen + Vector2(50, 50)
	_screen_touch(8, selection_origin, true)
	await create_timer(0.8, true, false, true).timeout
	_expect(not main.right_dragging, "Holding less than one second does not begin a selection box")
	await create_timer(0.25, true, false, true).timeout
	_expect(main.right_dragging and mobile.long_press_selection, "One-second stationary hold enters selection mode")
	_screen_drag(8, selection_end)
	_screen_touch(8, selection_end, false)
	_expect(main.selected_units.size() == 1 and not main.right_dragging, "Long-press drag and release box-selects the player")
	_expect(mobile.pointer_button == MOUSE_BUTTON_LEFT, "Long-press selection does not change the toolbar mode")
	_validate_movement_speed(mobile)
	main.clear_selection()
	mobile._send_key(KEY_F4, true)
	mobile._send_key(KEY_F4, false)
	await process_frame
	_expect(main.selected_units.size() == 1, "Touch toolbar key selects a player through the game input pipeline")
	var previous_zoom: float = main.level_camera.zoom.x
	mobile._zoom(MOUSE_BUTTON_WHEEL_DOWN)
	await process_frame
	_expect(main.level_camera.zoom.x < previous_zoom, "Touch zoom button changes the world camera zoom")
	mobile.set_speed_percent(30)
	main.switch_level(0, false, false)
	_expect(mobile.speed_percent == 60, "Reopening a mission resets movement speed to 60 percent")
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("Mobile port tests passed: 12 missions, 128% zoom, two-finger pan, one-second long-press selection, 30%-100% movement speeds and buttons, 60% mission default, toolbar controls")
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


func _validate_movement_speed(mobile: Node) -> void:
	mobile.set_speed_percent(100)
	mobile.speed_minus.pressed.emit()
	_expect(mobile.speed_percent == 90, "Speed minus reduces speed by ten percentage points")
	for step: int in range(12):
		mobile.change_speed(-10)
	_expect(mobile.speed_percent == 30 and mobile.speed_minus.disabled, "Movement speed is bounded at 30 percent")
	for step: int in range(12):
		mobile.speed_plus.pressed.emit()
	_expect(mobile.speed_percent == 100 and mobile.speed_plus.disabled, "Speed plus advances by ten points and is bounded at 100 percent")
	var scripts: Array[Script] = [
		preload("res://scripts/squad_unit.gd"),
		preload("res://scripts/enemy_unit.gd"),
		preload("res://scripts/escort_unit.gd"),
		preload("res://scripts/ambient_unit.gd"),
	]
	for actor_script: Script in scripts:
		for component_motion: bool in [false, true]:
			for percentage: int in [30, 60, 100]:
				mobile.set_speed_percent(percentage)
				var actor = actor_script.new()
				actor.configure("movement fixture", Color.WHITE, Vector2.ZERO)
				actor.auto_combat_enabled = false
				actor.legacy_actor_scheduler_enabled = false
				actor.hurt_remaining = 1.0
				actor.move_speed = 100.0
				actor.is_running = false
				actor.uses_original_component_movement = component_motion
				actor.walk_step_components = Vector2.ONE
				actor.movement_path = PackedVector2Array([Vector2(1000, 1000) if component_motion else Vector2(1000, 0)])
				actor.movement_path_index = 0
				actor.target_position = actor.movement_path[0]
				actor.attack_cooldown_remaining = 2.0
				actor.simulate_tick(0.1, true)
				_expect(is_equal_approx(actor.position.length(), percentage / 10.0), "Player/enemy/escort/animal scalar and original-component motion respect the selected speed: %s %s %d (observed %f)" % [actor_script.resource_path, component_motion, percentage, actor.position.length()])
				_expect(is_equal_approx(actor.attack_cooldown_remaining, 1.9), "Movement speed leaves combat timing unchanged")
				actor.free()
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Movement speed leaves global game time unchanged")
	mobile.set_speed_percent(60)


func _screen_touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _screen_drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
