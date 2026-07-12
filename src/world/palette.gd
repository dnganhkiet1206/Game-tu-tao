class_name Palette
## Shared, cached materials. Reusing material instances keeps draw state
## changes (and shader compiles) low on mobile.

static var _cache: Dictionary = {}
static var _vertex_mat: StandardMaterial3D = null
static var _water_mat: ShaderMaterial = null
static var _window_mat: StandardMaterial3D = null
static var _lamp_mat: StandardMaterial3D = null

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.25, 0.58, 0.62, 0.55);
uniform vec4 deep_color : source_color = vec4(0.04, 0.24, 0.38, 0.9);
uniform float wave_height = 0.14;
uniform float wave_speed = 1.2;

void vertex() {
	float pxa = VERTEX.x * 0.22 + TIME * wave_speed;
	float pzb = VERTEX.z * 0.19 + TIME * wave_speed * 0.83;
	VERTEX.y += (sin(pxa) + cos(pzb)) * wave_height * 0.5;
	NORMAL = normalize(vec3(-cos(pxa) * wave_height * 0.22, 1.0, sin(pzb) * wave_height * 0.19));
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec4 col = mix(shallow_color, deep_color, clamp(fres * 1.4, 0.0, 1.0));
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = 0.12;
	SPECULAR = 0.5;
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
		_window_mat.roughness = 0.2
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
	window_mat().emission_energy_multiplier = 1.6 if on else 0.0
	lamp_mat().emission_energy_multiplier = 2.2 if on else 0.0
