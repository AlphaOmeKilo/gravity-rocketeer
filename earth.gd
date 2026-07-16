@tool
extends Node2D
class_name Earth

## Ground / horizon at the bottom of the screen. The node origin sits at the
## surface PEAK (top-center of the ground) — the ship launches from here. The
## ground is a very shallow, full-width dome filled solid all the way down past
## the bottom of the screen, so it reads like lifting off from the ground rather
## than off a small planet.

## Half-width of the ground surface (should exceed half the visible screen).
@export var span: float = 680.0:
	set(v):
		span = v
		queue_redraw()

## How far the surface curves DOWN at the edges relative to the center peak.
## Small = minimal curvature (nearly flat ground with a hint of a horizon).
@export var dome_height: float = 46.0:
	set(v):
		dome_height = v
		queue_redraw()

## How far below the surface to fill solid (must reach past the screen bottom).
@export var depth: float = 1400.0:
	set(v):
		depth = v
		queue_redraw()

@export var earth_color: Color = Visuals.PLANET_GREEN:
	set(v):
		earth_color = v
		queue_redraw()

## Local surface height (y, positive = down) at a given local x. The peak is at
## x = 0 (y = 0); the surface drops by `dome_height` toward the edges.
func surface_y_at(local_x: float) -> float:
	var t: float = clampf(absf(local_x) / span, 0.0, 1.0)
	return dome_height * (1.0 - cos(t * PI * 0.5))

const STEPS: int = 48

## Emit one quad per surface segment, gradient-filled from `c_bottom` at `y_bottom`
## to `c_top` at the surface (offset up by `rise`). Per-vertex colours give a
## smooth vertical gradient with no shader and no texture; adjacent quads share
## edge colours, so the band reads as one continuous surface.
func _draw_band(rise: float, y_bottom_offset: float, c_top: Color, c_bottom: Color) -> void:
	for i in range(STEPS):
		var x0: float = lerpf(-span, span, float(i) / float(STEPS))
		var x1: float = lerpf(-span, span, float(i + 1) / float(STEPS))
		var s0: float = surface_y_at(x0)
		var s1: float = surface_y_at(x1)
		var quad: PackedVector2Array = PackedVector2Array([
			Vector2(x0, s0 + y_bottom_offset),
			Vector2(x1, s1 + y_bottom_offset),
			Vector2(x1, s1 - rise),
			Vector2(x0, s0 - rise),
		])
		draw_polygon(quad, PackedColorArray([c_bottom, c_bottom, c_top, c_top]))

func _draw() -> void:
	# Ground: lit at the surface, falling into shadow with depth.
	var lit: Color = earth_color.lightened(0.12)
	var deep: Color = earth_color.darkened(0.55)
	_draw_band(0.0, depth, lit, deep)

	# Thin horizon highlight along the surface curve.
	var top: PackedVector2Array = PackedVector2Array()
	for i in range(STEPS + 1):
		var hx: float = lerpf(-span, span, float(i) / float(STEPS))
		top.append(Vector2(hx, surface_y_at(hx)))
	draw_polyline(top, Color(0.5, 0.85, 0.7, 0.5), 2.0, true)

	# Atmosphere: a band of air above the surface fading to vacuum. The single
	# biggest cue that this is a planet and not a green shape on black.
	var air: Color = Visuals.ATMOSPHERE_COLOR
	_draw_band(
		Visuals.ATMOSPHERE_HEIGHT,
		0.0,
		Color(air.r, air.g, air.b, 0.0),
		Color(air.r, air.g, air.b, Visuals.ATMOSPHERE_ALPHA))
