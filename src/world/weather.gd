class_name Weather
extends Node3D
## Rain particles that follow the player. Emission scales with
## DayNight.rain_amount so showers fade in and out smoothly.

var _particles: GPUParticles3D


func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 700
	_particles.lifetime = 0.9
	_particles.visibility_aabb = AABB(Vector3(-30, -25, -30), Vector3(60, 45, 60))
	_particles.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(24, 1, 24)
	mat.direction = Vector3(0.15, -1, 0)
	mat.spread = 2.0
	mat.initial_velocity_min = 22.0
	mat.initial_velocity_max = 28.0
	mat.gravity = Vector3(0, -12, 0)
	_particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.55)
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.7, 0.78, 0.88, 0.35)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad.material = drop_mat
	_particles.draw_pass_1 = quad
	add_child(_particles)


func _process(_delta: float) -> void:
	var rain := DayNight.rain_amount
	if rain > 0.05:
		if not _particles.emitting:
			_particles.emitting = true
		_particles.amount_ratio = clampf(rain, 0.1, 1.0)
	elif _particles.emitting:
		_particles.emitting = false
	if is_instance_valid(Game.player):
		global_position = Game.player.global_position + Vector3(0, 14, 0)
