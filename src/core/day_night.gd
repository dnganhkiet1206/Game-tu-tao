extends Node
## Day/night cycle + light weather system.
## One in-game day lasts 24 real minutes (1 game hour per minute).
## The world registers its sun / environment here; this node drives them.
##
## Lighting is keyframed over the 24 h clock (golden hour, blue night,
## dawn mist) and blended with the rain state. A single DirectionalLight3D
## plays both sun and moon: it re-aims and re-tints when the sun is down,
## so nights are moonlit without paying for a second shadow-casting light.

const HOURS_PER_SECOND := 1.0 / 60.0  # 1 game hour per real minute

var time_hours: float = 7.5
var day: int = 1
var weather: String = "clear"  # "clear" | "rain"
var rain_amount: float = 0.0   # 0..1 smooth blend used by audio/particles

var sun: DirectionalLight3D = null
var environment: Environment = null
var sky_material: ProceduralSkyMaterial = null

var _last_hour_int: int = -1
var _weather_timer: float = 0.0
var _sun_shadow_on := false
var _rng := RandomNumberGenerator.new()

# --- lighting keyframes ([hour, value] pairs; sampled with 24 h wrap) --------

const SUN_COLOR_KEYS := [
	[6.0, Color(1.0, 0.55, 0.3)],    # sunrise ember
	[7.5, Color(1.0, 0.78, 0.55)],   # golden hour
	[10.0, Color(1.0, 0.95, 0.85)],
	[14.0, Color(1.0, 0.98, 0.92)],  # clean noon-ish white
	[17.0, Color(1.0, 0.85, 0.6)],   # afternoon warmth
	[18.5, Color(1.0, 0.55, 0.28)],  # sunset
	[19.3, Color(0.85, 0.4, 0.3)],
]
const SUN_ENERGY_KEYS := [
	[5.4, 0.0], [6.3, 0.5], [8.0, 1.1], [12.0, 1.4],
	[16.5, 1.15], [18.4, 0.5], [19.4, 0.0],
]
const MOON_ENERGY_KEYS := [
	[4.4, 0.22], [5.6, 0.0], [19.2, 0.0], [20.4, 0.22],
]
const SKY_TOP_KEYS := [
	[4.5, Color(0.02, 0.04, 0.10)],
	[6.0, Color(0.16, 0.2, 0.38)],
	[7.5, Color(0.3, 0.45, 0.72)],
	[12.0, Color(0.3, 0.55, 0.86)],
	[17.0, Color(0.32, 0.48, 0.76)],
	[18.6, Color(0.26, 0.3, 0.55)],
	[19.8, Color(0.07, 0.09, 0.2)],
	[21.0, Color(0.02, 0.04, 0.10)],
]
const SKY_HORIZON_KEYS := [
	[4.5, Color(0.06, 0.08, 0.16)],
	[5.8, Color(0.55, 0.32, 0.3)],
	[6.6, Color(0.98, 0.6, 0.38)],   # sunrise band
	[9.0, Color(0.72, 0.82, 0.92)],
	[15.0, Color(0.76, 0.85, 0.94)],
	[17.5, Color(0.88, 0.74, 0.55)],
	[18.6, Color(0.98, 0.5, 0.28)],  # sunset band
	[19.6, Color(0.4, 0.2, 0.22)],
	[20.6, Color(0.06, 0.08, 0.16)],
]
const SKY_ENERGY_KEYS := [
	[5.0, 0.35], [7.0, 0.9], [12.0, 1.0], [18.0, 0.9], [20.0, 0.4], [21.5, 0.35],
]
const AMBIENT_COLOR_KEYS := [
	[5.0, Color(0.3, 0.36, 0.55)],   # blue night
	[6.5, Color(0.7, 0.55, 0.5)],    # warm dawn bounce
	[9.0, Color(0.82, 0.88, 1.0)],
	[16.0, Color(0.85, 0.88, 0.98)],
	[18.5, Color(0.75, 0.55, 0.45)], # dusk bounce
	[20.0, Color(0.3, 0.36, 0.55)],
]
const AMBIENT_ENERGY_KEYS := [
	[5.0, 0.34], [7.0, 0.6], [10.0, 1.0], [17.0, 0.85], [19.0, 0.5], [20.5, 0.34],
]
const FOG_COLOR_KEYS := [
	[5.0, Color(0.05, 0.07, 0.13)],
	[6.5, Color(0.7, 0.55, 0.45)],   # dawn haze catches the sun
	[10.0, Color(0.68, 0.78, 0.88)],
	[17.5, Color(0.75, 0.68, 0.58)],
	[19.0, Color(0.35, 0.25, 0.28)],
	[20.5, Color(0.05, 0.07, 0.13)],
]
const FOG_DENSITY_KEYS := [
	[4.5, 0.0055], [6.0, 0.009], [7.5, 0.006], [10.0, 0.0028],
	[17.0, 0.0032], [19.5, 0.005], [22.0, 0.0055],
]
const CLOUD_COLOR_KEYS := [
	[5.0, Color(0.12, 0.14, 0.24, 0.4)],  # night clouds barely there
	[6.5, Color(1.0, 0.6, 0.45, 0.55)],   # sunrise-lit bellies
	[10.0, Color(1.0, 1.0, 1.0, 0.5)],
	[16.5, Color(1.0, 0.96, 0.9, 0.5)],
	[18.6, Color(1.0, 0.55, 0.4, 0.6)],   # sunset-lit
	[20.2, Color(0.12, 0.14, 0.24, 0.4)],
]

const MOON_COLOR := Color(0.6, 0.7, 0.95)
const STORM_CLOUD := Color(0.3, 0.32, 0.36, 0.95)
const RAIN_SKY := Color(0.32, 0.35, 0.4)
const RAIN_FOG := Color(0.42, 0.46, 0.5)


func _ready() -> void:
	_rng.randomize()
	_weather_timer = _rng.randf_range(120.0, 300.0)


func register_sky(p_sun: DirectionalLight3D, p_env: Environment) -> void:
	sun = p_sun
	environment = p_env
	if environment.sky != null and environment.sky.sky_material is ProceduralSkyMaterial:
		sky_material = environment.sky.sky_material
	_sun_shadow_on = sun.shadow_enabled
	_apply()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	time_hours += delta * HOURS_PER_SECOND
	if time_hours >= 24.0:
		time_hours -= 24.0
		day += 1
	var hour_int := int(time_hours)
	if hour_int != _last_hour_int:
		_last_hour_int = hour_int
		Events.hour_changed.emit(hour_int)
	_update_weather(delta)
	_apply()


func _update_weather(delta: float) -> void:
	_weather_timer -= delta
	if _weather_timer <= 0.0:
		if weather == "clear":
			weather = "rain"
			_weather_timer = _rng.randf_range(60.0, 140.0)
		else:
			weather = "clear"
			_weather_timer = _rng.randf_range(240.0, 480.0)
		Events.weather_changed.emit(weather)
	var target := 1.0 if weather == "rain" else 0.0
	rain_amount = move_toward(rain_amount, target, delta * 0.15)


## 0 at midnight, 1 at noon — smooth daylight factor.
func daylight() -> float:
	return clampf(1.0 - absf(time_hours - 12.0) / 6.5, 0.0, 1.0)


func is_night() -> bool:
	return time_hours < 5.5 or time_hours > 19.0


func clock_text() -> String:
	var h := int(time_hours)
	var m := int((time_hours - h) * 60.0)
	return "%02d:%02d" % [h, m]


## Advance to next morning (used by sleeping in bed).
func sleep_to_morning() -> void:
	if time_hours > 6.5:
		day += 1
	time_hours = 6.5
	weather = "clear"
	rain_amount = 0.0
	_weather_timer = _rng.randf_range(240.0, 480.0)
	Events.weather_changed.emit(weather)


# --- keyframe sampling ---------------------------------------------------------

## Piecewise-linear sample of [hour, value] keys with wrap-around at 24 h.
static func _sample(keys: Array, h: float) -> Variant:
	var prev: Array = keys[keys.size() - 1]
	var prev_h: float = prev[0] - 24.0
	for key_v in keys:
		var key: Array = key_v
		var key_h: float = key[0]
		if h < key_h:
			return _lerp_value(prev[1], key[1], (h - prev_h) / (key_h - prev_h))
		prev_h = key_h
		prev = key
	var first: Array = keys[0]
	return _lerp_value(prev[1], first[1], (h - prev_h) / (first[0] + 24.0 - prev_h))


static func _lerp_value(a: Variant, b: Variant, t: float) -> Variant:
	if a is Color:
		return (a as Color).lerp(b, t)
	return lerpf(float(a), float(b), t)


# --- application ----------------------------------------------------------------

func _apply() -> void:
	if sun == null:
		return
	var h := time_hours
	var rain := rain_amount
	var rain_dim := 1.0 - rain * 0.5

	# Sun travels east->west; the same light re-aims as the moon at night.
	var t := h / 24.0
	var sun_angle := (t - 0.25) * TAU  # sunrise ~06:00
	var sun_energy: float = _sample(SUN_ENERGY_KEYS, h)
	var moon_energy: float = _sample(MOON_ENERGY_KEYS, h)
	if sun_energy >= moon_energy:
		sun.rotation = Vector3(-sun_angle, deg_to_rad(30.0), 0.0)
		sun.light_energy = sun_energy * rain_dim
		sun.light_color = _sample(SUN_COLOR_KEYS, h)
	else:
		sun.rotation = Vector3(-sun_angle + PI, deg_to_rad(-20.0), 0.0)
		sun.light_energy = moon_energy * (1.0 - rain * 0.7)
		sun.light_color = MOON_COLOR
	var want_shadow: bool = Game.quality >= 1 and sun.light_energy > 0.03
	if want_shadow != _sun_shadow_on:
		_sun_shadow_on = want_shadow
		sun.shadow_enabled = want_shadow

	if environment != null:
		environment.ambient_light_energy = float(_sample(AMBIENT_ENERGY_KEYS, h)) * rain_dim
		environment.ambient_light_color = _sample(AMBIENT_COLOR_KEYS, h)
		var fog_col: Color = _sample(FOG_COLOR_KEYS, h)
		environment.fog_light_color = fog_col.lerp(RAIN_FOG, rain * 0.7)
		environment.fog_density = lerpf(float(_sample(FOG_DENSITY_KEYS, h)), 0.014, rain)

	if sky_material != null:
		var top: Color = _sample(SKY_TOP_KEYS, h)
		sky_material.sky_top_color = top.lerp(RAIN_SKY.darkened(0.25), rain * 0.8)
		var horizon: Color = _sample(SKY_HORIZON_KEYS, h)
		horizon = horizon.lerp(RAIN_SKY, rain * 0.8)
		sky_material.sky_horizon_color = horizon
		sky_material.ground_horizon_color = horizon
		sky_material.ground_bottom_color = horizon.darkened(0.5)
		sky_material.sky_energy_multiplier = float(_sample(SKY_ENERGY_KEYS, h)) * (1.0 - rain * 0.3)
		var clouds: Color = _sample(CLOUD_COLOR_KEYS, h)
		sky_material.sky_cover_modulate = clouds.lerp(STORM_CLOUD, rain)

	# Wet ground + stronger tree sway while it rains (shared material writes).
	Palette.set_wetness(rain)
