extends Node2D

## Gravity Rocketeer - main orchestrator.
## Owns game state, input (drag-to-aim), the shared physics simulation used by
## both the live preview and the real flight, win/fail detection, trail history,
## and auto-restart on failure.

# ---------------------------------------------------------------------------
# Global tunables (mirrored 1:1 by the debug overlay).
# ---------------------------------------------------------------------------
@export var gravitational_constant: float = 12.0
## Fixed launch speed. Direction is aimed from the ship toward your finger;
## drag distance only sets aim, not speed.
@export var launch_speed: float = 450.0
## Ship within this distance of the target center => WIN.
@export var landing_distance: float = 80.0
## World boundary = base screen size * this scale, centered on the play area.
## Ship crossing it => drift fail.
@export var world_boundary_scale: float = 2.5

# ---------------------------------------------------------------------------
# Simulation config
# ---------------------------------------------------------------------------
const SIM_DT: float = 1.0 / 60.0
const PREVIEW_MAX_STEPS: int = 500
## The aim preview never draws longer than this many world units of path.
const PREVIEW_MAX_LENGTH: float = 1000.0
## From this level index (0-based) on, the aim preview is halved -- later puzzles
## reveal less of the trajectory, so the player has to read the gravity themselves.
const PREVIEW_SHORTEN_LEVEL: int = 4   # "Level 5" in the level list
const PREVIEW_SHORTEN_FACTOR: float = 0.5
const MIN_DRAG: float = 18.0
const FAIL_RESET_DELAY: float = 1.0
## Delay after a win before the "Landed!" modal slides in.
const WIN_MODAL_DELAY: float = 0.5
const MAX_TRAILS: int = 3
const MAX_FLIGHT_STEPS: int = 60 * 30 # safety cap (~30s) so a bad shot can't loop forever
## How long the launch flame burns before the ship coasts. Cosmetic only -- the
## whole launch impulse is applied instantly in _try_launch().
const BURN_TIME: float = 0.45
## Visible ground thickness as a fraction of screen height.
const GROUND_HEIGHT_FRACTION: float = 0.04
## Intro text reveal rate (characters per second) -- deliberately fast.
const TYPE_CHARS_PER_SEC: float = 45.0

enum State { AIMING, FLYING, WON, FAILED }

var state: int = State.AIMING
var ship_velocity: Vector2 = Vector2.ZERO
var launch_position: Vector2 = Vector2.ZERO       # current relaunch origin (pad or waypoint)
var base_launch_position: Vector2 = Vector2.ZERO  # the earth pad
var current_path: PackedVector2Array = PackedVector2Array()
var flight_steps: int = 0

# Fixed-timestep simulation state. The sim advances in deterministic SIM_DT
# steps (so it always matches the preview), while the ship is *rendered* at a
# position interpolated between the last two sim steps for the actual frame
# time -- this decouples motion smoothness from the (uneven) render frame rate.
var sim_pos: Vector2 = Vector2.ZERO
var prev_sim_pos: Vector2 = Vector2.ZERO
var sim_accumulator: float = 0.0

var dragging: bool = false
var drag_current_world: Vector2 = Vector2.ZERO

var fail_timer: float = 0.0
var burn_remaining: float = 0.0  # seconds left on the cosmetic launch flame
var shake_remaining: float = 0.0 # seconds left on the liftoff camera kick
var trails: Array = [] # Array[Line2D], oldest first

# Win modal: built in code, revealed WIN_MODAL_DELAY seconds after a win.
var win_modal: Control = null
var win_backdrop: ColorRect = null
var win_panel: Panel = null
var win_title: Label = null
var next_button: Button = null
var solution_button: Button = null
var win_modal_pending: bool = false
var win_modal_timer: float = 0.0
# The full winning route (all legs), captured at win time and drawn brightly
# while the "View Solution" button is held.
var solution_line: Line2D = null
var solution_path: PackedVector2Array = PackedVector2Array()

# Typewriter intro state.
var intro_char_accum: float = 0.0
var intro_full_len: int = 0

var base_screen: Vector2 = Vector2(720, 1280)
var stars: Array = [] # Array[Dictionary]: {pos, radius, color, bright}

# Bodies are spawned per level (data-driven), so a level can have any number of
# blockers. `gravity_bodies` (used by the physics) = blockers + the target.
var current_level: int = 0
var completed_levels: Dictionary = {} # level index -> true once cleared
var unlock_all: bool = false          # test mode: ignore level locking
var blockers: Array = []            # Array[GravityBody] the ship must avoid
var moons: Array = []               # Array of orbit dicts {body, parent, orbit_radius, orbit_speed, angle}
var waypoints: Array = []           # Array[GravityBody] blue checkpoints you can land on
var waypoint_used: Dictionary = {}  # waypoint node -> true once landed on this attempt
var target_planet: GravityBody = null
var gravity_bodies: Array = []

const TARGET_COLOR: Color = Visuals.PLANET_GREEN      # target is always green
const BLOCKER_COLOR: Color = Color(0.95, 0.5, 0.15)   # blockers orange
const RED_GIANT_COLOR: Color = Color(0.88, 0.24, 0.2) # red giant blocker
const MOON_COLOR: Color = Color(0.92, 0.92, 0.95)     # moons are always white
## A moon's radius as a fraction of the blocker it orbits (kept proportionate).
const MOON_RADIUS_RATIO: float = 0.24
const WAYPOINT_COLOR: Color = Color(0.35, 0.6, 1.0)   # waypoints are blue
## A waypoint's radius as a fraction of the target size.
const WAYPOINT_RADIUS_RATIO: float = 0.75
## The station drawn on top of a waypoint. Preloaded rather than referenced by a
## global class_name, so running straight from the CLI needs no prior editor scan.
const STATION_SCRIPT: Script = preload("res://station.gd")

## Every body's gravity-well radius is derived from its mass, not hand-set, so the
## glow always marks where the pull still bends the flight path -- and it can't drift
## out of sync when a mass is tuned. From the flyby impulse dv ~= 2*g*mass/(b*v), the
## well edge is the closest approach b at which a pass is deflected by this many
## units/s. Reach scales with mass; one shared threshold makes every well comparable.
const INFLUENCE_DEFLECTION: float = 115.0

# Level definitions. Each: a target and a list of blockers, given as
# {pos, mass, radius, influence}. Positions are in the 720x1280 base space.
const LEVELS: Array = [
	{ # Level 1: just the target, no blockers -- an intro to flying to the target.
		"intro": "Hello commander...\nDrag anywhere to aim, then release to launch.\nSteer the rocket to the green planet.\nGravity bends your path -- use it, don't fight it.\nDrift off into deep space on a straight shot? That would be embarrassing.",
		"target": {"pos": Vector2(360, -200), "mass": 350000.0, "radius": 68.0},
		"blockers": [],
	},
	{ # Level 2: a single big blocker directly between the pad and the target.
		"intro": "Well well, an obstacle. How rude.\nThat planet sits squarely between us and our destination.\nCurve around it. Try not to explode -- it voids the warranty.",
		"target": {"pos": Vector2(360, -200), "mass": 350000.0, "radius": 68.0},
		"blockers": [
			{"pos": Vector2(360, 840), "mass": 1000000.0, "radius": 125.0},
		],
	},
	{ # Level 3: a slalom -- two blockers staggered on Y (and opposite sides) so
	  # the ship passes through one gravity well at a time, with a wide gap
	  # between the upper (second) blocker and the target.
		"intro": "Ah, twins. How delightful for everyone.\nWeave between the wells, one at a time.\nDeep breaths, commander.",
		"target": {"pos": Vector2(360, -200), "mass": 350000.0, "radius": 68.0},
		"blockers": [
			{"pos": Vector2(93, 927), "mass": 650000.0, "radius": 125.0},
			{"pos": Vector2(627, 558), "mass": 650000.0, "radius": 125.0},
		],
	},
	{ # Level 4: like level 2 (single blocker) but with a white moon orbiting the
	  # blocker -- a moving mass, so timing the launch matters.
		"intro": "See that little white moon? It orbits.\nTime your launch -- the gravity assist is now a moving target.",
		"target": {"pos": Vector2(360, -200), "mass": 350000.0, "radius": 68.0},
		"blockers": [
			{"pos": Vector2(360, 840), "mass": 1000000.0, "radius": 125.0,
				"moon": {"mass": 90000.0, "orbit_radius": 290.0, "orbit_speed": 0.9, "phase": 0.0}},
		],
	},
	{ # Level 5: a red giant on the left and a blue waypoint level with it on the
	  # right that you land on and relaunch from toward the target.
		"intro": "That red giant is enormous -- its gravity yanks hard.\nSee the station down to your right? Dock there, then relaunch toward the target -- a safe hop that never touches the giant's pull.\nOr chance a slingshot around the giant, if you fancy living dangerously.",
		"target": {"pos": Vector2(360, -180), "mass": 350000.0, "radius": 68.0},
		"blockers": [
			{"pos": Vector2(-20, 780), "mass": 1400000.0, "radius": 220.0, "type": "red_giant"},
		],
		"waypoints": [
			# Lower-right, near the launch pad. Zero mass: the station has no pull and
			# no gravity well -- it's a pure dock you aim through, not a mass to slingshot.
			{"pos": Vector2(760, 1090), "mass": 0.0},
		],
	},
	{ # Level 6: twin slalom (like level 3) but BOTH blockers now carry an orbiting
	  # moon, set to opposite phases so the central gap opens and closes out of sync.
	  # The difficulty capstone: level 3's weave + level 4's moving mass, x2, no waypoint.
	  # The lower blocker is 10% heavier and larger than its twin, so the weave is
	  # asymmetric -- the first well you meet pulls harder than the second.
		"intro": "Twins again -- but these ones brought pets.\nEach well now has a moon on a leash, and they don't take turns nicely.\nRead the dance, thread the gap, and for the love of physics -- time your launch.",
		"target": {"pos": Vector2(360, -200), "mass": 350000.0, "radius": 68.0},
		"blockers": [
			{"pos": Vector2(130, 900), "mass": 715000.0, "radius": 137.5,
				"moon": {"mass": 90000.0, "orbit_radius": 235.0, "orbit_speed": 0.95, "phase": 0.0}},
			{"pos": Vector2(510, 340), "mass": 650000.0, "radius": 125.0,
				"moon": {"mass": 90000.0, "orbit_radius": 240.0, "orbit_speed": 1.15, "phase": 3.14159}},
		],
	},
]

@onready var earth: Earth = $Earth
@onready var bodies_container: Node2D = $Bodies
@onready var ship: Ship = $Ship
@onready var trail_container: Node2D = $TrailContainer
@onready var preview_line: Line2D = $PreviewLine
@onready var intro_label: Label = $UILayer/IntroLabel
@onready var debug_overlay = $DebugLayer
@onready var level_menu = $MenuLayer
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	# Put the ground as a thin strip along the bottom of the visible area, then
	# place the ship on its surface peak.
	_position_ground()
	base_launch_position = earth.global_position + Vector2(0, -(ship.size + 6.0))
	launch_position = base_launch_position
	_setup_intro_label()
	_build_win_modal()
	_setup_preview_style()
	_generate_stars()
	debug_overlay.bind(self)
	_load_level(0) # a valid state behind the menu
	level_menu.bind(self) # opens the level-select menu at startup
	queue_redraw()

## Called by the level menu: start the chosen level and close the menu.
func start_level(index: int) -> void:
	level_menu.close()
	_load_level(index)

func is_completed(index: int) -> bool:
	return completed_levels.get(index, false)

## Top inset of the device safe area, in canvas (content-scale) units, so UI in
## CanvasLayers can sit below the status bar / Dynamic Island on any device.
func safe_area_top() -> float:
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win: Vector2i = DisplayServer.window_get_size()
	var content_w: float = float(get_window().content_scale_size.x)
	if win.x <= 0 or content_w <= 0.0:
		return 12.0
	var scale: float = float(win.x) / content_w
	return float(safe.position.y) / scale

## Lowest-index level not yet completed (== LEVELS.size() if everything's done).
func next_uncompleted_index() -> int:
	for i in range(LEVELS.size()):
		if not is_completed(i):
			return i
	return LEVELS.size()

## A level is playable if it's already completed (replayable) or it's the next
## uncompleted one. Later uncompleted levels stay locked until you reach them --
## unless test mode (`unlock_all`) is on, which unlocks everything.
func is_unlocked(index: int) -> bool:
	return unlock_all or is_completed(index) or index == next_uncompleted_index()

## Play the next uncompleted level (or replay the last if all are completed).
func continue_game() -> void:
	var idx: int = next_uncompleted_index()
	if idx >= LEVELS.size():
		idx = LEVELS.size() - 1
	start_level(idx)

func _setup_intro_label() -> void:
	var f: Font = load("res://fonts/VT323-Regular.ttf")
	intro_label.add_theme_font_override("font", f)
	intro_label.add_theme_font_size_override("font_size", 34)
	intro_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.95))

## Begin the character-by-character reveal of the current level's intro text.
func _start_intro(text: String) -> void:
	intro_label.text = text
	intro_full_len = text.length()
	intro_char_accum = 0.0
	intro_label.visible_characters = 0
	intro_label.visible = text != ""

# ---------------------------------------------------------------------------
# Levels
# ---------------------------------------------------------------------------
func _load_level(index: int) -> void:
	current_level = clampi(index, 0, LEVELS.size() - 1)
	for c in bodies_container.get_children():
		c.queue_free()
	blockers.clear()
	moons.clear()
	waypoints.clear()
	waypoint_used.clear()
	launch_position = base_launch_position # a fresh attempt starts at the pad
	var data: Dictionary = LEVELS[current_level]
	target_planet = _make_body(data["target"], TARGET_COLOR)
	_style_green(target_planet, _body_rng("target"))
	var bi: int = 0
	for bdata in data["blockers"]:
		var is_giant: bool = bdata.get("type", "") == "red_giant"
		var col: Color = RED_GIANT_COLOR if is_giant else BLOCKER_COLOR
		var k: Visuals.BodyKind = Visuals.BodyKind.GIANT if is_giant else Visuals.BodyKind.ROCKY
		var b: GravityBody = _make_body(bdata, col, k)
		var rng: RandomNumberGenerator = _body_rng("blocker%d" % bi)
		if is_giant:
			_style_giant(b, rng)
		else:
			_style_rocky(b, rng)
		blockers.append(b)
		if bdata.has("moon"):
			_make_moon(bdata["moon"], b)
		bi += 1
	for wdata in data.get("waypoints", []):
		_make_waypoint(wdata)
	# Physics acts on blockers + moons + waypoints + target.
	gravity_bodies = blockers.duplicate()
	for m in moons:
		gravity_bodies.append(m["body"])
	for w in waypoints:
		gravity_bodies.append(w)
	gravity_bodies.append(target_planet)
	clear_trails()
	_hide_win_modal()
	_reset_ship()
	_start_intro(data.get("intro", ""))

## Gravity-well radius for a body of this mass -- see INFLUENCE_DEFLECTION. A massless
## body (the station) gets no well, matching its lack of pull.
func _influence_for_mass(mass: float) -> float:
	if mass <= 0.0:
		return 0.0
	return 2.0 * gravitational_constant * mass / (launch_speed * INFLUENCE_DEFLECTION)

func _make_body(d: Dictionary, color: Color,
		kind: Visuals.BodyKind = Visuals.BodyKind.ROCKY) -> GravityBody:
	var b: GravityBody = GravityBody.new()
	b.position = d["pos"]
	b.mass = d["mass"]
	b.physical_radius = d["radius"]
	b.influence_radius = _influence_for_mass(b.mass)
	b.body_color = color
	b.kind = kind
	b.show_influence = true
	bodies_container.add_child(b)
	return b

## A per-body RNG seeded from the level + a tag, so every planet's random look is
## stable across replays but each planet differs from its neighbours.
func _body_rng(tag: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%d/%s" % [current_level, tag])
	return rng

## Rocky blocker: a greyish world with a faint random hue -- like the terrestrial /
## rocky types (Mercury grey, rusty tan, dusty ochre). Low saturation keeps it
## reading as rock, not candy. Mottled between a darker and lighter tint of itself.
func _style_rocky(b: GravityBody, rng: RandomNumberGenerator) -> void:
	var hue: float = rng.randf()
	var sat: float = rng.randf_range(0.10, 0.24)
	var val: float = rng.randf_range(0.46, 0.64)
	var base: Color = Color.from_hsv(hue, sat, val)
	b.body_color = base
	b.detail_dark = base.darkened(rng.randf_range(0.30, 0.45))
	b.detail_light = base.lightened(rng.randf_range(0.22, 0.38))
	b.detail_strength = rng.randf_range(0.45, 0.65)
	b.detail_seed = rng.randf_range(0.0, 100.0)

## Red giant: same mottled treatment but anchored to red. The hue only jitters
## across red-orange and saturation stays high, so it stays unmistakably a red
## giant while gaining surface streaks and a little grey.
func _style_giant(b: GravityBody, rng: RandomNumberGenerator) -> void:
	var hue: float = wrapf(rng.randf_range(-0.02, 0.045), 0.0, 1.0)
	var sat: float = rng.randf_range(0.55, 0.72)
	var val: float = rng.randf_range(0.72, 0.86)
	var base: Color = Color.from_hsv(hue, sat, val)
	b.body_color = base
	b.detail_dark = base.darkened(rng.randf_range(0.30, 0.45))
	b.detail_light = base.lightened(rng.randf_range(0.18, 0.30))
	b.detail_strength = rng.randf_range(0.40, 0.55)
	b.detail_seed = rng.randf_range(0.0, 100.0)

## Green world (home + target): keep the signature green, but break up the disc
## with white highlands and dark-green lowlands so it reads as a living planet.
func _style_green(b: GravityBody, rng: RandomNumberGenerator) -> void:
	b.detail_dark = Visuals.PLANET_GREEN.darkened(rng.randf_range(0.45, 0.58))
	b.detail_light = Color(0.92, 0.96, 0.93)
	b.detail_strength = rng.randf_range(0.42, 0.55)
	b.detail_seed = rng.randf_range(0.0, 100.0)

## Spawn a white moon that orbits `parent`. Its radius is kept proportionate to
## the parent blocker. Tracked in `moons` and advanced each frame.
func _make_moon(m: Dictionary, parent: GravityBody) -> void:
	var moon: GravityBody = GravityBody.new()
	moon.mass = m["mass"]
	moon.physical_radius = parent.physical_radius * MOON_RADIUS_RATIO
	moon.influence_radius = _influence_for_mass(moon.mass)
	moon.body_color = MOON_COLOR
	moon.kind = Visuals.BodyKind.MOON
	moon.show_influence = true # draw the moon's gravity-well glow too
	bodies_container.add_child(moon)
	var entry: Dictionary = {
		"body": moon,
		"parent": parent,
		"orbit_radius": float(m["orbit_radius"]),
		"orbit_speed": float(m["orbit_speed"]),
		"angle": float(m.get("phase", 0.0)),
	}
	moons.append(entry)
	_place_moon(entry)

func _place_moon(entry: Dictionary) -> void:
	var a: float = entry["angle"]
	entry["body"].position = entry["parent"].position + Vector2(cos(a), sin(a)) * entry["orbit_radius"]

func _update_moons(delta: float) -> void:
	for entry in moons:
		entry["angle"] += entry["orbit_speed"] * delta
		_place_moon(entry)

## Reveal the intro text one character at a time.
func _advance_intro(delta: float) -> void:
	if intro_label.visible_characters < 0 or intro_label.visible_characters >= intro_full_len:
		return
	intro_char_accum += delta * TYPE_CHARS_PER_SEC
	intro_label.visible_characters = mini(int(intro_char_accum), intro_full_len)

func _hit_any_moon(pos: Vector2) -> bool:
	for entry in moons:
		var moon: GravityBody = entry["body"]
		if pos.distance_to(moon.global_position) <= moon.physical_radius:
			return true
	return false

## Spawn a blue waypoint: a landable checkpoint with its own gravity, sized to
## a fraction of the target. Landing on it lets the ship relaunch from there.
func _make_waypoint(w: Dictionary) -> void:
	var wp: GravityBody = GravityBody.new()
	wp.position = w["pos"]
	wp.mass = w["mass"]
	wp.physical_radius = target_planet.physical_radius * WAYPOINT_RADIUS_RATIO
	wp.influence_radius = _influence_for_mass(wp.mass) # 0 mass => no pull, no well
	wp.body_color = WAYPOINT_COLOR
	wp.kind = Visuals.BodyKind.STATION # draw the well glow but no planet disc
	wp.show_influence = true
	bodies_container.add_child(wp)
	# The visible checkpoint is a docked station, drawn on top of the well glow.
	# Preloaded (not a global class_name) so a fresh CLI run needs no editor scan.
	var station: Node2D = STATION_SCRIPT.new()
	station.radius = wp.physical_radius
	station.accent = WAYPOINT_COLOR
	wp.add_child(station)
	waypoints.append(wp)

## Land on a waypoint: bank the leg so far as a trail, park the ship there, make
## it the new relaunch origin, and face the final target for the next launch.
func _land_waypoint(wp: GravityBody) -> void:
	_finalize_trail()
	waypoint_used[wp] = true
	# Perch the rocket on top of the waypoint, the same way it sits above the
	# earth pad (offset up by the body's radius + the ship's length).
	var perch: Vector2 = wp.global_position + Vector2(0, -(wp.physical_radius + ship.size + 6.0))
	ship.global_position = perch
	launch_position = perch # relaunch from atop the waypoint (checkpoint)
	ship_velocity = Vector2.ZERO
	ship.rotation = -PI / 2.0 # point straight up, same as launching from earth
	ship.thrust = 0.0
	burn_remaining = 0.0
	Effects.flare(self, sim_pos, WAYPOINT_COLOR) # touchdown reads the same as a win
	current_path = PackedVector2Array()
	flight_steps = 0
	sim_accumulator = 0.0
	state = State.AIMING

func _has_next_level() -> bool:
	return current_level + 1 < LEVELS.size()

func _setup_preview_style() -> void:
	preview_line.width = 3.0
	preview_line.default_color = Color(0.5, 0.85, 1.0, 0.6)
	preview_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	preview_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	# Fade only the tail so the aim line dissolves as it nears the wrong mass.
	var grad: Gradient = Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(0.5, 0.85, 1.0, 0.6))
	grad.add_point(0.75, Color(0.5, 0.85, 1.0, 0.6))
	grad.set_offset(1, 1.0)
	grad.set_color(1, Color(0.5, 0.85, 1.0, 0.0))
	preview_line.gradient = grad

## Build the starfield. The camera never moves, so depth can't come from parallax
## -- it has to come from magnitude and colour temperature alone. Fixed seed, so
## every level and every run gets the same sky.
func _generate_stars() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260714
	stars = []
	for i in range(260):
		# Cubed uniform => mostly faint stars with a handful of bright ones, which
		# is what actually reads as distance. A flat distribution looks like noise.
		var m: float = pow(rng.randf(), 3.0)
		# Colour temperature, biased hard toward white: a few cool blue and warm
		# amber stars are enough to kill the "printed dots" feel.
		var t: float = rng.randf_range(-1.0, 1.0)
		t = signf(t) * pow(absf(t), 2.0)
		var tint: Color = Visuals.STAR_COOL if t < 0.0 else Visuals.STAR_WARM
		var col: Color = Color.WHITE.lerp(tint, absf(t))
		col.a = lerpf(0.28, 0.95, m)
		stars.append({
			"pos": Vector2(rng.randf_range(-700, 1420), rng.randf_range(-700, 1980)),
			"radius": lerpf(0.7, 2.3, m),
			"color": col,
			"bright": m > 0.8,
		})

## Place the ground so only a thin strip (GROUND_HEIGHT_FRACTION of the visible
## screen height) shows along the bottom, adapting to whatever device/aspect the
## game runs on.
## In `expand` stretch mode the width axis always fits exactly, so world units
## per screen pixel = (content_width / zoom) / window_pixel_width. From that we
## derive the visible world height and where the bottom edge sits.
func _position_ground() -> void:
	var cam: Camera2D = $Camera2D
	var base_w: float = float(get_window().content_scale_size.x)
	if base_w <= 0.0:
		base_w = base_screen.x
	var win: Vector2 = Vector2(get_window().size)
	if win.x <= 0.0 or win.y <= 0.0:
		win = Vector2(get_window().content_scale_size)
	var world_w: float = base_w / cam.zoom.x
	var world_per_px: float = world_w / win.x
	var world_h: float = win.y * world_per_px
	var center: Vector2 = cam.global_position
	var band: float = world_h * GROUND_HEIGHT_FRACTION
	earth.position = Vector2(center.x, center.y + world_h * 0.5 - band)
	earth.span = world_w * 0.5 + 80.0
	# Keep the visible curvature subtle on such a thin strip.
	earth.dome_height = minf(earth.dome_height, band * 0.8)

# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------
func _reset_ship() -> void:
	# A fresh attempt always starts back at the earth pad, and any waypoint is
	# available to land on again (a failed run from a waypoint doesn't respawn
	# you at the waypoint).
	launch_position = base_launch_position
	waypoint_used.clear()
	ship.global_position = launch_position
	ship_velocity = Vector2.ZERO
	ship.rotation = -PI / 2.0 # face straight up
	ship.thrust = 0.0
	ship.visible = true # a previous attempt may have exploded it
	burn_remaining = 0.0
	shake_remaining = 0.0
	camera.offset = Vector2.ZERO
	current_path = PackedVector2Array()
	flight_steps = 0
	preview_line.points = PackedVector2Array()
	dragging = false
	state = State.AIMING

func clear_trails() -> void:
	for t in trails:
		t.queue_free()
	trails.clear()

## The win button: advances to the next level, or replays from level 1 if the
## last level was just cleared.
func _on_restart_pressed() -> void:
	if _has_next_level():
		_load_level(current_level + 1)
	else:
		_load_level(0)

# ---------------------------------------------------------------------------
# Win modal (built in code): a dimmed backdrop + centered panel with the win
# title, a Next Level button, and a hold-to-peek "View Solution" button. It's
# revealed WIN_MODAL_DELAY seconds after the win (see _process/State.WON).
# ---------------------------------------------------------------------------
func _build_win_modal() -> void:
	var font: Font = load("res://fonts/VT323-Regular.ttf")

	# The bright winning-route overlay lives in world space (like trails) so it
	# lines up with the play area. Hidden until the player holds View Solution.
	solution_line = Line2D.new()
	solution_line.width = 5.0
	solution_line.default_color = Color(1.0, 0.85, 0.2, 0.95)
	solution_line.joint_mode = Line2D.LINE_JOINT_ROUND
	solution_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	solution_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	solution_line.z_index = 5
	solution_line.visible = false
	add_child(solution_line)

	win_modal = Control.new()
	win_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_modal.visible = false
	$UILayer.add_child(win_modal)

	# Full-screen dim that also swallows taps outside the panel.
	win_backdrop = ColorRect.new()
	win_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	win_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	win_modal.add_child(win_backdrop)

	# Centered panel.
	win_panel = Panel.new()
	var panel_size: Vector2 = Vector2(460, 340)
	win_panel.custom_minimum_size = panel_size
	win_panel.size = panel_size
	win_panel.position = (base_screen - panel_size) * 0.5
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.18, 0.98)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.5, 0.85, 1.0, 0.7)
	sb.set_content_margin_all(28)
	win_panel.add_theme_stylebox_override("panel", sb)
	win_modal.add_child(win_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 28
	vbox.offset_top = 28
	vbox.offset_right = -28
	vbox.offset_bottom = -28
	vbox.add_theme_constant_override("separation", 22)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	win_panel.add_child(vbox)

	win_title = Label.new()
	win_title.add_theme_font_override("font", font)
	win_title.add_theme_font_size_override("font_size", 56)
	win_title.add_theme_color_override("font_color", Color(0.92, 0.96, 0.95))
	win_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_title.text = "Landed!"
	vbox.add_child(win_title)

	next_button = _make_modal_button(font, "Next Level", 34)
	next_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(next_button)

	solution_button = _make_modal_button(font, "Hold to View Solution", 26)
	solution_button.button_down.connect(_on_solution_down)
	solution_button.button_up.connect(_on_solution_up)
	vbox.add_child(solution_button)

func _make_modal_button(font: Font, text: String, size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 62)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	return b

## Snapshot the full winning route (every banked leg + the final flight) so it
## can be redrawn brightly on demand, even after the trails fade.
func _capture_solution() -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for t in trails:
		pts.append_array(t.points)
	pts.append_array(current_path)
	solution_path = pts

func _show_win_modal() -> void:
	win_backdrop.visible = true
	win_panel.modulate = Color(1, 1, 1, 1)
	solution_line.visible = false
	win_modal.visible = true

func _hide_win_modal() -> void:
	win_modal_pending = false
	if win_modal != null:
		win_modal.visible = false
		win_panel.modulate = Color(1, 1, 1, 1)
		win_backdrop.visible = true
	if solution_line != null:
		solution_line.visible = false

## While held, fade the modal aside and light up the winning trajectory.
func _on_solution_down() -> void:
	if solution_path.size() >= 2:
		solution_line.points = solution_path
		solution_line.visible = true
	win_backdrop.visible = false
	win_panel.modulate = Color(1, 1, 1, 0.12)

func _on_solution_up() -> void:
	solution_line.visible = false
	win_backdrop.visible = true
	win_panel.modulate = Color(1, 1, 1, 1)

# ---------------------------------------------------------------------------
# Input: touch/drag to aim (direction = ship -> finger), release to launch at a
# fixed speed. Drag distance only sets aim direction, not speed.
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if state != State.AIMING:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			intro_label.visible = false # dismiss the briefing once aiming starts
			drag_current_world = get_global_mouse_position()
			_update_preview()
		elif dragging:
			dragging = false
			_try_launch()
	elif event is InputEventMouseMotion and dragging:
		drag_current_world = get_global_mouse_position()
		_update_preview()

## Returns the current aim as {valid, dir}. Speed is the fixed `launch_speed`.
func _aim() -> Dictionary:
	var v: Vector2 = drag_current_world - ship.global_position
	var dist: float = v.length()
	if dist < MIN_DRAG:
		return {"valid": false}
	return {"valid": true, "dir": v / dist}

## Visible length cap for the aim preview at the current level. Halved from
## PREVIEW_SHORTEN_LEVEL on, so late puzzles show less of the trajectory.
func _preview_max_length() -> float:
	if current_level >= PREVIEW_SHORTEN_LEVEL:
		return PREVIEW_MAX_LENGTH * PREVIEW_SHORTEN_FACTOR
	return PREVIEW_MAX_LENGTH

func _update_preview() -> void:
	var aim: Dictionary = _aim()
	if not aim.valid:
		preview_line.points = PackedVector2Array()
		return
	var dir: Vector2 = aim.dir
	ship.rotation = dir.angle()
	var pos: Vector2 = ship.global_position
	var vel: Vector2 = dir * launch_speed
	var pts: PackedVector2Array = PackedVector2Array([pos])
	# Draw the trajectory but cut it the moment it makes contact with an actual
	# body of mass -- append the contact point so the line reaches the body
	# surface, then stop; nothing past the impact is shown. The line is also
	# capped at PREVIEW_MAX_LENGTH world units, trimmed to end exactly there.
	var max_length: float = _preview_max_length()
	var drawn_len: float = 0.0
	for i in range(PREVIEW_MAX_STEPS):
		var step: Array = _sim_step(pos, vel, SIM_DT)
		var next_pos: Vector2 = step[0]
		var seg: float = pos.distance_to(next_pos)
		if drawn_len + seg >= max_length:
			var t: float = (max_length - drawn_len) / seg if seg > 0.0 else 0.0
			pts.append(pos.lerp(next_pos, t))
			break
		drawn_len += seg
		pos = next_pos
		vel = step[1]
		if _hit_any_blocker(pos) or _hit_any_moon(pos):
			pts.append(pos)
			break
		pts.append(pos)
		if _out_of_bounds(pos):
			break
	preview_line.points = pts

func _hit_any_blocker(pos: Vector2) -> bool:
	for b in blockers:
		if pos.distance_to(b.global_position) <= b.physical_radius:
			return true
	return false

func _try_launch() -> void:
	var aim: Dictionary = _aim()
	if not aim.valid:
		preview_line.points = PackedVector2Array()
		return
	var dir: Vector2 = aim.dir
	ship_velocity = dir * launch_speed
	ship.rotation = dir.angle()
	sim_pos = ship.global_position
	prev_sim_pos = sim_pos
	sim_accumulator = 0.0
	current_path = PackedVector2Array([ship.global_position])
	flight_steps = 0
	preview_line.points = PackedVector2Array()
	ship.thrust = 1.0 # burn now; it decays over BURN_TIME and then we coast
	burn_remaining = BURN_TIME
	# Dust only off the earth pad -- a waypoint launch happens in space, with no
	# surface to kick up.
	var from_pad: bool = launch_position.is_equal_approx(base_launch_position)
	Effects.liftoff(self, ship.global_position, dir, from_pad)
	state = State.FLYING

# ---------------------------------------------------------------------------
# Shared physics: one integration step. Used by preview AND real flight so they
# are guaranteed identical.
# ---------------------------------------------------------------------------
func _sim_step(pos: Vector2, vel: Vector2, dt: float) -> Array:
	var accel: Vector2 = Vector2.ZERO
	for b in gravity_bodies:
		accel += b.acceleration_at(pos, gravitational_constant)
	vel += accel * dt
	pos += vel * dt
	return [pos, vel]

# Run everything on the render clock. Flight advances the sim in fixed SIM_DT
# steps via an accumulator, then renders the ship interpolated between steps so
# motion stays smooth regardless of the actual (possibly uneven) frame rate.
const MAX_SUBSTEPS: int = 8 # cap steps per frame to avoid a spiral of death

func _process(delta: float) -> void:
	# Moons orbit continuously, in every state, so the player can time a launch.
	_update_moons(delta)
	_advance_intro(delta)
	_update_shake(delta)
	match state:
		State.FLYING:
			_update_flight(delta)
		State.FAILED:
			fail_timer -= delta
			if fail_timer <= 0.0:
				_reset_ship()
		State.WON:
			if win_modal_pending:
				win_modal_timer -= delta
				if win_modal_timer <= 0.0:
					win_modal_pending = false
					_show_win_modal()

func _update_flight(delta: float) -> void:
	# The launch burn is purely visual -- the impulse was applied all at once in
	# _try_launch(). It just gives the departure a moment of engine before the
	# ballistic coast takes over.
	if burn_remaining > 0.0:
		burn_remaining = maxf(burn_remaining - delta, 0.0)
		ship.thrust = burn_remaining / BURN_TIME

	sim_accumulator += delta
	var steps_done: int = 0
	while sim_accumulator >= SIM_DT and state == State.FLYING and steps_done < MAX_SUBSTEPS:
		prev_sim_pos = sim_pos
		_advance_sim(SIM_DT)
		sim_accumulator -= SIM_DT
		steps_done += 1
	# If we hit the cap (a bad hitch), drop the backlog rather than spiral.
	if steps_done >= MAX_SUBSTEPS:
		sim_accumulator = 0.0

	if state == State.FLYING:
		var t: float = clampf(sim_accumulator / SIM_DT, 0.0, 1.0)
		ship.global_position = prev_sim_pos.lerp(sim_pos, t)
	elif state != State.AIMING:
		# WIN/FAIL: settle on the final sim position. On a waypoint landing the
		# state becomes AIMING and the ship is already perched on top -- don't
		# clobber that with the contact point (it'd show on the side).
		ship.global_position = sim_pos
	if state == State.FLYING and ship_velocity.length() > 1.0:
		ship.rotation = ship_velocity.angle()

## Liftoff camera kick, decaying to nothing. Drives `camera.offset` rather than the
## camera's position: `_position_ground()` derives the ground and the launch pad from
## `camera.global_position`, so shaking that would drag the world with it.
func _update_shake(delta: float) -> void:
	if shake_remaining <= 0.0:
		return
	shake_remaining = maxf(shake_remaining - delta, 0.0)
	var falloff: float = shake_remaining / Visuals.SHAKE_TIME
	var mag: float = Visuals.SHAKE_MAGNITUDE * falloff * falloff # ease out
	camera.offset = Vector2(randf_range(-mag, mag), randf_range(-mag, mag))
	if shake_remaining <= 0.0:
		camera.offset = Vector2.ZERO # always settle back exactly

## One deterministic simulation step operating on the sim state (not the
## rendered ship transform), with win/fail detection.
func _advance_sim(dt: float) -> void:
	var step: Array = _sim_step(sim_pos, ship_velocity, dt)
	sim_pos = step[0]
	ship_velocity = step[1]
	current_path.append(sim_pos)
	flight_steps += 1

	# WIN: actually strike the target -- no margin, the path must run through it.
	if sim_pos.distance_to(target_planet.global_position) <= target_planet.physical_radius:
		_win()
		return
	# LAND on a waypoint: the path must run through it (no margin), then park and
	# let the player relaunch from it.
	for wp in waypoints:
		if not waypoint_used.get(wp, false) and sim_pos.distance_to(wp.global_position) <= wp.physical_radius:
			_land_waypoint(wp)
			return
	# FAIL (explode): hit any blocker or moon.
	if _hit_any_blocker(sim_pos) or _hit_any_moon(sim_pos):
		_fail()
		return
	# FAIL (drift): left the world boundary.
	if _out_of_bounds(sim_pos):
		_fail()
		return
	if flight_steps >= MAX_FLIGHT_STEPS:
		_fail()

func _out_of_bounds(pos: Vector2) -> bool:
	var center: Vector2 = base_screen * 0.5
	var half: Vector2 = base_screen * world_boundary_scale * 0.5
	return abs(pos.x - center.x) > half.x or abs(pos.y - center.y) > half.y

func _win() -> void:
	state = State.WON
	completed_levels[current_level] = true
	ship.thrust = 0.0
	Effects.flare(self, sim_pos, TARGET_COLOR)
	_capture_solution() # grab the winning route before it becomes a faded trail
	_finalize_trail()
	if _has_next_level():
		win_title.text = "Landed!"
		next_button.text = "Next Level"
	else:
		win_title.text = "You win!"
		next_button.text = "Play Again"
	# Hold the modal back for a beat so the landing reads before the UI appears.
	win_modal_pending = true
	win_modal_timer = WIN_MODAL_DELAY

func _fail() -> void:
	state = State.FAILED
	fail_timer = FAIL_RESET_DELAY
	ship.thrust = 0.0
	# Only a collision leaves a wreck. Drifting out of bounds or timing out means
	# the ship is still out there somewhere -- no explosion for those.
	if _hit_any_blocker(sim_pos) or _hit_any_moon(sim_pos):
		Effects.explode(self, sim_pos)
		ship.visible = false
	_finalize_trail()

# ---------------------------------------------------------------------------
# Trails: keep the last 3 flight paths on screen, oldest most faded.
# ---------------------------------------------------------------------------
func _finalize_trail() -> void:
	if current_path.size() < 2:
		return
	var line: Line2D = Line2D.new()
	line.points = current_path
	line.width = 2.0
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	trail_container.add_child(line)
	trails.append(line)
	while trails.size() > MAX_TRAILS:
		var old = trails.pop_front()
		old.queue_free()
	_recolor_trails()
	current_path = PackedVector2Array()

func _recolor_trails() -> void:
	var n: int = trails.size()
	for i in range(n):
		var age: int = n - 1 - i # 0 = newest
		var alpha: float = clampf(0.9 - 0.3 * float(age), 0.25, 0.9)
		trails[i].default_color = Color(0.85, 0.87, 0.95, alpha)

# ---------------------------------------------------------------------------
# Background (drawn behind all children: parent draws first).
# ---------------------------------------------------------------------------
func _draw() -> void:
	draw_rect(Rect2(-900, -900, 3240, 3800), Visuals.SPACE_COLOR)
	for s in stars:
		var col: Color = s["color"]
		# The brightest few get a soft bloom, so they sit in front of the rest.
		if s["bright"]:
			draw_circle(s["pos"], s["radius"] * 3.0, Color(col.r, col.g, col.b, 0.10))
		draw_circle(s["pos"], s["radius"], col)
