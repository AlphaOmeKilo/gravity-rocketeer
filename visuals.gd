extends RefCounted
class_name Visuals

## Shared art constants. Bodies, ground, and ship all read from here so the scene
## stays coherent -- and so a new level inherits the look for free rather than
## re-deciding it. If a colour or a light angle is decided in two places, it will
## drift; put it here instead.

## Direction TO the single global light, in 2D screen space (+Y is down, so a
## negative Y points up). Upper-left: every lit body shows its bright edge at the
## top-left and its terminator at the bottom-right.
const LIGHT_DIR: Vector2 = Vector2(-0.707, -0.707)

## Z component used when lifting LIGHT_DIR into 3D to shade a sphere. Higher =
## light more head-on = softer, wider-spread terminator.
const LIGHT_Z: float = 0.55

## How far a lit body darkens toward its terminator. Restrained on purpose: the
## puzzle needs the disc to read as one solid mass at a glance.
const TERMINATOR_MIX: float = 0.35

## Rim-light strength and tightness on the lit edge.
const RIM_STRENGTH: float = 0.55
const RIM_POWER: float = 3.0

## Body archetypes. Drives the one shared body shader via uniforms -- not separate
## code paths. Every kind is lit by LIGHT_DIR the same way; the kind only widens the
## corona or lifts albedo. Keeping the shading identical is what makes the bodies
## read as one family.
enum BodyKind {
	ROCKY,  ## target + blockers
	GIANT,  ## red giant: same shading, wider corona to carry its scale
	MOON,   ## small, high albedo
}

# --- Palette ---------------------------------------------------------------
## Green means habitable ground: the home planet you launch from and the target
## you're trying to reach are the same green, deliberately. Defined once here so
## the two can't drift apart.
const PLANET_GREEN: Color = Color(0.25, 0.82, 0.42)

# --- Space -----------------------------------------------------------------
const SPACE_COLOR: Color = Color(0.03, 0.04, 0.09)

## Star colour temperature endpoints. Most stars sit near white; a few pull toward
## these extremes.
const STAR_COOL: Color = Color(0.72, 0.82, 1.0)
const STAR_WARM: Color = Color(1.0, 0.85, 0.65)

# --- Atmosphere ------------------------------------------------------------
## Tint of the air where the ground meets space, and how far up it fades.
const ATMOSPHERE_COLOR: Color = Color(0.35, 0.78, 0.72)
const ATMOSPHERE_HEIGHT: float = 130.0
const ATMOSPHERE_ALPHA: float = 0.28

# --- Ship ------------------------------------------------------------------
const SHIP_COLOR: Color = Color(0.92, 0.92, 1.0)
const FLAME_HOT: Color = Color(1.0, 0.9, 0.55)
const FLAME_COOL: Color = Color(1.0, 0.45, 0.15)
## Faint engine ember while coasting -- the flight is ballistic, so this is the
## only engine light between launch and impact.
const EMBER_COLOR: Color = Color(1.0, 0.5, 0.2, 0.5)

## Dust kicked off the ground at liftoff. Tinted by the ground it comes from
## rather than a neutral grey.
const DUST_COLOR: Color = Color(0.72, 0.88, 0.76, 0.55)

# --- Camera ----------------------------------------------------------------
## Liftoff kick. Small on purpose: enough to feel the engine, not enough to fight
## the player reading their trajectory.
const SHAKE_MAGNITUDE: float = 5.0
const SHAKE_TIME: float = 0.35

## Lift LIGHT_DIR into the 3D direction used to shade a sphere.
static func light_dir_3d() -> Vector3:
	return Vector3(LIGHT_DIR.x, LIGHT_DIR.y, LIGHT_Z).normalized()
