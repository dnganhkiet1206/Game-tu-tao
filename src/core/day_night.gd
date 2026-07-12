extends Node
## Day/night cycle + light weather system.
## One in-game day lasts 24 real minutes (1 game hour per minute).
## The world registers its sun / environment here; this node drives them.

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
var _rng := RandomNumberGenerator.new()

# Color keys for the sky through the day.
const SKY_NIGHT := Color(0.04, 0.06, 0.13)
const SKY_DAWN := Color(0.95, 0.55, 0.35)
const SKY_DAY := Color(0.38, 0.62, 0.85)
const SKY_DUSK := Color(0.9, 0.45, 0.3)
const HORIZON_NIGHT := Color(0.08, 0.1, 0.18)
const HORIZON_DAY := Color(0.75, 0.83, 0.9)


func _ready() -> void:
	_rng.randomize()
	_weather_timer = _rng.randf_range(120.0, 300.0)


func register_sky(p_sun: DirectionalLight3D, p_env: Environment) -> void:
	sun = p_sun
	environment = p_env
	if environment.sky != null and environment.sky.sky_material is ProceduralSkyMaterial:
		sky_material = environment.sky.sky_material
	_apply(0.0)


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
	_apply(delta)


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
	Events.weather_changed.emit(weather)


func _apply(_delta: float) -> void:
	if sun == null:
		return
	# Sun travels east->west; elevation peaks at noon.
	var t := time_hours / 24.0
	var sun_angle := (t - 0.25) * TAU  # sunrise ~06:00
	sun.rotation = Vector3(-sun_angle, deg_to_rad(30.0), 0.0)
	var dl := daylight()
	var rain_dim := 1.0 - rain_amount * 0.5
	sun.light_energy = maxf(dl * 1.2, 0.0) * rain_dim
	sun.light_color = Color(1.0, 0.75 + 0.25 * dl, 0.55 + 0.45 * dl)
	sun.shadow_enabled = Game.quality >= 1 and dl > 0.05

	if environment != null:
		var ambient := lerpf(0.35, 1.0, dl) * rain_dim
		environment.ambient_light_energy = ambient
		environment.ambient_light_color = Color(0.55, 0.65, 0.8).lerp(Color(0.9, 0.92, 1.0), dl)
		environment.fog_enabled = true
		var fog_night := Color(0.05, 0.07, 0.12)
		var fog_day := Color(0.65, 0.75, 0.85)
		var fog_col := fog_night.lerp(fog_day, dl)
		fog_col = fog_col.lerp(Color(0.45, 0.5, 0.55), rain_amount * 0.7)
		environment.fog_light_color = fog_col
		environment.fog_density = lerpf(0.0035, 0.012, rain_amount)

	if sky_material != null:
		var top := _sky_top_color()
		sky_material.sky_top_color = top.lerp(Color(0.3, 0.33, 0.38), rain_amount * 0.8)
		var horizon := HORIZON_NIGHT.lerp(HORIZON_DAY, dl)
		horizon = horizon.lerp(Color(0.4, 0.43, 0.47), rain_amount * 0.8)
		sky_material.sky_horizon_color = horizon
		sky_material.ground_horizon_color = horizon
		sky_material.ground_bottom_color = horizon.darkened(0.5)


func _sky_top_color() -> Color:
	var h := time_hours
	if h < 5.0 or h >= 21.0:
		return SKY_NIGHT
	if h < 7.0:
		return SKY_NIGHT.lerp(SKY_DAWN, (h - 5.0) / 2.0)
	if h < 9.0:
		return SKY_DAWN.lerp(SKY_DAY, (h - 7.0) / 2.0)
	if h < 17.0:
		return SKY_DAY
	if h < 19.0:
		return SKY_DAY.lerp(SKY_DUSK, (h - 17.0) / 2.0)
	return SKY_DUSK.lerp(SKY_NIGHT, (h - 19.0) / 2.0)
