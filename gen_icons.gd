extends SceneTree

# Dev-only: rasterizes icon.svg into the PNG sizes iOS export expects.
func _init() -> void:
	var tex: Texture2D = load("res://icon.svg")
	var base: Image = tex.get_image()
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("ios_icons"):
		dir.make_dir("ios_icons")
	var sizes := {
		"app_store_1024": 1024,
		"iphone_180": 180,
		"iphone_120": 120,
		"ipad_167": 167,
		"ipad_152": 152,
		"ipad_76": 76,
		"spotlight_80": 80,
		"spotlight_40": 40,
	}
	for name in sizes:
		var s: int = sizes[name]
		var img: Image = base.duplicate()
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		var path := "res://ios_icons/%s.png" % name
		img.save_png(path)
		print("wrote ", path, " (", s, "px)")
	quit()
