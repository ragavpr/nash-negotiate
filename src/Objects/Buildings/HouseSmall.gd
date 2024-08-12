extends Node3D

var game
var owned_by
var health = 100

var health_bar
var health_bar_material
static var health_gradient: Gradient

func _ready():
	$AnimationPlayer.current_animation = 'anim_trans_in'
	$house_small.quaternion = Quaternion.from_euler(Vector3(0, randf() * PI, 0))
	
	health_bar = $Health
	# health_bar_material = $Health.get_surface_override_material(0) # Material is shared
	health_bar_material = StandardMaterial3D.new()
	health_bar_material.emission_enabled = true
	health_bar_material.albedo_color = Color(0, 0, 0, 1)
	$Health.set_surface_override_material(0, health_bar_material)
	
	#Static initialization
	if health_gradient == null:
		print("Gradient Created")
		health_gradient = Gradient.new()
		health_gradient.set_color(0, Color.RED)
		health_gradient.set_color(1, Color.GREEN)
		health_gradient.add_point(0.5, Color.YELLOW)
	
	set_health(100)

func set_health(new_health):
	health = new_health
	health_bar.scale.z = max(0.004 * health, 0)
	health_bar_material.emission = health_gradient.sample(0.01*health)

func take_damage(amount):
	set_health(health - amount)
	if(health <= 0):
		game.house_delete_event(self)
		$AnimationPlayer.play_backwards('anim_trans_in')
		await $AnimationPlayer.animation_finished
		get_tree().queue_delete(self)

func set_owned_by(player):
	owned_by = player
	if player == 1:
		$house_small/Plane.set_surface_override_material(1, load("res://src/Materials/HouseRoofR.tres"))
	else:
		$house_small/Plane.set_surface_override_material(1, load("res://src/Materials/HouseRoofB.tres"))

func _physics_process(delta):
	#take_damage(0.5)
	pass
