extends CanvasLayer

## Settings overlay: a small "settings" button (top-right, in the safe area)
## toggles a panel of tunables that apply ACROSS ALL LEVELS -- gravity, launch
## speed, win distance, and the world boundary. They write to the running game
## in real time. Per-level body layout is defined in the level data, not here.

var main: Node = null

var root: Control
var panel: PanelContainer
var vbox: VBoxContainer
var sliders: Dictionary = {}  # key -> HSlider
var defaults: Dictionary = {} # key -> float

func bind(m: Node) -> void:
	main = m
	_build_ui()

# Each spec entry: [label, key, min, max, step, getter Callable, setter Callable]
func _global_specs() -> Array:
	return [
		["G (grav constant)", "G", 0.0, 20.0, 0.01,
			func(): return main.gravitational_constant,
			func(v): main.gravitational_constant = v],
		["Launch speed", "speed", 50.0, 1000.0, 5.0,
			func(): return main.launch_speed,
			func(v): main.launch_speed = v],
		["Landing distance (win)", "landing", 5.0, 200.0, 1.0,
			func(): return main.landing_distance,
			func(v): main.landing_distance = v],
		["World boundary scale", "boundary", 1.0, 6.0, 0.1,
			func(): return main.world_boundary_scale,
			func(v): main.world_boundary_scale = v],
	]

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top: float = main.safe_area_top() + 8.0

	var toggle: Button = Button.new()
	toggle.text = "settings"
	toggle.position = Vector2(556, top)
	toggle.custom_minimum_size = Vector2(152, 44)
	toggle.add_theme_font_override("font", load("res://fonts/VT323-Regular.ttf"))
	toggle.add_theme_font_size_override("font_size", 26)
	root.add_child(toggle)

	panel = PanelContainer.new()
	panel.position = Vector2(356, top + 56.0)
	panel.custom_minimum_size = Vector2(352, 0)
	panel.visible = false
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.12, 0.94)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.4, 0.6, 0.9, 0.6)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	toggle.pressed.connect(func(): panel.visible = not panel.visible)

	vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(330, 0)
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "SETTINGS (all levels)"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	for s in _global_specs():
		_add_slider(vbox, s)

	_add_button(vbox, "Reset to Defaults", _reset_defaults)
	_add_button(vbox, "Copy Values (print)", _print_values)

func _add_slider(container: Node, spec: Array) -> void:
	var label_text: String = spec[0]
	var key: String = spec[1]
	var getter: Callable = spec[5]
	var setter: Callable = spec[6]

	var head: Label = Label.new()
	head.add_theme_font_size_override("font_size", 14)

	var slider: HSlider = HSlider.new()
	slider.min_value = spec[2]
	slider.max_value = spec[3]
	slider.step = spec[4]
	var cur: float = float(getter.call())
	if cur > slider.max_value:
		slider.max_value = cur
	slider.value = cur
	slider.custom_minimum_size = Vector2(326, 22)

	var fmt: Callable = func(v: float) -> String:
		return "%s: %.1f" % [label_text, v]
	head.text = fmt.call(cur)
	slider.value_changed.connect(func(v: float):
		head.text = fmt.call(v)
		setter.call(v)
	)

	container.add_child(head)
	container.add_child(slider)
	sliders[key] = slider
	defaults[key] = cur

func _add_button(container: Node, text: String, cb: Callable) -> void:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(326, 34)
	b.pressed.connect(cb)
	container.add_child(b)

func _reset_defaults() -> void:
	for key in defaults.keys():
		if sliders.has(key):
			sliders[key].value = defaults[key] # triggers value_changed -> setter

func _print_values() -> void:
	print("# ---- Gravity Rocketeer settings (all levels) ----")
	print("gravitational_constant = %f" % main.gravitational_constant)
	print("launch_speed = %f" % main.launch_speed)
	print("landing_distance = %f" % main.landing_distance)
	print("world_boundary_scale = %f" % main.world_boundary_scale)
	print("# -------------------------------------------------")
