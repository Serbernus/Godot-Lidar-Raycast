extends Node

@onready var main = $/root/main
@onready var multimesh_container = $/root/main/multimesh_container
var LineDrawer

var current_to_remove: MultiMeshInstance3D
var removed = false

var global_points_cap = 8192 * 32
var holder_points_cap = 2048
var points_total = 0

func _process(_delta):
	if points_total > global_points_cap:
		if current_to_remove == null:
			print("Preparing to Remove")
			current_to_remove = multimesh_container.get_child(0)
			current_to_remove.set_meta("processing", true)
		elif current_to_remove.get_meta("instance_count") == 0:
			points_total -= holder_points_cap
			current_to_remove.free()
			current_to_remove = null
			print("Removing")

func total_point_count(instance):
	points_total += instance.point_count
