extends CharacterBody3D

signal point_count_signal

@onready var debug = $/root/main/debug

@onready var multimesh_container = $/root/main/multimesh_container
var line_prefab: PackedScene
var holder_prefab: PackedScene
var point_holder: MultiMeshInstance3D
var point_count = 0

@onready var raycaster = $head/hand/mesh/raycaster
@onready var ray_lines = raycaster.get_node("lines")
var ray_distance = 24.0
var ray_max_count = 128
var ray_max_bounces = 3
var ray_spread_factor = 8.0
var ray_spread = 1.0

@onready var head = $head
@onready var hand = $head/hand

var mouse_position: Vector2i
var mouse_motion: Vector2i
var mouse_lock = false

var direction_input: Vector2
var char_rotation: Vector3
var char_motion: Vector3

const char_speed = 10.0
const char_jump = 5.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_lock = true
	connect("point_count_signal", Global.total_point_count.bind(self))
	line_prefab = load("res://resources/prefabs/raycast_line.tscn")
	holder_prefab = load("res://resources/prefabs/point_holder.tscn")
	
	for line in ray_max_bounces:
		var instance = line_prefab.instantiate()
		ray_lines.add_child(instance)
		set_line_cast(instance, Vector3.ZERO, Vector3.FORWARD, 0, Color.WHITE)

func _process(delta):
	if mouse_lock:
		if Input.is_action_just_released("mouse_s_u"):
			ray_spread_factor = lerp(ray_spread_factor, 12.0, delta * 32)
		elif Input.is_action_just_released("mouse_s_d"):
			ray_spread_factor = lerp(ray_spread_factor, 4.0, delta * 32)
		
		char_rotation = lerp(char_rotation, char_rotation - Vector3(mouse_motion.y, mouse_motion.x, 0) / 2, delta)
		char_rotation.x = clamp(char_rotation.x, deg_to_rad(-80), deg_to_rad(90))
		head.rotation.x = char_rotation.x
		rotation.y = char_rotation.y
		
	mouse_motion = Vector2i(0, 0)

func _physics_process(delta):
	for line in ray_lines.get_child_count():
		set_line_cast(ray_lines.get_child(line), raycaster.global_position, raycaster.global_basis.z, 0.01, Color.BLACK)
	
	if mouse_lock:
		direction_input = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var direction = Vector3(direction_input.x, 0, direction_input.y).normalized().rotated(Vector3.UP, rotation.y)
		if not is_on_floor():
			char_motion.y -= gravity * delta
		elif is_on_floor():
			if Input.is_action_just_pressed("move_jump"):
				char_motion.y = char_jump
			else:
				char_motion.x = direction.x * char_speed
				char_motion.z = direction.z * char_speed
		velocity = lerp(velocity, char_motion, delta * 8)
		move_and_slide()
		
		if Input.is_action_pressed("mouse_left"):
			point_raycast_instancer(ray_max_count, ray_spread * ray_spread_factor)

func _input(event):
	if event is InputEventMouseMotion:
		mouse_position = event.position
		mouse_motion = event.relative
	if Input.is_action_just_pressed("escape"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		mouse_lock = false
	elif Input.is_action_just_pressed("mouse_left") or Input.is_action_just_pressed("mouse_right"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_lock = true
	if mouse_lock:
		if Input.is_action_just_pressed("f_screen_toggle"):
			if DisplayServer.window_get_mode(0) == 0:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func point_raycast_instancer(ray_count:int, spread:float):
	var space_state = get_world_3d().direct_space_state
	if not point_holder:
		point_holder = instantiate_holder()
	var current_point_count = 0
	var current_loop_buffer:PackedFloat32Array = []
	var prev_loop_buffer = point_holder.multimesh.buffer
	for r in ray_count:
		var origin = raycaster.global_position
		var randomness = get_random_pos_in_sphere(spread)
		var end = head.global_position - head.basis.z.rotated(Vector3.UP, rotation.y) * ray_distance + randomness
		var query = PhysicsRayQueryParameters3D.create(origin, end)
		query.exclude = [self]
		var final_result = space_state.intersect_ray(query)
		if final_result:
			var norm = final_result.normal
			var pos = final_result.position + norm * 0.01
			var distance = raycaster.global_position.distance_to(pos)
			if not distance > ray_distance - randf_range(0.0, ray_distance / 2.0):
				var rot = Vector3(atan2(1 - norm.y, norm.y), atan2(norm.x, norm.z), 0)
				var i_transform = Transform3D(Basis.from_euler(rot), pos)
				if not point_count >= Global.holder_points_cap:
					var color = final_result.collider.get_parent().material_override.albedo_color
					var color_rand = Color(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0)
					color += color_rand
					point_count += 1
					current_point_count += 1
					point_holder.multimesh.instance_count = 1
					point_holder.multimesh.set_instance_transform(0, i_transform)
					point_holder.multimesh.set_instance_color(0, color)
					current_loop_buffer += point_holder.multimesh.buffer
					point_holder.multimesh.instance_count = current_point_count
					point_holder.multimesh.buffer = current_loop_buffer
					
					set_line_cast(ray_lines.get_child(0), origin, end, distance, color)
					
					var b_roughness = 1 - final_result.collider.get_parent().material_override.roughness
					var b_color = color
					var b_norm = norm
					var b_origin = pos
					var b_ray_distance = ray_distance * b_roughness
					for r_b in ray_max_bounces:
						if b_roughness <= 0.25:
							break
						var b_randomness = get_random_pos_in_sphere(12)
						var b_end = b_origin + b_origin.direction_to(raycaster.global_position).reflect(b_norm) * b_ray_distance + b_randomness
						var b_query = PhysicsRayQueryParameters3D.create(b_origin, b_end)
						b_query.exclude = [self]
						var bounce_result = space_state.intersect_ray(b_query)
						if bounce_result:
							b_norm = bounce_result.normal
							var b_pos = bounce_result.position + b_norm * 0.01
							var b_distance = b_origin.distance_to(bounce_result.position)
							var b_distance_factor = b_distance / (b_ray_distance / 4)
							if not b_distance > b_ray_distance - randf_range(0.0, b_ray_distance / 2.0):
								var b_rot = Vector3(atan2(1 - b_norm.y, b_norm.y), atan2(b_norm.x, b_norm.z), 0)
								var b_i_transform = Transform3D(Basis.from_euler(b_rot), b_pos)
								if not point_count >= Global.holder_points_cap:
									b_color = lerp(b_color, bounce_result.collider.get_parent().material_override.albedo_color, b_distance_factor)
									var b_color_rand = Color(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0)
									b_color += b_color_rand
									point_count += 1
									current_point_count += 1
									point_holder.multimesh.instance_count = 1
									point_holder.multimesh.set_instance_transform(0, b_i_transform)
									point_holder.multimesh.set_instance_color(0, b_color * b_roughness)
									current_loop_buffer += point_holder.multimesh.buffer
									point_holder.multimesh.instance_count = current_point_count
									point_holder.multimesh.buffer = current_loop_buffer
									
									set_line_cast(ray_lines.get_child(r_b + 1), b_origin, b_pos, b_distance, b_color)
									
									b_ray_distance = ray_distance - ray_distance * b_roughness
									b_origin = b_pos
									b_roughness = 1 - bounce_result.collider.get_parent().material_override.roughness
								else:
									break
							else:
								break
				else:
					break
	point_holder.multimesh.instance_count = point_count
	point_holder.multimesh.buffer = prev_loop_buffer + current_loop_buffer
	point_holder.set_meta("instance_count", point_count)
	if point_count >= Global.holder_points_cap:
		emit_signal("point_count_signal")
		point_holder = instantiate_holder()

func set_line_cast(line:Node3D, line_o:Vector3, line_e:Vector3, distance:float, l_color:Color):
	line.global_position = line_o
	line.look_at(line_e, Vector3.UP)
	line.scale.z = distance
	var material:ShaderMaterial = line.get_node("shape").material_override
	material.set_shader_parameter("color", l_color)

func instantiate_holder():
	point_count = 0
	var instance = holder_prefab.instantiate()
	var point_mesh = load("res://resources/prefabs/point_mesh.obj")
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = point_mesh
	instance.multimesh = multimesh
	multimesh_container.add_child(instance)
	return instance

func get_random_pos_in_sphere (radius : float) -> Vector3:
	var x1 = randf_range(-1, 1)
	var x2 = randf_range(-1, 1)
	
	while x1*x1 + x2*x2 >= 1:
		x1 = randf_range(-1, 1)
		x2 = randf_range(-1, 1)
	
	var random_pos_on_unit_sphere = Vector3 (
		2 * x1 * sqrt (1 - x1*x1 - x2*x2),
		2 * x2 * sqrt (1 - x1*x1 - x2*x2),
		1 - 2 * (x1*x1 + x2*x2)
		)
	
	return random_pos_on_unit_sphere * randf_range(0, radius)
