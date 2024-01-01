extends MultiMeshInstance3D

var instances_to_remove = 16

func _process(_delta):
	if get_meta("processing"):
		if not get_meta("instance_count") == 0:
			set_meta("instance_count", get_meta("instance_count") - instances_to_remove)
			var tmp_buffer = multimesh.buffer
			if tmp_buffer.size() / 16 >= instances_to_remove:
				for i in 16 * instances_to_remove:
					tmp_buffer.remove_at(0)
				multimesh.instance_count = get_meta("instance_count")
				if not get_meta("instance_count") <= 0:
					multimesh.buffer = tmp_buffer
			else:
				instances_to_remove = round(tmp_buffer.size() / 16)
