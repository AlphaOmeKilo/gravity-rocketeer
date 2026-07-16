# In-game art pass — levels 1–6

Goal: set the visual benchmark for future levels. Direction: **lit but restrained** —
flat base colors stay, one consistent light direction adds a soft terminator and rim.
Readability of the gravity field always wins over richness.

## Shared foundation

- [ ] `visuals.gd` — one place for the art constants every system reads:
      `LIGHT_DIR` (single global light, from upper-left), palette, halo tuning.
      Bodies, ground, and ship all reference it so the scene stays coherent.

## 1. Bodies + glow fix (highest leverage — touches all 6 levels)

- [ ] `body.gdshader` — replaces the 24× `draw_circle` stack in `gravity_body.gd:56-60`
      that causes the visible concentric banding.
      - Smooth halo falloff over `influence_radius` (one gradient, no bands)
      - Disc with `smoothstep` AA edge at `physical_radius`
      - Sphere-normal lambert terminator, restrained (~0.35 mix)
      - Rim light on the lit edge
- [ ] `gravity_body.gd` — swap `_draw()` for a `ColorRect` + `ShaderMaterial` child.
      Drive uniforms from the existing `@export` setters so editor tuning still works.
      Quad half-extent = `max(influence_radius, physical_radius) * 1.05` (guard the
      case where influence < physical).
- [ ] Keep `show_influence` working (halo strength → 0 when false).
- [ ] Per-type character within one shader, via uniforms only:
      star (red giant) emits, rocky (blocker/target) is lit, moon is lit + high albedo.

## 2. Horizon atmosphere

- [ ] `earth.gd` — atmosphere band above the surface curve. Use `draw_polygon()` with
      **per-vertex colors** (triangle strip along the curve, opaque tint at surface →
      alpha 0 above). No shader needed; works on every renderer.
- [ ] Subtle ground shading — lit at the surface, darker toward the bottom, same trick.

## 3. Starfield depth

- [ ] `main.gd` `_generate_stars()` — replace the 160 uniform 1.4px/0.65α dots.
      - Magnitude skew (`pow(randf(), 3)`) — mostly faint, a few bright
      - Color temperature variance — cool blue-white ↔ warm amber, mostly white
      - Keep the fixed seed so levels are reproducible
- [ ] NOTE: camera is static (never written in `main.gd`), so no parallax. Depth comes
      from magnitude/color alone. No twinkle — it would force a full-screen redraw
      every frame while idle, for little gain.

## 4. Ship + feedback moments

- [ ] `ship.gd` — readable silhouette; soft glow so it holds up against the field.
- [ ] Flame is **launch-only**. Flight is ballistic (`_advance_sim()` applies gravity
      only), so the always-on flame nub at `ship.gd:19` is wrong today. Burn on launch,
      cut out, coast dark with a faint engine ember.
- [ ] Explosion on `_fail()` — currently no art at all. `CPUParticles2D` (safest across
      mobile/gl_compat) burst at the impact point.
- [ ] Landing flare on `_win()` — expanding ring pulse + brief flash at touchdown.

## Verification

- [ ] Render levels 1–6 offscreen via `shot.gd`, compare against the pre-change shots.
- [ ] **Build and run on the iOS Simulator** — this is the real target. The desktop
      preview is `gl_compatibility`; the game ships on the mobile renderer. A shader
      that previews fine can still break there, so the sim run is the gate, not a bonus.
- [ ] Confirm gravity-field readability didn't regress on level 5 (red giant) and
      level 6 (twin moons) — the two busiest fields.

## Review

All four areas done. New files: `visuals.gd`, `body.gdshader`, `effects.gd`.
Changed: `gravity_body.gd`, `earth.gd`, `ship.gd`, `main.gd`.

What landed:
- **Bodies**: one `body.gdshader` on a ColorRect per body replaces the 24x
  `draw_circle` stack. Banding gone, halos smooth, and rocky/giant/moon now differ by
  uniform rather than by code path. Moons hold light through the terminator so they
  read high-albedo.
- **Every body is lit identically, including the red giant.** First pass had the
  giant self-illuminate (no terminator) on the theory that a star emits. More
  physically honest, but it read as flat paint beside the lit spheres and broke the
  material language -- the whole point of the shared shader. Corrected: the giant
  gets the same lambert + rim as everything else, and carries its scale through the
  wider corona instead. Rule of thumb for future bodies: shading model is the
  family; kind only tunes corona reach and albedo.
- **Atmosphere**: `draw_polygon()` with per-vertex colours, no shader. Biggest
  single win per line changed.
- **Stars**: 260 stars, cubed-uniform magnitude skew + colour temperature. No
  parallax (camera is static) and no twinkle (would force a full-screen redraw while
  idle).
- **Ship + feedback**: new silhouette, launch-only burn, explosion on collision,
  flare on landing (target and waypoint).

Two findings from reading the code, both acted on:
- The flight is ballistic, so the old always-on flame nub was lying. Flame is now
  launch-only.
- The camera is never moved, which ruled out the parallax plan.

### Verification — what was and was NOT proven

- All 6 levels render clean offscreen (`shot.gd`), compared against pre-change shots.
- Ran on the iOS Simulator. Device geometry sampled on-device confirmed
  `ship == pad == (360, 1780.4)` at the phone's real 1206x2622 — the ship sits on the
  pad correctly at that aspect.
- **NOT proven: the mobile (Vulkan/Metal) renderer.** The iOS *Simulator* falls back
  to OpenGL ES 3.0 despite `rendering_method="mobile"` (it dlopens OpenGLES.framework
  and writes `shader_cache/CanvasShaderGLES3/`). So the sim only re-tested the same
  GLES3 path as the desktop preview. The plan above assumed the sim was the gate;
  that assumption was wrong. `body.gdshader` uses only basic math and takes its
  AA width as a uniform rather than using `fwidth()`, so the risk is low — but it
  needs one run on a physical iPhone to actually be verified.

### Open / judgement calls

- Halo falloff is `pow(1 - d, 2.5)`, which reaches its edge a bit tighter than the old
  disc-stack ramp. Looks better, but the influence radius is gameplay-relevant (the
  aim preview fades inside it), so it's worth a play-test.
- `shot.gd` (offscreen level renderer) is left in the project root as a dev tool.
