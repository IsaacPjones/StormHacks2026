shader_type spatial;
render_mode blend_mix, depth_draw_never, diffuse_burley, specular_disabled;

uniform sampler2D greenery_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D greenery_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 greenery_tint : source_color = vec4(0.55, 0.68, 0.50, 1.0);
uniform float detail_mip_bias : hint_range(-1.0, 0.0, 0.1) = -0.5;
uniform float normal_strength : hint_range(0.0, 2.0, 0.05) = 0.8;
uniform float texture_scale : hint_range(0.01, 2.0, 0.01) = 0.08;
uniform float patch_scale : hint_range(0.01, 1.0, 0.01) = 0.18;
uniform float greenery_coverage : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float blend_softness : hint_range(0.01, 0.4, 0.01) = 0.06;
uniform float greenery_opacity : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float surface_height : hint_range(-10.0, 10.0, 0.1) = 0.0;
uniform float underground_fade_depth : hint_range(0.1, 10.0, 0.1) = 1.5;
uniform vec2 pattern_offset = vec2(13.4, 7.8);

varying vec3 world_position;
varying vec3 world_normal;

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	vec2 curve = local * local * (3.0 - 2.0 * local);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), curve.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), curve.x), curve.y);
}

float patch_noise(vec2 point) {
	float result = 0.0;
	float amplitude = 0.533333;
	for (int octave = 0; octave < 4; octave++) {
		result += noise(point) * amplitude;
		point = point * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return result;
}

vec3 triplanar(sampler2D tex, vec3 point, vec3 weights) {
	return texture(tex, point.yz, detail_mip_bias).rgb * weights.x
		+ texture(tex, point.xz, detail_mip_bias).rgb * weights.y
		+ texture(tex, point.xy, detail_mip_bias).rgb * weights.z;
}

vec3 normal_detail(vec3 point, vec3 weights) {
	vec2 x = texture(greenery_normal, point.yz, detail_mip_bias).rg * 2.0 - 1.0;
	vec2 y = texture(greenery_normal, point.xz, detail_mip_bias).rg * 2.0 - 1.0;
	vec2 z = texture(greenery_normal, point.xy, detail_mip_bias).rg * 2.0 - 1.0;
	return vec3(0.0, x.x, x.y) * weights.x + vec3(y.x, 0.0, y.y) * weights.y + vec3(z.x, z.y, 0.0) * weights.z;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 ground_normal = normalize(world_normal);
	vec3 weights = pow(abs(ground_normal), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	vec3 point = world_position * texture_scale;
	float pattern = patch_noise(world_position.xz * patch_scale + pattern_offset);
	float threshold = 1.0 - greenery_coverage;
	float greenery = smoothstep(threshold - blend_softness, threshold + blend_softness, pattern);
	if (greenery_coverage <= 0.0) { greenery = 0.0; }
	if (greenery_coverage >= 1.0) { greenery = 1.0; }
	// Keep buried chambers and vertical cutaway walls looking like soil.
	greenery *= smoothstep(0.25, 0.75, ground_normal.y);
	greenery *= smoothstep(surface_height - underground_fade_depth, surface_height, world_position.y);
	// The original StandardMaterial3D draws the soil first, including its normals.
	// This light overlay preserves that detail through the translucent greenery.
	ALBEDO = triplanar(greenery_texture, point, weights) * greenery_tint.rgb;
	vec3 detail = normal_detail(point, weights);
	detail -= ground_normal * dot(detail, ground_normal);
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(ground_normal + detail * normal_strength));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ALPHA = greenery * greenery_opacity;
}
