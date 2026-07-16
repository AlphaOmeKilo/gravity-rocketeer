shader_type canvas_item;

// One shader for every celestial body: target, blockers, red giant, moons.
// Replaces the old 24x concentric draw_circle() stack, which banded visibly and
// cost a lot of overdraw. Archetype differences (rocky / star / moon) come from
// uniforms, not separate code paths.
//
// Drawn on a ColorRect whose half-extent covers the influence radius, so UV 0..1
// maps to -1..1 in `p` below, and all radii arrive pre-divided by that extent.

// 0 = rocky, 1 = giant (wider corona), 2 = moon (high albedo).
// All three are lit the same way -- kind only widens the corona or lifts albedo.
uniform int kind : hint_range(0, 2) = 0;

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

	// Moons are high-albedo: they hold more light through the terminator.
	float mix_amount = kind == 2 ? terminator_mix * 0.7 : terminator_mix;
	float shade = mix(1.0 - mix_amount, 1.0, lambert);
	vec3 lit = body_color.rgb * shade;

	// Rim light on the edge facing the light.
	float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), rim_power) * lambert;
	lit += vec3(rim * rim_strength) * body_color.rgb;

	float halo_alpha = halo * halo_strength * 0.55;
	COLOR = vec4(mix(body_color.rgb, lit, disc), max(halo_alpha, disc));
}
