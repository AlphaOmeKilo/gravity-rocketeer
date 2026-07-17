@tool
extends Node2D

## A docked space station used as a landable checkpoint (the old blue "waypoint
## planet"). This node is purely visual -- gravity, the well glow and the landing
## test all live on the sibling GravityBody. It's drawn in code (central hull +
## solar wings + docking ring) so it reads as something built, not another planet.

@export var radius: float = 52.0:
	set(v):
		radius = v
		queue_redraw()

## Blue accent shared with the waypoint gameplay colour, so a station still reads as
## "the landable checkpoint" at a glance.
@export var accent: Color = Color(0.35, 0.6, 1.0):
	set(v):
		accent = v
		queue_redraw()

const SPIN: float = 0.15 # rad/s -- a slow idle tumble so it feels alive

func _process(delta: float) -> void:
	rotation += delta * SPIN

func _hexagon(r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(6):
		var a: float = PI / 6.0 + float(i) * PI / 3.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _draw() -> void:
	var r: float = radius
	var hull_light: Color = Color(0.78, 0.82, 0.90)
	var hull_dark: Color = Color(0.26, 0.30, 0.38)
	var panel: Color = Color(0.10, 0.20, 0.42)
	var panel_line: Color = accent

	# Central truss the wings hang off.
	draw_rect(Rect2(-r * 2.3, -r * 0.08, r * 4.6, r * 0.16), hull_dark)

	# Two solar wings with grid lines and a frame.
	for s in [-1.0, 1.0]:
		var inner: float = s * r * 1.15
		var outer: float = s * r * 2.25
		var pr: Rect2 = Rect2(minf(inner, outer), -r * 0.62, absf(outer - inner), r * 1.24)
		draw_rect(pr, panel)
		for k in range(1, 4):
			var gx: float = lerpf(pr.position.x, pr.position.x + pr.size.x, float(k) / 4.0)
			draw_line(Vector2(gx, pr.position.y), Vector2(gx, pr.position.y + pr.size.y), panel_line, 1.0)
		draw_line(Vector2(pr.position.x, 0.0), Vector2(pr.position.x + pr.size.x, 0.0), panel_line, 1.0)
		draw_rect(pr, panel_line.darkened(0.1), false, 1.5)

	# Docking ring.
	draw_arc(Vector2.ZERO, r * 1.12, 0.0, TAU, 40, hull_light, 3.0, true)

	# Central hexagonal hull with an inner ring and a glowing accent core.
	var hex: PackedVector2Array = _hexagon(r * 0.9)
	draw_colored_polygon(hex, hull_light)
	var outline: PackedVector2Array = hex.duplicate()
	outline.append(hex[0])
	draw_polyline(outline, hull_dark, 2.0, true)
	draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 32, hull_dark, 2.0, true)
	draw_circle(Vector2.ZERO, r * 0.34, accent)
	draw_circle(Vector2.ZERO, r * 0.18, Color(0.85, 0.92, 1.0))

	# Warm beacon lights spaced around the ring.
	for i in range(3):
		var a: float = float(i) * TAU / 3.0
		draw_circle(Vector2(cos(a), sin(a)) * r * 1.12, r * 0.08, Color(1.0, 0.55, 0.3))
