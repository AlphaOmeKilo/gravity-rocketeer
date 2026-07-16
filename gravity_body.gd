@tool
extends Node2D
class_name GravityBody

## A massive body that gravitationally attracts the ship.
## Only the ship is affected by these; bodies do NOT pull each other.
## All physics values are @export so they can be tuned in the editor AND
## live-adjusted by the debug overlay at runtime.
##
## Rendering is a single ColorRect running body.gdshader, sized to cover the
## influence radius. The @export setters below push straight into shader uniforms,
## so editor tuning and the runtime debug overlay both stay live.

@export var mass: float = 400000.0

## Collision radius. Ship coming within this radius => explode (fail).
@export var physical_radius: float = 40.0:
	set(v):
		physical_radius = v
		_rebuild()

## Sphere-of-influence radius. Used by the trajectory preview: the aim line
## fades out once it enters this radius, so the slingshot result stays hidden.
@export var influence_radius: float = 200.0:
	set(v):
		influence_radius = v
		_rebuild()

@export var body_color: Color = Color(0.95, 0.5, 0.15):
	set(v):
		body_color = v
		_apply_uniforms()

## Which archetype this body reads as. See Visuals.BodyKind.
@export var kind: Visuals.BodyKind = Visuals.BodyKind.ROCKY:
	set(v):
		kind = v
		_apply_uniforms()

## Draw the (normally invisible) sphere-of-influence glow.
@export var show_influence: bool = false:
	set(v):
		show_influence = v
		_apply_uniforms()

const SHADER: Shader = preload("res://body.gdshader")

var _rect: ColorRect = null

## Half-width of the render quad. Covers the influence glow, but never less than
## the body itself -- a body whose influence_radius is smaller than its physical
## radius would otherwise get its disc clipped by the quad.
func _half_extent() -> float:
	return maxf(influence_radius, physical_radius) * 1.05

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _rect == null:
		_rect = ColorRect.new()
		_rect.material = ShaderMaterial.new()
		(_rect.material as ShaderMaterial).shader = SHADER
		# Purely decorative: never eat touches meant for the aim drag.
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_rect)
	var half: float = _half_extent()
	_rect.size = Vector2(half, half) * 2.0
	_rect.position = Vector2(-half, -half)
	_apply_uniforms()

func _apply_uniforms() -> void:
	if _rect == null:
		return
	var mat: ShaderMaterial = _rect.material as ShaderMaterial
	var half: float = _half_extent()
	mat.set_shader_parameter("kind", int(kind))
	mat.set_shader_parameter("body_color", body_color)
	mat.set_shader_parameter("physical_frac", physical_radius / half)
	mat.set_shader_parameter("influence_frac", influence_radius / half)
	# One world unit expressed in the shader's -1..1 quad space, for edge AA.
	mat.set_shader_parameter("px", 1.0 / half)
	mat.set_shader_parameter("halo_strength", 1.0 if show_influence else 0.0)
	mat.set_shader_parameter("light_dir", Visuals.light_dir_3d())
	mat.set_shader_parameter("terminator_mix", Visuals.TERMINATOR_MIX)
	mat.set_shader_parameter("rim_strength", Visuals.RIM_STRENGTH)
	mat.set_shader_parameter("rim_power", Visuals.RIM_POWER)

## Acceleration this body imparts on a ship at `world_point`, for constant `g`.
## F = G * m / r^2, directed from the point toward this body's center.
## Ship mass is treated as 1, so acceleration == force.
func acceleration_at(world_point: Vector2, g: float) -> Vector2:
	var to_body: Vector2 = global_position - world_point
	var dist_sq: float = to_body.length_squared()
	if dist_sq < 1.0:
		dist_sq = 1.0
	var accel_mag: float = g * mass / dist_sq
	return to_body.normalized() * accel_mag
