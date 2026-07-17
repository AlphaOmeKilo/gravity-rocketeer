shader_type canvas_item;

// One shader for every celestial body: target, blockers, red giant, moons.
// Replaces the old 24x concentric draw_circle() stack, which banded visibly and
// cost a lot of overdraw. Archetype differences (rocky / star / moon) come from
// uniforms, not separate code paths.
//
// Drawn on a ColorRect whose half-extent covers the influence radius, so UV 0..1
// maps to -1..1 in `p` below, and all radii arrive pre-divided by that extent.

// 0 = rocky, 1 = giant (wider corona), 2 = moon (high albedo), 3 = station
// (no disc, just the well glow -- a Station node draws the structure).
uniform int kind : hint_range(0, 3) = 0;

uniform vec4 body_color : source_color = vec4(0.95, 0.5, 0.15, 1.0);

// Radii as a fraction of the quad's half-extent.
uniform float physical_frac : hint_range(0.0, 1.0) = 0.3;
uniform float influence_frac : hint_range(0.0, 1.0) = 1.0;

// One pixel, in the same normalised units as `p`. Passed in rather than derived
// with fwidth() so edge antialiasing behaves identically on the mobile and
// compatibility renderers.
uniform float px = 0.004;

uniform float halo_strength : hint_range(0.0, 2.0) = 1.0;

uniform vec3 light_dir = vec3(-0.66, -0.66, 0.51);
uniform float terminator_mix : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;

// --- Surface detail. Mottles the disc between two tints of body_color so a body
// reads as real terrain (continents, maria, mineral streaks) instead of flat
// paint. detail_strength = 0 (moons, waypoints) keeps the old flat look exactly.
// detail_seed offsets the noise so no two bodies share the same surface.
uniform vec4 detail_dark : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 detail_light : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float detail_strength : hint_range(0.0, 1.0) = 0.0;
uniform float detail_seed = 0.0;

// Value noise (hash-based). Deterministic, cheap, no texture -- so it renders the
// same on the mobile and compatibility renderers.
float hash21(vec2 x) {
	return fract(sin(dot(x, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 x) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(x);
		x *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);

	// --- Halo: one smooth falloff to the influence radius. No bands.
	float halo = 0.0;
	if (influence_frac > 0.001) {
		float hd = clamp(d / influence_frac, 0.0, 1.0);
		// pow() curve keeps the core bright and lets the edge reach true zero,
		// so there is no hard ring where the quad ends.
		halo = pow(1.0 - hd, 2.5);
	}
	// A giant's corona carries further than a rocky body's well.
	if (kind == 1) {
		halo = pow(halo, 0.72);
	}

	// --- Disc: antialiased edge at the physical radius.
	float aa = px * 1.5;
	float disc = 1.0 - smoothstep(physical_frac - aa, physical_frac + aa, d);

	// --- Shading. Treat the disc as a sphere and light it from one global source.
	// Every body gets this, including the giant. Letting the giant self-illuminate
	// was more physically honest but made it read as flat paint next to the lit
	// spheres -- it broke the material language. Scale is carried by the corona
	// above, not by a different shading model.
	float r = clamp(d / max(physical_frac, 0.0001), 0.0, 1.0);
	vec3 n = vec3(p / max(physical_frac, 0.0001), sqrt(max(0.0, 1.0 - r * r)));
	float lambert = clamp(dot(normalize(n), normalize(light_dir)), 0.0, 1.0);

	// --- Surface tint: pull body_color toward its dark/light detail colours by a
	// noise field, in units of body radii so feature scale is consistent across
	// sizes. Low noise = dark lowlands, high noise = bright highlands.
	vec2 nc = (p / max(physical_frac, 0.0001)) * 3.0 + vec2(detail_seed);
	float m = fbm(nc);
	vec3 surface = body_color.rgb;
	float lo = smoothstep(0.55, 0.28, m);
	float hi = smoothstep(0.60, 0.82, m);
	surface = mix(surface, detail_dark.rgb, lo * detail_strength);
	surface = mix(surface, detail_light.rgb, hi * detail_strength);

	// Moons are high-albedo: they hold more light through the terminator.
	float mix_amount = kind == 2 ? terminator_mix * 0.7 : terminator_mix;
	float shade = mix(1.0 - mix_amount, 1.0, lambert);
	vec3 lit = surface * shade;

	// Rim light on the edge facing the light.
	float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), rim_power) * lambert;
	lit += vec3(rim * rim_strength) * surface;

	// The gravity-well glow keeps its own brightened tint: a dim, greyed rocky body
	// would otherwise vanish into space. Lifting toward white preserves the body's
	// hue (so wells still read by colour) while guaranteeing the well stays visible.
	vec3 halo_col = mix(body_color.rgb, vec3(1.0), 0.4);
	float halo_alpha = halo * halo_strength * 0.55;
	// A station has no planet disc -- only its well glow is drawn here; the hull is
	// a separate Station node on top.
	float disc_draw = kind == 3 ? 0.0 : disc;
	COLOR = vec4(mix(halo_col, lit, disc_draw), max(halo_alpha, disc_draw));
}
