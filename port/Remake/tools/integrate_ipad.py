"""Idempotently integrate mobile content paths and touch pointer modes."""
from pathlib import Path

game = Path(__file__).resolve().parents[1] / "game"
for name in ("main.gd", "imported_level_data.gd", "level_view.gd", "legacy_media_catalog.gd"):
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
    path.write_text(text, encoding="utf-8", newline="\n")

path = game / "project.godot"
text = path.read_text(encoding="utf-8")
text = text.replace('run/main_scene="res://scenes/main.tscn"', 'run/main_scene="res://scenes/mobile_boot.tscn"')
if "[autoload]" not in text:
    text += '\n[autoload]\n\nMobileContent="*res://scripts/mobile_content.gd"\n'
if "[input_devices]" not in text:
    text += '\n[input_devices]\n\npointing/emulate_mouse_from_touch=true\n'
# Scale the virtual canvas to preserve usable touch target sizes on Retina iPads.
text = text.replace('window/stretch/mode="disabled"', 'window/stretch/mode="canvas_items"\nwindow/stretch/aspect="expand"')
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
