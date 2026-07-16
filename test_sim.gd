extends SceneTree

# Regression/verification for the chosen tuned defaults. Mirrors main.gd exactly.

const G := 1.0
const DT := 1.0 / 60.0
const LAUNCH_SPEED := 225.0
const LANDING := 80.0
const BOUNDARY_SCALE := 2.5
const MAX_STEPS := 60 * 30
const W_RPHYS := 40.0
const INFLUENCE := 200.0

var launch_pos := Vector2(360, 1135)
var w_pos := Vector2(360, 840)
var w_mass := 400000.0
var t_pos := Vector2(250, 300)
var t_mass := 25000.0
var base := Vector2(720, 1280)

func accel(pos: Vector2) -> Vector2:
	var a := Vector2.ZERO
	var d1 := w_pos - pos
	a += d1.normalized() * (G * w_mass / maxf(d1.length_squared(), 1.0))
	var d2 := t_pos - pos
	a += d2.normalized() * (G * t_mass / maxf(d2.length_squared(), 1.0))
	return a

func oob(p: Vector2) -> bool:
	var c := base * 0.5
	var h := base * BOUNDARY_SCALE * 0.5
	return absf(p.x - c.x) > h.x or absf(p.y - c.y) > h.y

# returns [outcome, min_dist_wrong, max_abs_x_off, max_abs_y_off]
func sim(angle_deg: float) -> Array:
	var dir := Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
	var pos := launch_pos
	var vel := dir * LAUNCH_SPEED
	var min_w := 1e9
	for i in range(MAX_STEPS):
		vel += accel(pos) * DT
		pos += vel * DT
		min_w = minf(min_w, pos.distance_to(w_pos))
		if pos.distance_to(t_pos) <= LANDING:
			return ["WIN", min_w]
		if pos.distance_to(w_pos) <= W_RPHYS:
			return ["EXPLODE", min_w]
		if oob(pos):
			return ["DRIFT", min_w]
	return ["TIMEOUT", min_w]

func _init() -> void:
	var direct := rad_to_deg((t_pos - launch_pos).angle())
	var dres := sim(direct)
	print("Direct-at-target angle = %.1f deg -> %s (proves assist %s)" % [
		direct, dres[0], ("NECESSARY" if dres[0] != "WIN" else "NOT necessary!")])
	var wins: Array = []
	var best := 1e9
	var best_a := 0.0
	var a := -140.0
	while a <= -40.0:
		var r := sim(a)
		if r[0] == "WIN":
			wins.append(a)
		if r[1] < best and r[0] == "WIN":
			best = r[1]
			best_a = a
		a += 0.5
	if wins.is_empty():
		print("FAIL: no winning angle!")
	else:
		print("Winning angles: %.1f .. %.1f deg (count=%d)" % [wins[0], wins[-1], wins.size()])
		print("Best winning angle %.1f deg, min distance to wrong mass = %.1f px (influence=%d) -> assist used: %s" % [
			best_a, best, int(INFLUENCE), str(best < INFLUENCE)])
	quit()
