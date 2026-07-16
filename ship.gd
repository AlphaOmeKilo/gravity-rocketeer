extends Node2D
class_name Ship

## Rocket. Points along +X at rotation 0, so the orchestrator sets
## `rotation = velocity.angle()` to make it face its direction of travel.

@export var ship_color: Color = Visuals.SHIP_COLOR
@export var size: float = 15.0

## Engine burn, 0..1. The flight is ballistic -- `_advance_sim()` applies gravity
## and nothing else -- so this is only non-zero during the launch burn. Coasting
## with the engine lit would be a lie about what the physics is doing.
var thrust: float = 0.0:
	set(v):
		var c: float = clampf(v, 0.0, 1.0)
		if c != thrust:
			thrust = c
			queue_redraw()

var _flicker: float = 0.0

func _process(_delta: float) -> void:
	# Only burn animation needs a per-frame redraw; coasting is static.
	if thrust > 0.0:
		_flicker = randf()
		queue_redraw()

func _draw() -> void:
	# Soft glow: at 15px against a starfield the hull alone disappears.
	draw_circle(Vector2.ZERO, size * 1.7, Color(0.6, 0.75, 1.0, 0.05))

	if thrust > 0.01:
		_draw_flame()
	else:
		# Faint ember between launch and impact, so the engine still reads as a
		# thing that exists while coasting.
		draw_circle(Vector2(-size * 0.62, 0.0), size * 0.15, Visuals.EMBER_COLOR)

	# Fins first, so the hull overlaps them.
	var fin: Color = ship_color.darkened(0.45)
	for s in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-size * 0.2, size * 0.3 * s),
			Vector2(-size * 0.9, size * 0.75 * s),
			Vector2(-size * 0.62, size * 0.28 * s),
		]), fin)

	# Hull.
	draw_colored_polygon(PackedVector2Array([
		Vector2(size, 0.0),
		Vector2(size * 0.1, -size * 0.4),
		Vector2(-size * 0.62, -size * 0.32),
		Vector2(-size * 0.62, size * 0.32),
		Vector2(size * 0.1, size * 0.4),
	]), ship_color)

	# Cockpit.
	draw_circle(Vector2(size * 0.3, 0.0), size * 0.15, Color(0.35, 0.55, 0.85))

func _draw_flame() -> void:
	var tail: Vector2 = Vector2(-size * 0.62, 0.0)
	var flame_len: float = size * (1.5 + 0.55 * _flicker) * thrust
	var flame_w: float = size * 0.4 * thrust
	draw_colored_polygon(PackedVector2Array([
		tail + Vector2(0.0, -flame_w),
		tail + Vector2(-flame_len, 0.0),
		tail + Vector2(0.0, flame_w),
	]), Visuals.FLAME_COOL)
	draw_colored_polygon(PackedVector2Array([
		tail + Vector2(0.0, -flame_w * 0.5),
		tail + Vector2(-flame_len * 0.55, 0.0),
		tail + Vector2(0.0, flame_w * 0.5),
	]), Visuals.FLAME_HOT)
