extends RefCounted
class_name Effects

## One-shot visual events for the two moments the player actually watches: the
## crash and the landing. Each spawns a self-freeing node into `parent`, so
## callers stay one line and nothing needs cleaning up.
##
## CPUParticles2D rather than GPUParticles2D on purpose: it behaves identically
## on the mobile renderer (what ships) and the compatibility renderer (what the
## desktop preview uses), with no import or platform caveats.

## Debris burst. Used when the ship strikes a blocker or moon.
static func explode(parent: Node2D, pos: Vector2, tint: Color = Visuals.FLAME_HOT) -> void:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.position = pos
	p.amount = 56
	p.lifetime = 0.85
	p.one_shot = true
	p.explosiveness = 1.0 # fire the whole batch on frame one, not as a stream
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.gravity = Vector2.ZERO # in space nothing pulls the debris down
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 300.0
	p.damping_min = 40.0
	p.damping_max = 90.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var grad: Gradient = Gradient.new()
	grad.set_color(0, tint)
	grad.set_color(1, Color(Visuals.FLAME_COOL.r, Visuals.FLAME_COOL.g, Visuals.FLAME_COOL.b, 0.0))
	p.color_ramp = grad
	parent.add_child(p)
	p.emitting = true
	_free_after(parent, p, p.lifetime + 0.2)

## Liftoff. `dir` is the launch direction, so exhaust fires opposite it. `ground`
## adds the dust billow -- true off the earth pad, false off a waypoint, where
## there is no surface to kick up.
static func liftoff(parent: Node2D, pos: Vector2, dir: Vector2, ground: bool) -> void:
	var ex: CPUParticles2D = CPUParticles2D.new()
	ex.position = pos
	ex.amount = 40
	ex.lifetime = 0.5
	ex.one_shot = true
	ex.explosiveness = 0.75
	ex.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	ex.emission_sphere_radius = 4.0
	ex.direction = -dir
	ex.spread = 22.0
	ex.gravity = Vector2.ZERO
	ex.initial_velocity_min = 120.0
	ex.initial_velocity_max = 340.0
	ex.damping_min = 100.0
	ex.damping_max = 200.0
	ex.scale_amount_min = 1.5
	ex.scale_amount_max = 3.5
	var eg: Gradient = Gradient.new()
	eg.set_color(0, Visuals.FLAME_HOT)
	eg.set_color(1, Color(Visuals.FLAME_COOL.r, Visuals.FLAME_COOL.g, Visuals.FLAME_COOL.b, 0.0))
	ex.color_ramp = eg
	parent.add_child(ex)
	ex.emitting = true
	_free_after(parent, ex, ex.lifetime + 0.2)

	if not ground:
		return

	var dust: CPUParticles2D = CPUParticles2D.new()
	dust.position = pos + Vector2(0.0, 10.0) # at the surface, not the nozzle
	dust.amount = 34
	dust.lifetime = 1.1
	dust.one_shot = true
	dust.explosiveness = 0.85
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(20.0, 3.0)
	dust.direction = Vector2.RIGHT
	dust.spread = 180.0 # billow out to both sides
	dust.gravity = Vector2(0.0, -20.0) # dust rises and hangs rather than falling
	dust.initial_velocity_min = 40.0
	dust.initial_velocity_max = 130.0
	dust.damping_min = 60.0
	dust.damping_max = 120.0
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 5.0
	var dg: Gradient = Gradient.new()
	dg.set_color(0, Visuals.DUST_COLOR)
	dg.set_color(1, Color(Visuals.DUST_COLOR.r, Visuals.DUST_COLOR.g, Visuals.DUST_COLOR.b, 0.0))
	dust.color_ramp = dg
	parent.add_child(dust)
	dust.emitting = true
	_free_after(parent, dust, dust.lifetime + 0.2)

## Expanding ring + flash. Used on a successful landing.
static func flare(parent: Node2D, pos: Vector2, tint: Color) -> void:
	var r: RingFlare = RingFlare.new()
	r.position = pos
	r.tint = tint
	parent.add_child(r)
	var tw: Tween = parent.create_tween().set_parallel(true)
	tw.tween_property(r, "radius", 130.0, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "alpha", 0.0, 0.6)
	tw.chain().tween_callback(r.queue_free)

## Free by timer rather than the `finished` signal: works the same across Godot
## 4.x point releases, and one stray timer is cheaper than a leaked node.
static func _free_after(parent: Node, node: Node, secs: float) -> void:
	parent.get_tree().create_timer(secs).timeout.connect(node.queue_free)

class RingFlare extends Node2D:
	var tint: Color = Color.WHITE

	var radius: float = 0.0:
		set(v):
			radius = v
			queue_redraw()

	var alpha: float = 1.0:
		set(v):
			alpha = v
			queue_redraw()

	func _draw() -> void:
		# Flash fades faster than the ring so the ring is what you follow outward.
		draw_circle(Vector2.ZERO, radius * 0.6,
			Color(tint.r, tint.g, tint.b, alpha * 0.18))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64,
			Color(tint.r, tint.g, tint.b, alpha), 3.0, true)
