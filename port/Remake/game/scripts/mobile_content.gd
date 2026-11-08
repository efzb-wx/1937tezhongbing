extends CanvasLayer
## External legacy loaders require real filesystem paths. Extract the bundled
## content once into the app sandbox rather than globalizing res:// out of PCK.

const ARCHIVE := "res://mobile-content.zip"
const ROOT := "user://mobile-content"
signal extraction_progress(done: int, total: int)
var pointer_button: int = MOUSE_BUTTON_LEFT
var ready_for_game := false


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
