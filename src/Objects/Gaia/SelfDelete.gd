extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready():
	$CPUParticles3D.emitting = true
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_cpu_particles_3d_finished():
	get_tree().queue_delete(self)
	print("DONE")
