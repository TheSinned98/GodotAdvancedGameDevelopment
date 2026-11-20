shader_type canvas_item;
render_mode unshaded;

// Numerische Hoehen-/Vegetationsdaten, keine sRGB-Farbtextur.
uniform sampler2D terrain_data : filter_linear, repeat_disable;
uniform float chunk_cells = 30.0;
uniform vec2 chunk_pixels = vec2(480.0);
uniform float sea_level = 0.40;
uniform float mountain_level = 0.72;
uniform float detail_strength : hint_range(0.0, 0.20) = 0.045;

uniform vec4 deep_color : source_color = vec4(0.12, 0.28, 0.43, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.24, 0.55, 0.61, 1.0);
uniform vec4 sand_color : source_color = vec4(0.87, 0.77, 0.53, 1.0);
uniform vec4 dry_color : source_color = vec4(0.60, 0.59, 0.35, 1.0);
uniform vec4 grass_color : source_color = vec4(0.36, 0.55, 0.30, 1.0);
uniform vec4 forest_color : source_color = vec4(0.22, 0.43, 0.27, 1.0);
uniform vec4 rock_color : source_color = vec4(0.55, 0.53, 0.49, 1.0);

varying vec2 inner_uv;
varying vec2 world_pixel;

void vertex() {
	inner_uv = VERTEX / chunk_pixels;
	world_pixel = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Deterministisches Koernchen in Weltkoordinaten, nicht pro Chunk neu gestartet.
float grain(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	// Chunk-Grenzen liegen zwischen Texelzentren; der Rand bleibt unsichtbar.
	vec2 sample_uv = (inner_uv * chunk_cells + vec2(1.0)) / (chunk_cells + 2.0);
	vec2 fields = texture(terrain_data, sample_uv).rg;
	float height = fields.r;
	float plants = fields.g;

	vec3 water = mix(deep_color.rgb, shallow_color.rgb,
		smoothstep(sea_level - 0.12, sea_level - 0.01, height));
	vec3 land = mix(dry_color.rgb, grass_color.rgb, smoothstep(0.30, 0.57, plants));
	land = mix(land, forest_color.rgb, smoothstep(0.55, 0.84, plants));
	land = mix(sand_color.rgb, land, smoothstep(sea_level + 0.018, sea_level + 0.055, height));
	land = mix(land, rock_color.rgb,
		smoothstep(mountain_level - 0.035, mountain_level + 0.055, height));

	vec3 surface = mix(water, land, smoothstep(sea_level - 0.010, sea_level + 0.014, height));
	float detail = (grain(floor(world_pixel / 2.0)) - 0.5) * detail_strength;
	COLOR = vec4(clamp(surface + vec3(detail), vec3(0.0), vec3(1.0)), 1.0);
}
