extends Control


func _ready() -> void:
	var label := Label.new()
	label.text = "首次准备游戏资源 / Preparing game content..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(label)
	MobileContent.extraction_progress.connect(func(done: int, total: int) -> void:
		label.text = "准备游戏资源 / Preparing content: %d%%" % (100 * done / maxi(total, 1))
	)
	await get_tree().process_frame
	await get_tree().process_frame
	if await MobileContent.prepare_content():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		label.text = "资源准备失败 / Content preparation failed"
