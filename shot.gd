extends SceneTree

# Temporary: render a level and save a PNG, to review the in-game art.
#   godot --rendering-method gl_compatibility -s shot.gd -- <level> <out.png> [aim_deg] [frames]
# With aim_deg, drives a real launch through _try_launch() (same path the player's
# drag-release takes) and grabs the frame `frames` later, so liftoff effects and the
# camera kick can actually be seen.

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var level: int = int(args[0]) if args.size() > 0 else 0
	var out: String = args[1] if args.size() > 1 else "/tmp/shot.png"
	var has_aim: bool = args.size() > 2
	var aim_deg: float = float(args[2]) if has_aim else 0.0
	var frames: int = int(args[3]) if args.size() > 3 else 8

	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.start_level(level)
	for i in range(90):
		await process_frame

	if has_aim:
		# Aim by placing the "finger" along aim_deg from the ship, then release.
		var dir: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(aim_deg))
		main.drag_current_world = main.ship.global_position + dir * 120.0
		main._try_launch()
		for i in range(frames):
			await process_frame

	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " state=", main.state)
	quit()
