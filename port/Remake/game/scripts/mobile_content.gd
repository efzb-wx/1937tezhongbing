extends CanvasLayer
## External legacy loaders require real filesystem paths. Extract the bundled
## content once into the app sandbox rather than globalizing res:// out of PCK.

const ARCHIVE := "res://mobile-content.zip"
const ROOT := "user://mobile-content"
signal extraction_progress(done: int, total: int)
var pointer_button: int = MOUSE_BUTTON_LEFT
var ready_for_game := false
var toolbar: MarginContainer
var touch_positions: Dictionary = {}
var touch_main: Node
var multiple_touches := false
var touch_button: int = MOUSE_BUTTON_LEFT
var touch_origin := Vector2.ZERO
var touch_moved := false
var touch_started_usec: int = 0
var long_press_selection := false
var speed_percent: int = 100
var speed_label: Label
var speed_minus: Button
var speed_plus: Button
const LONG_PRESS_USEC := 1000000


func set_speed_percent(value: int) -> void:
	speed_percent = clampi(value, 30, 100)
	SquadUnit.mobile_movement_scale = speed_percent / 100.0
	if speed_label != null:
		speed_label.text = "移动速度 %d%%" % speed_percent
	if speed_minus != null:
		speed_minus.disabled = speed_percent <= 30
	if speed_plus != null:
		speed_plus.disabled = speed_percent >= 100


func change_speed(step: int) -> void:
	set_speed_percent(speed_percent + step)


func reset_for_level() -> void:
	cancel_touch_gesture()
	set_speed_percent(60)


func _process(_delta: float) -> void:
	_activate_long_press()


func _activate_long_press() -> void:
	if (
		not is_instance_valid(touch_main) or multiple_touches
		or touch_positions.size() != 1 or touch_button != MOUSE_BUTTON_LEFT
		or touch_moved or Time.get_ticks_usec() - touch_started_usec < LONG_PRESS_USEC
	):
		return
	if not _world_touch_point(touch_main, touch_origin):
		return
	touch_button = MOUSE_BUTTON_RIGHT
	long_press_selection = true
	_touch_mouse(touch_main, touch_origin, MOUSE_BUTTON_RIGHT, true)


func touch_controls_enabled() -> bool:
	return OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args()


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_touch_gesture()


func cancel_touch_gesture() -> void:
	if is_instance_valid(touch_main):
		touch_main.set("camera_dragging", false)
		touch_main.set("right_dragging", false)
		touch_main.queue_redraw()
	touch_positions.clear()
	multiple_touches = false
	touch_moved = false
	long_press_selection = false
	touch_main = null


func _world_touch_point(main: Node, point: Vector2) -> bool:
	var shell: Node = main.get("game_shell")
	if shell != null and bool(shell.call("is_overlay_open")):
		return false
	if toolbar != null and toolbar.get_global_rect().has_point(point):
		return false
	var probe := InputEventMouseButton.new()
	probe.position = point
	return not bool(main.call("_pointer_event_over_gameplay_ui", probe))


func _touch_centroid() -> Vector2:
	var center := Vector2.ZERO
	for point: Vector2 in touch_positions.values():
		center += point
	return center / maxf(touch_positions.size(), 1)


func _touch_mouse(main: Node, point: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = pressed
	main.set("pointer_screen_position", point)
	main.call("_unhandled_input", event)


func handle_touch_input(main: Node, event: InputEvent) -> bool:
	if not touch_controls_enabled():
		return false
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:
		return false
	if touch_main != null and touch_main != main:
		cancel_touch_gesture()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if touch_positions.is_empty():
				if not _world_touch_point(main, touch.position):
					return false
				touch_main = main
				touch_origin = touch.position
				touch_button = pointer_button
				touch_moved = false
				touch_started_usec = Time.get_ticks_usec()
				long_press_selection = false
				multiple_touches = false
				touch_positions[touch.index] = touch.position
				# Delay left-click orders until release so a second finger can
				# join without ever issuing a movement or attack order.
				if touch_button != MOUSE_BUTTON_LEFT:
					_touch_mouse(main, touch.position, touch_button, true)
			else:
				touch_positions[touch.index] = touch.position
				multiple_touches = true
				main.set("camera_dragging", false)
				main.set("right_dragging", false)
				main.queue_redraw()
			return true
		if not touch_positions.has(touch.index):
			return false
		_activate_long_press()
		if touch.canceled:
			multiple_touches = true
		if not multiple_touches and _world_touch_point(main, touch.position):
			if touch_button == MOUSE_BUTTON_LEFT:
				if not touch_moved:
					_touch_mouse(main, touch.position, touch_button, true)
					_touch_mouse(main, touch.position, touch_button, false)
			else:
				_touch_mouse(main, touch.position, touch_button, false)
		touch_positions.erase(touch.index)
		if touch_positions.is_empty():
			cancel_touch_gesture()
		return true
	var drag := event as InputEventScreenDrag
	if not touch_positions.has(drag.index):
		return false
	_activate_long_press()
	var previous_center := _touch_centroid()
	var previous_point: Vector2 = touch_positions[drag.index]
	touch_positions[drag.index] = drag.position
	if touch_origin.distance_to(drag.position) > 12.0:
		touch_moved = true
	if multiple_touches:
		if touch_positions.size() >= 2 and _world_touch_point(main, drag.position):
			var camera := main.get("level_camera") as Camera2D
			if camera != null:
				camera.position -= (_touch_centroid() - previous_center) / camera.zoom
				main.call("clamp_level_camera")
		return true
	if touch_button != MOUSE_BUTTON_LEFT:
		var motion := InputEventMouseMotion.new()
		motion.position = drag.position
		motion.relative = drag.position - previous_point
		main.call("_unhandled_input", motion)
	return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90


func prepare_content() -> bool:
	if not FileAccess.file_exists(ARCHIVE):
		return true
	ready_for_game = await _prepare_content()
	if not ready_for_game:
		push_error("Mobile content extraction failed; refusing to start the game.")
		get_tree().quit(1)
		return false
	if OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args():
		_create_toolbar()
	return true


static func resolve(path: String) -> String:
	if path.begins_with("res://../LocalAssets/") and FileAccess.file_exists(ARCHIVE):
		return ProjectSettings.globalize_path(
			ROOT.path_join("LocalAssets").path_join(path.trim_prefix("res://../LocalAssets/"))
		)
	return ProjectSettings.globalize_path(path)


func _prepare_content() -> bool:
	var digest := FileAccess.get_sha256(ARCHIVE)
	var cache_root := ProjectSettings.globalize_path(ROOT)
	var marker := cache_root.path_join("complete.sha256")
	if FileAccess.file_exists(marker) and FileAccess.get_file_as_string(marker) == digest:
		return true
	var archive := ZIPReader.new()
	if archive.open(ARCHIVE) != OK:
		return false
	var files := archive.get_files()
	var completed := 0
	for entry: String in files:
		if entry.ends_with("/"):
			continue
		if not entry.begins_with("LocalAssets/") or ".." in entry.split("/") or "\\" in entry:
			archive.close()
			return false
		var destination := cache_root.path_join(entry)
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
			archive.close()
			return false
		var output := FileAccess.open(destination, FileAccess.WRITE)
		if output == null:
			archive.close()
			return false
		output.store_buffer(archive.read_file(entry))
		var result := output.get_error()
		output.close()
		if result != OK:
			archive.close()
			return false
		completed += 1
		if completed % 16 == 0:
			extraction_progress.emit(completed, files.size())
			await get_tree().process_frame
	archive.close()
	var completion := FileAccess.open(marker, FileAccess.WRITE)
	if completion == null:
		return false
	completion.store_string(digest)
	return completion.get_error() == OK


func _create_toolbar() -> void:
	var margin := MarginContainer.new()
	toolbar = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.offset_top = 24
	margin.offset_left = 24
	margin.offset_right = -24
	add_child(margin)
	var rows := VBoxContainer.new()
	margin.add_child(rows)
	var controls := HBoxContainer.new()
	rows.add_child(controls)
	var mode := OptionButton.new()
	mode.custom_minimum_size = Vector2(180, 48)
	mode.add_item("点按 / Tap", MOUSE_BUTTON_LEFT)
	mode.add_item("移图 / Pan", MOUSE_BUTTON_MIDDLE)
	mode.add_item("框选 / Select", MOUSE_BUTTON_RIGHT)
	mode.item_selected.connect(func(index: int) -> void: pointer_button = mode.get_item_id(index))
	controls.add_child(mode)
	_add_key(controls, "菜单", KEY_ESCAPE)
	_add_key(controls, "地图", KEY_M)
	_add_key(controls, "跑步", KEY_R)
	_add_key(controls, "卧倒", KEY_C)
	for direction: int in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var zoom := Button.new()
		zoom.text = "+" if direction == MOUSE_BUTTON_WHEEL_UP else "−"
		zoom.focus_mode = Control.FOCUS_NONE
		zoom.custom_minimum_size = Vector2(48, 48)
		zoom.pressed.connect(_zoom.call_deferred.bind(direction))
		controls.add_child(zoom)
	var extra := HBoxContainer.new()
	extra.visible = false
	rows.add_child(extra)
	var more := Button.new()
	more.text = "更多"
	more.custom_minimum_size = Vector2(64, 48)
	more.pressed.connect(func() -> void: extra.visible = not extra.visible)
	controls.add_child(more)
	for index: int in range(5):
		_add_key(extra, str(index + 1), KEY_F2 + index)
	_add_key(extra, "武器", KEY_W)
	_add_key(extra, "物品", KEY_A)
	_add_key(extra, "视线", KEY_S)
	_add_key(extra, "掩埋", KEY_B)
	_add_key(extra, "帮助", KEY_F1)
	speed_label = Label.new()
	extra.add_child(speed_label)
	speed_minus = _add_speed_button(extra, "速度−", -10)
	speed_plus = _add_speed_button(extra, "速度＋", 10)
	set_speed_percent(speed_percent)


func _add_speed_button(row: HBoxContainer, label: String, step: int) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(76, 48)
	button.pressed.connect(change_speed.bind(step))
	row.add_child(button)
	return button


func _add_key(row: HBoxContainer, label: String, keycode: int) -> void:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 48)
	button.pressed.connect(func() -> void:
		_send_key.call_deferred(keycode, true)
		_send_key.call_deferred(keycode, false)
	)
	row.add_child(button)


func _send_key(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _zoom(direction: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = direction
	event.position = get_viewport().get_visible_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	Input.parse_input_event(event)
