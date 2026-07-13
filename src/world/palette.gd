class_name Palette
## Shared, cached materials. Reusing material instances keeps draw state
## changes (and shader compiles) low on mobile.

static var _cache: Dictionary = {}
static var _vertex_mat: StandardMaterial3D = null
static var _foliage_mat: ShaderMaterial = null
static var _water_mat: ShaderMaterial = null
static var _window_mat: StandardMaterial3D = null
static var _lamp_mat: StandardMaterial3D = null
static var _wetness := -1.0

## Water: three directional waves with analytic normals, Schlick fresnel
## deep/shallow mix and a high-frequency normal shimmer for sun glints.
## Purely procedural (no textures) and cheap enough for the mobile renderer.
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.22, 0.56, 0.60, 0.60);
uniform vec4 deep_color : source_color = vec4(0.03, 0.22, 0.36, 0.94);
uniform float wave_height = 0.14;
uniform float wave_speed = 1.1;
uniform float shimmer = 0.22;

varying vec3 world_pos;

// Sum of three directional sine waves; returns (height, d/dx, d/dz).
vec3 wave_dh(vec2 p, float t) {
	vec2 d1 = normalize(vec2(1.0, 0.35));
	vec2 d2 = normalize(vec2(-0.7, 1.0));
	vec2 d3 = normalize(vec2(0.3, -1.0));
	float p1 = dot(p, d1) * 0.24 + t;
	float p2 = dot(p, d2) * 0.31 + t * 1.27;
	float p3 = dot(p, d3) * 0.52 + t * 1.71;
	float h = 0.55 * sin(p1) + 0.32 * sin(p2) + 0.13 * sin(p3);
	vec2 g = 0.55 * 0.24 * cos(p1) * d1
		+ 0.32 * 0.31 * cos(p2) * d2
		+ 0.13 * 0.52 * cos(p3) * d3;
	return vec3(h, g);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 hg = wave_dh(world_pos.xz, TIME * wave_speed);
	VERTEX.y += hg.x * wave_height;
	NORMAL = normalize(vec3(-hg.y * wave_height * 4.0, 1.0, -hg.z * wave_height * 4.0));
}

void fragment() {
	// Fine ripple detail on top of the vertex waves (world-space, no texture).
	float rx = sin(world_pos.x * 2.1 + TIME * 1.9) * sin(world_pos.z * 1.7 - TIME * 1.3);
	float rz = sin(world_pos.z * 2.4 - TIME * 2.2) * sin(world_pos.x * 1.5 + TIME * 1.1);
	vec3 n = normalize(NORMAL + mat3(VIEW_MATRIX) * vec3(rx * shimmer, 0.0, rz * shimmer));
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	vec4 col = mix(shallow_color, deep_color, clamp(0.25 + fres * 0.9, 0.0, 1.0));
	ALBEDO = col.rgb;
	ALPHA = clamp(col.a + fres * 0.25, 0.0, 0.97);
	NORMAL = n;
	ROUGHNESS = 0.06;
	SPECULAR = 0.65;
}
"""

## Vertex-colored foliage with wind sway. Sway strength ramps with height
## above the trunk base so roots stay planted; phase is offset per instance
## position so a forest never moves in lockstep.
const FOLIAGE_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float sway_strength = 0.09;
uniform float sway_speed = 1.3;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float ph = TIME * sway_speed + root.x * 0.31 + root.z * 0.27;
	float amt = clamp((VERTEX.y - 0.5) * 0.22, 0.0, 1.0) * sway_strength;
	VERTEX.x += (sin(ph) + 0.4 * sin(ph * 2.3)) * amt;
	VERTEX.z += (cos(ph * 0.8) + 0.4 * sin(ph * 1.7)) * amt;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""


## Flat-color material, cached per color/params.
static func mat(color: Color, rough: float = 0.92, metallic: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%.2f" % [color.to_html(), rough, metallic, emission]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_cache[key] = m
	return m


## Material for meshes that carry vertex colors (terrain, generated props).
static func vertex_mat() -> StandardMaterial3D:
	if _vertex_mat == null:
		_vertex_mat = StandardMaterial3D.new()
		_vertex_mat.vertex_color_use_as_albedo = true
		_vertex_mat.roughness = 0.95
		# Generated geometry ships explicit outward normals; disabling culling
		# makes winding irrelevant (safety > the small overdraw cost here).
		_vertex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _vertex_mat


## Vertex-colored material with wind sway, shared by every tree mesh.
static func foliage_mat() -> ShaderMaterial:
	if _foliage_mat == null:
		var shader := Shader.new()
		shader.code = FOLIAGE_SHADER
		_foliage_mat = ShaderMaterial.new()
		_foliage_mat.shader = shader
	return _foliage_mat


static func water_mat() -> ShaderMaterial:
	if _water_mat == null:
		var shader := Shader.new()
		shader.code = WATER_SHADER
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = shader
	return _water_mat


## Shared window material; world raises emission at night so every window
## in the town lights up with a single material change.
static func window_mat() -> StandardMaterial3D:
	if _window_mat == null:
		_window_mat = StandardMaterial3D.new()
		_window_mat.albedo_color = Color(0.35, 0.48, 0.55)
		_window_mat.roughness = 0.15
		_window_mat.metallic = 0.4
		_window_mat.emission_enabled = true
		_window_mat.emission = Color(1.0, 0.85, 0.55)
		_window_mat.emission_energy_multiplier = 0.0
	return _window_mat


## Shared street-lamp head material (emission toggled at night).
static func lamp_mat() -> StandardMaterial3D:
	if _lamp_mat == null:
		_lamp_mat = StandardMaterial3D.new()
		_lamp_mat.albedo_color = Color(0.9, 0.88, 0.75)
		_lamp_mat.emission_enabled = true
		_lamp_mat.emission = Color(1.0, 0.9, 0.6)
		_lamp_mat.emission_energy_multiplier = 0.0
	return _lamp_mat


static func set_night_lights(on: bool) -> void:
	# Energies sit above the glow HDR threshold so lit windows and lamp
	# heads bloom softly at night on medium/high quality.
	window_mat().emission_energy_multiplier = 2.0 if on else 0.0
	lamp_mat().emission_energy_multiplier = 3.0 if on else 0.0


## CPU mirror of the water shader's vertex waves, so floating gameplay
## objects (fishing bobber, swimmer, flooded cars) ride the same surface
## the GPU renders. Keep the constants in sync with WATER_SHADER.
static func wave_height_at(p: Vector2, time_s: float) -> float:
	var d1 := Vector2(1.0, 0.35).normalized()
	var d2 := Vector2(-0.7, 1.0).normalized()
	var d3 := Vector2(0.3, -1.0).normalized()
	var t := time_s * 1.1  # wave_speed
	var h := 0.55 * sin(p.dot(d1) * 0.24 + t) \
		+ 0.32 * sin(p.dot(d2) * 0.31 + t * 1.27) \
		+ 0.13 * sin(p.dot(d3) * 0.52 + t * 1.71)
	return h * 0.14  # wave_height


## Rain response shared by the whole generated world: wet ground turns
## reflective and the wind picks up in the trees. One material write each.
static func set_wetness(amount: float) -> void:
	if absf(amount - _wetness) < 0.02:
		return
	_wetness = amount
	vertex_mat().roughness = lerpf(0.95, 0.55, amount)
	foliage_mat().set_shader_parameter("sway_strength", lerpf(0.09, 0.24, amount))
	foliage_mat().set_shader_parameter("sway_speed", lerpf(1.3, 2.1, amount))
