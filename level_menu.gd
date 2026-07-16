extends CanvasLayer

## Level-select menu: a flexible grid of square buttons over the space
## background. A square is filled white with black text once its level is
## completed; otherwise it's an empty white-outlined square with a white number.
## Tapping a square starts that level.

var main: Node = null

var root: Control
var panel: Control
var grid: GridContainer
var toggle: Button
var continue_button: Button
var unlock_toggle: Button
var buttons: Array = [] # Array[Button], one per level

func bind(m: Node) -> void:
	main = m
	_build()
	open() # start on the menu

func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Full-screen panel (dark space backdrop + grid). Shown/hidden as a whole.
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP # eats input behind it
	panel.visible = false
	root.add_child(panel)

	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.09) # matches the game's space background
	panel.add_child(bg)

	var title: Label = Label.new()
	title.text = "SELECT LEVEL"
	title.add_theme_font_override("font", _font())
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 120.0
	title.offset_bottom = 190.0
	panel.add_child(title)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 46)
	center.add_child(vbox)

	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	vbox.add_child(grid)

	continue_button = Button.new()
	continue_button.text = "Continue >"
	continue_button.custom_minimum_size = Vector2(290, 68)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.add_theme_font_override("font", _font())
	continue_button.add_theme_font_size_override("font_size", 36)
	_style_continue(continue_button)
	continue_button.pressed.connect(func(): main.continue_game())
	vbox.add_child(continue_button)

	unlock_toggle = Button.new()
	unlock_toggle.custom_minimum_size = Vector2(290, 50)
	unlock_toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	unlock_toggle.add_theme_font_override("font", _font())
	unlock_toggle.add_theme_font_size_override("font_size", 24)
	_update_unlock_text()
	unlock_toggle.pressed.connect(func():
		main.unlock_all = not main.unlock_all
		_update_unlock_text()
		refresh()
	)
	vbox.add_child(unlock_toggle)

	_build_buttons()

func _update_unlock_text() -> void:
	unlock_toggle.text = "Unlock all (test): %s" % ("ON" if main.unlock_all else "OFF")

	# "levels" toggle, always on top so the menu can be opened/closed anytime.
	toggle = Button.new()
	toggle.text = "levels"
	toggle.position = Vector2(12, main.safe_area_top() + 8.0)
	toggle.custom_minimum_size = Vector2(104, 44)
	toggle.add_theme_font_override("font", _font())
	toggle.add_theme_font_size_override("font_size", 26)
	root.add_child(toggle)
	toggle.pressed.connect(func():
		if panel.visible:
			close()
		else:
			open()
	)

func _font() -> Font:
	return load("res://fonts/VT323-Regular.ttf")

func _build_buttons() -> void:
	for c in grid.get_children():
		c.queue_free()
	buttons.clear()
	var n: int = main.LEVELS.size()
	# Flexible grid: keep it roughly square as levels are added.
	grid.columns = maxi(1, int(ceil(sqrt(float(n)))))
	for i in range(n):
		var b: Button = Button.new()
		b.custom_minimum_size = Vector2(132, 132)
		b.text = str(i + 1)
		b.add_theme_font_override("font", _font())
		b.add_theme_font_size_override("font_size", 52)
		var idx: int = i
		b.pressed.connect(func(): main.start_level(idx))
		grid.add_child(b)
		buttons.append(b)

func _style_button(b: Button, completed: bool, unlocked: bool) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	var text_color: Color
	if completed:
		sb.bg_color = Color(1, 1, 1, 1)         # filled white
		sb.border_color = Color(1, 1, 1, 0.92)
		text_color = Color(0, 0, 0)             # black number
	elif unlocked:
		sb.bg_color = Color(1, 1, 1, 0)         # no fill
		sb.border_color = Color(1, 1, 1, 0.92)
		text_color = Color(1, 1, 1)             # white number
	else: # locked
		sb.bg_color = Color(1, 1, 1, 0)
		sb.border_color = Color(1, 1, 1, 0.25)  # dim outline
		text_color = Color(1, 1, 1, 0.28)       # dim number
	b.disabled = not unlocked                   # locked squares aren't clickable
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, text_color)

func _style_continue(b: Button) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 1, 1, 0.92)
	sb.bg_color = Color(1, 1, 1, 0.10)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color(1, 1, 1))

func refresh() -> void:
	for i in range(buttons.size()):
		_style_button(buttons[i], main.is_completed(i), main.is_unlocked(i))

func open() -> void:
	refresh()
	panel.visible = true

func close() -> void:
	panel.visible = false
