"""Idempotently integrate mobile content paths and touch pointer modes."""
from pathlib import Path
import re

game = Path(__file__).resolve().parents[1] / "game"
# A source-native SVG keeps the iOS icon input reproducible and independent of
# desktop ICO files. Godot resizes this master icon for every required slot.
icon = game / "mobile_icon.svg"
icon.write_text('''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<rect width="1024" height="1024" fill="#20392f"/>
<rect x="54" y="54" width="916" height="916" rx="48" fill="none" stroke="#cbbd8b" stroke-width="12"/>
<path d="M512 156 548 265 662 265 570 332 605 440 512 373 419 440 454 332 362 265 476 265Z" fill="#cbbd8b"/>
<g fill="none" stroke="#eee5c8" stroke-width="25" stroke-linecap="square" stroke-linejoin="miter">
<path d="M245 548V788"/>
<path d="M302 548H412V788H302M302 548V668H412"/>
<path d="M475 548H585V788H475M475 668H585"/>
<path d="M648 548H778L694 788"/>
</g><path d="M290 863H734" stroke="#cbbd8b" stroke-width="12"/>
</svg>''', encoding="utf-8")
for name in ("main.gd", "imported_level_data.gd", "level_view.gd", "legacy_media_catalog.gd", "squad_unit.gd"):
    path = game / "scripts" / name
    text = path.read_text(encoding="utf-8")
    text = text.replace("ProjectSettings.globalize_path(", 'preload("res://scripts/mobile_content.gd").resolve(')
    if name == "main.gd" and "# iPad touch pointer mode" not in text:
        anchor = "\tif event is InputEventMouseMotion and camera_dragging and level_camera != null:"
        patch = '''\t# iPad touch pointer mode; GUI consumes its own events before this handler.
\tif event.device == InputEvent.DEVICE_ID_EMULATION and event is InputEventMouseButton:
\t\tvar touch_mouse := event as InputEventMouseButton
\t\tif touch_mouse.button_index == MOUSE_BUTTON_LEFT:
\t\t\ttouch_mouse.button_index = int(get_node("/root/MobileContent").get("pointer_button"))
'''
        assert anchor in text
        text = text.replace(anchor, patch + anchor, 1)
    if name == "main.gd" and "# Touch devices have no persistent edge pointer." not in text:
        anchor = "func _advance_mouse_edge_scroll(delta: float) -> Vector2:\n"
        assert anchor in text
        text = text.replace(anchor, anchor + '\t# Touch devices have no persistent edge pointer.\n\tif OS.has_feature("ios"):\n\t\treturn Vector2.ZERO\n', 1)
    text = text.replace('touch_mouse.button_index = MobileContent.pointer_button', 'touch_mouse.button_index = int(get_node("/root/MobileContent").get("pointer_button"))')
    if name == "main.gd":
        if "# Reset mobile controls for each opened mission." not in text:
            anchor = "\tvar level_load_started_usec := Time.get_ticks_usec()"
            assert anchor in text
            text = text.replace(anchor, '''\t# Reset mobile controls for each opened mission.
\tvar mobile_controls := get_node_or_null("/root/MobileContent")
\tif mobile_controls != null and bool(mobile_controls.call("touch_controls_enabled")):
\t\tmobile_controls.call("reset_for_level")
''' + anchor, 1)
        text = text.replace(
            "level_camera.zoom = Vector2.ONE * LEVEL_VIEW.MAX_ZOOM",
            "level_camera.zoom = Vector2.ONE * 1.28",
        )
        if "# Route native multitouch before legacy mouse commands." not in text:
            anchor = "func _input(event: InputEvent) -> void:\n"
            text = text.replace(anchor, anchor + '''\t# Route native multitouch before legacy mouse commands.
\tvar mobile_input := get_node_or_null("/root/MobileContent")
\tif mobile_input != null and bool(mobile_input.call("handle_touch_input", self, event)):
\t\tget_viewport().set_input_as_handled()
\t\treturn
''', 1)
        if "# Native touches own world commands; mouse emulation remains for GUI." not in text:
            anchor = "func _unhandled_input(event: InputEvent) -> void:\n"
            text = text.replace(anchor, anchor + '''\t# Native touches own world commands; mouse emulation remains for GUI.
\tif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
\t\tvar mobile_input := get_node_or_null("/root/MobileContent")
\t\tif mobile_input != null and bool(mobile_input.call("touch_controls_enabled")):
\t\t\tget_viewport().set_input_as_handled()
\t\t\treturn
''', 1)
    if name == "squad_unit.gd" and "static var mobile_movement_scale" not in text:
        text = text.replace("extends Node2D", "extends Node2D\n\nstatic var mobile_movement_scale: float = 1.0", 1)
        for before, after in (
            ("var travel := maxf(move_speed, 0.0) * fixed_delta", "var travel := maxf(move_speed, 0.0) * fixed_delta * mobile_movement_scale"),
            ("var component_velocity := original_component_velocity()", "var component_velocity := original_component_velocity() * mobile_movement_scale"),
            ("var remaining_distance := maxf(move_speed, 0.0) * safe_delta", "var remaining_distance := maxf(move_speed, 0.0) * safe_delta * mobile_movement_scale"),
            ("_advance_movement_presentation(safe_delta,", "_advance_movement_presentation(safe_delta * mobile_movement_scale,"),
            ("_advance_movement_progress_watchdog(safe_delta,", "_advance_movement_progress_watchdog(safe_delta * mobile_movement_scale,"),
        ):
            assert before in text, before
            text = text.replace(before, after)
    path.write_text(text, encoding="utf-8", newline="\n")

path = game / "project.godot"
text = path.read_text(encoding="utf-8")
if "config/icon=" not in text:
    text = text.replace("[application]", '[application]\n\nconfig/icon="res://mobile_icon.svg"', 1)
text = text.replace('run/main_scene="res://scenes/main.tscn"', 'run/main_scene="res://scenes/mobile_boot.tscn"')
if "[autoload]" not in text:
    text += '\n[autoload]\n\nMobileContent="*res://scripts/mobile_content.gd"\n'
if "[input_devices]" not in text:
    text += '\n[input_devices]\n\npointing/emulate_mouse_from_touch=true\n'
# Scale the virtual canvas to preserve usable touch target sizes on Retina iPads.
text = text.replace('window/stretch/mode="disabled"', 'window/stretch/mode="canvas_items"\nwindow/stretch/aspect="expand"')
# Godot SCREEN_SENSOR_LANDSCAPE = 4. Value 1 is PORTRAIT.
# This also generates landscape-only native iPad supported orientations.
text, orientation_count = re.subn(
    r"(?m)^window/handheld/orientation=.*$", "window/handheld/orientation=4", text
)
if orientation_count == 0:
    text = text.replace("[display]", "[display]\n\nwindow/handheld/orientation=4", 1)
# iOS export validates the project import setting, independently of the
# texture_format/etc2_astc export-preset flag. macOS does not enable this
# automatically, so the exporter otherwise rejects the preset with no message.
if "textures/vram_compression/import_etc2_astc=" not in text:
    assert "[rendering]" in text
    text = text.replace("[rendering]", "[rendering]\n\ntextures/vram_compression/import_etc2_astc=true", 1)
path.write_text(text, encoding="utf-8", newline="\n")

path = game / "export_presets.cfg"
text = path.read_text(encoding="utf-8")
if 'name="iOS"' not in text:
    text += '''
[preset.1]
name="iOS"
platform="iOS"
runnable=true
advanced_options=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="mobile-content.zip, data/*.json, data/**/*.json"
exclude_filter="tests/*, tests/**, tools/*, tools/**"
export_path="../LocalBuild/iOS/1937iPad.ipa"
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.1.options]
application/app_store_team_id="0000000000"
application/bundle_identifier="org.community.m1937.ipad"
application/signature=""
application/short_version="0.9.0"
application/version="1"
application/export_project_only=true
application/targeted_device_family=1
application/min_ios_version="16.0"
application/additional_plist_content=""
architectures/arm64=true
texture_format/s3tc_bptc=false
texture_format/etc2_astc=true
'''
path.write_text(text, encoding="utf-8", newline="\n")
print("iPad integration applied")
