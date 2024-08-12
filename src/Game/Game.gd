extends Node
@export var instantiate: PackedScene
@export var calamity0: PackedScene
@export var calamity1: PackedScene

var money = 100

enum CalamityType {
	EARTHQUAKE, METEOR
}

enum GameState {
	P0,
	P1,
	BUSY,
}

var houses = [
	[null,null,null,null,null,null],
	[null,null,null,null,null,null],
	[null,null,null,null,null,null],
	[null,null,null,null,null,null],
	[null,null,null,null,null,null],
	[null,null,null,null,null,null]
]

var lives = 12

var cost_matrix = [
	[100, 125], # Same Color   # Build and convert to self
	[ 75, 100]  # Other Color  # convert to other
]

var turn_count = -1
var actions_per_turn = 3
var actions_available = 0

var current_game_state
var ui_game_status

var game_over = false

var selected_tile = null

var mutual_trust = 0.5 #GEMINI-AI INFLUENCES THIS

var P
func _ready():
	current_game_state = GameState.BUSY
	ui_game_status = $Cockpit/GameStatus
	#start with P0 turn
	P = [{
		money = 400 + randi() % 100,
		houses = 0,
		house_list = [],
		opp_houses = 0,
		tax_acc = 0,
		tax_share = 0.5,
		ui_money = $P0UI/Money,
		ui_tax_acc = $P0UI/TaxAcc,
		ui_ratio = $P0UI/Ratio,
		ui_ratio_value = $P0UI/Ratio/DisplayValue,
		ui_ratio_kept = $P0UI/RatioKept,
		ui_ratio_given = $P0UI/RatioGiven
	},{
		money = 400 + randi() % 100,
		houses = 0,
		house_list = [],
		opp_houses = 0,
		tax_acc = 0,
		tax_share = 0.5,
		ui_money = $P1UI/Money,
		ui_tax_acc = $P1UI/TaxAcc,
		ui_ratio = $P1UI/Ratio,
		ui_ratio_value = $P1UI/Ratio/DisplayValue,
		ui_ratio_kept = $P1UI/RatioKept,
		ui_ratio_given = $P1UI/RatioGiven
	}]
	update_ui()
	end_turn()

func set_game_state(state: GameState):
	current_game_state = state

func _on_area_3d_input_event(_camera, event, position, _normal, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if current_game_state == GameState.P0:
				select_tile(position)
				#await create_building(position, current_game_state)
				#end_turn()

func select_tile(position):
	var selector = $Floor/Selector
	var territory_hint = $Floor/TerritoryHint
	
	selector.visible = false
	territory_hint.visible = false
	selected_tile = null
	$Cockpit/Control/Action1.disabled = true
	$Cockpit/Control/Action2.disabled = true
	$Cockpit/Control/Action3.disabled = true
	$Cockpit/Control/Action1/Cost.text = ""
	$Cockpit/Control/Action2/Cost.text = ""
	$Cockpit/Control/Action3/Cost.text = ""
		
	if(position == null):
		return

	var x = int(clamp(position.x, 0, 5)+0.5)
	var z = int(clamp(position.z, 0, 5)+0.5)
	var other_territory = true if z > 2 else false

	selector.position = Vector3(x, 0.15, z)
	if(selected_tile and selected_tile == [x,z]):
		return
	selected_tile = [x, z]
	selector.visible = true
	
	if(houses[x][z] == null):
		territory_hint.visible = true
		var cost = cost_matrix[0][1 if other_territory else 0]
		$Cockpit/Control/Action1/Cost.text = str(cost) + " $"
		if(P[0].money >= cost and actions_available >= 1):
			$Cockpit/Control/Action1.disabled = false
	else:
		var cost = cost_matrix[0 - 1 if houses[x][z].owned_by == 1 else 0][1 if other_territory else 0]
		$Cockpit/Control/Action2/Cost.text = str(cost) + " $"
		if(P[0].money >= cost and actions_available >= 1):
			$Cockpit/Control/Action2.disabled = false
		if houses[x][z].health < 100:
			print("Repairable")
			var repair_cost = (100-houses[x][z].health) * 0.5
			$Cockpit/Control/Action3/Cost.text = ("%.1f" % repair_cost) + " $"
			if(P[0].money >= repair_cost and actions_available >= 0.5):
				$Cockpit/Control/Action3.disabled = false

func create_building(position: Vector3, player: GameState):
	$SelfTimer.one_shot = true
	$SelfTimer.wait_time = 1
	var x = int(clamp(position.x, 0, 5)+0.5)
	var z = int(clamp(position.z, 0, 5)+0.5)

	var build_in_P1: int = z > 2
	var cost = 100
	if build_in_P1 - player != 0:
		cost += 25

	if houses[x][z] == null and (P[player].houses < 8) and spend_money(player, cost):
		$SelfTimer.start()
		set_game_state(GameState.BUSY)
		var instance = instantiate.instantiate()
		instance.position = Vector3(x,0,z)
		add_child(instance)
		instance.game = self
		instance.set_owned_by(player)
		houses[x][z] = instance
		P[player].house_list.append(instance)
		houses[x][z].owned_by = player
		P[player].houses += 1
		await $SelfTimer.timeout
		set_game_state(player as GameState)
		actions_available -= 1
		calc_tax()
		return true
	return false

func convert_building(house, player):
	var other_territory = player - 1 if house.position.z > 2 else 0
	var cost = cost_matrix[player - house.owned_by][other_territory]
	if(P[player].houses < 8 and spend_money(player, cost) == true):
		P[house.owned_by].houses -= 1
		P[house.owned_by].house_list.erase(house)
		P[1 - house.owned_by].houses += 1
		P[1 - house.owned_by].house_list.append(house)
		house.set_owned_by(1 - house.owned_by)
		actions_available -= 1
		calc_tax()
		return true
	return false

func repair_building(house, player):
	var cost = (100-house.health) * 0.5
	if(spend_money(player, cost) == true):
		house.set_health(100)
		actions_available -= 0.5
		return true
	return false

func spend_money(player: GameState, amount: float):
	if(P[player].money > amount):
		P[player].money -= amount
		update_ui()
		return true
	return false

func update_ui():
	for i in range(0, 2):
		#print(i)
		P[i].ui_money.text = "%.2f" % P[i].money
		P[i].ui_tax_acc.text = "%.2f" % P[i].tax_acc
		P[i].ui_ratio_value.text = "%.0f" % (P[i].tax_share*100) + "%"
		P[i].ui_ratio_kept.text = "%.2f" % (P[i].tax_acc * (1-P[i].tax_share))
		P[i].ui_ratio_given.text = "%.2f" % (P[i].tax_acc * P[i].tax_share)
	$Cockpit/TurnIndication.text = str(turn_count)
	$Cockpit/Life.text = str(lives)
	if current_game_state == 0:
		$Cockpit/Control/Action0/Cost.text = str(actions_available)+"/"+str(actions_per_turn)
		ui_game_status.text = "TAKE ACTIONS OR END TURN" if actions_available > 0 else "OUT OF ACTIONS"
		if actions_available <= 0:
			end_turn()
	else:
		$Cockpit/Control/Action0/Cost.text = ""

func calc_tax():
	if houses != null:
		P[0].tax_acc = 0
		P[1].tax_acc = 0
		for i in range(0, 6):
			for j in range(0, 6):
				if houses[i][j] != null:
					var territory = 1 if j > 2 else 0
					var house_own = houses[i][j].owned_by
					# print(territory, house_own)
					P[territory].tax_acc += 20
					if house_own != territory:
						P[territory].tax_acc += 15
		update_ui()

func natural_disaster():
	var chance = max(turn_count, 8)*0.4 + randf() * 0.2
	var type
	if chance < 0.5:
		ui_game_status.text = "No Calamity encountered"
		return
	
	chance = randf()
	if chance < 0.4:
		type = CalamityType.EARTHQUAKE
	else:
		type = CalamityType.METEOR
		
	if type == CalamityType.EARTHQUAKE:
		add_child(calamity0.instantiate())
		var magnitude = randf() * 30 + turn_count * 1.2
		ui_game_status.text = "Earthquake"
		for i in range(6):
			for j in range(6):
				if houses[i][j] != null:
					houses[i][j].take_damage(randf() * magnitude)
	elif type == CalamityType.METEOR:
		var position = Vector3(randf() * 7 - 0.5, 0, randf() * 7 - 0.5)
		var instance = calamity1.instantiate()
		instance.position = position
		add_child(instance)
		var magnitude = 10 + randf() * 25 + turn_count * 1.2
		ui_game_status.text = "Meteor Struck"
		for i in range(6):
			for j in range(6):
				if houses[i][j] != null:
					var distance = position.distance_to(Vector3(i, 0, j))
					if distance < 3:
						houses[i][j].take_damage(magnitude * (1/(distance)))
	$SelfTimer.wait_time = 3
	$SelfTimer.start()
	await $SelfTimer.timeout

func end_turn():
	actions_available = actions_per_turn
	if current_game_state == GameState.P0:
		$P0UI/Ratio.editable = false
		$Cockpit/Control/Action0.disabled = true
		$Cockpit/Interact.disabled = true
		select_tile(null)
		ui_game_status.text = "NEIGHBOR IS PLAYING"
		current_game_state = GameState.P1
		await complete_remaining_actions()
	else:
		$P0UI/Ratio.editable = true
		$Cockpit/Control/Action0.disabled = false
		$Cockpit/Interact.disabled = false
		current_game_state = GameState.P0
		var p1_recipt = P[1].tax_acc * (1-P[1].tax_share) + P[0].tax_acc * P[0].tax_share
		var p0_recipt = P[0].tax_acc * (1-P[0].tax_share) + P[1].tax_acc * P[1].tax_share
		P[1].money += p1_recipt
		P[0].money += p0_recipt
		mutual_trust += (P[0].tax_share-0.5) * 0.2 + clamp((p1_recipt - p0_recipt)*(p1_recipt + p0_recipt) / (P[1].money + P[0].money), 0, 1) * 0.4
		mutual_trust = clamp(mutual_trust, 0, 1)
		print("Mutual Trust", mutual_trust)
		update_ui()
		turn_count += 1
		if(turn_count > 11):
			$Helper/Text.text = "Congratulations, you have successfully survived 12 rounds, rescue has arrived and you can flee the planet before the crash into the asteroid cloud.\n\nYou have won the game.\nYou can continue playing if you want."
			$Helper/HelperButton.text = "RESTART"
			$Helper/ContinueButton.visible = true
			$Helper.visible = true
			pass
			

func ai_player_action(): # returns 'true' if it wants to get executed again
	var helpful = true if randf() < mutual_trust else false
	print("Helpful: ", helpful)

	var chance = randf()
	print(chance)
	if chance < 0.5:
		#Repair Action
		for house in P[0].house_list+P[1].house_list:
			if house.health < (90 + randf() * 10):
				print("Repaired Building")
				return repair_building(house, current_game_state)
	elif chance < 0.7:
		#Build Action
		for i in range(6):
			if randf() < 0.20:
				continue
			for j in range(0 if helpful else 3, 3 if helpful else 6):
				if houses[i][j] == null:
					print("Created Building")
					return await create_building(Vector3(i, 0, j), current_game_state)
	elif chance < 0.95:
		#Convert Action
		for house in P[0].house_list+P[1].house_list:
			var conversion_coop = (true if house.owned_by else false) == (house.position.z > 2.5)
			if(helpful == conversion_coop):
				print("Converted Building")
				return convert_building(house, current_game_state)
		
	else:
		print("Did nothing")
		return false
	print("Reached End")
	return true

func complete_remaining_actions():
	# GEMINI AI INFLUENCE HERE
	# var limit = 15
	# while(await ai_player_action() == true and limit > 0):
	# 	print("AI Action")
	var limit = 15
	while(actions_available > 0 and P[1].money > 70 and limit > 0):
		print("Called")
		await ai_player_action()
		limit -= 1
	P[1].tax_share = mutual_trust * 0.75 + randf() * 0.20
	$P1UI/Ratio.value = P[1].tax_share
	update_ui()

	await natural_disaster()
	end_turn()

func house_delete_event(house):
	var x = int(house.position.x)
	var z = int(house.position.z)
	houses[x][z] = null
	P[house.owned_by].houses -= 1
	P[house.owned_by].house_list.erase(house)
	lives -= 1
	if(lives <= 0):
		$Helper/Text.text = "Game Over, you and your neighbor have lost 12 houses combined. Better luck next time."
		$Helper/HelperButton.text = "RESTART"
		$Helper.visible = true
		pass
		#TODO show UI
	calc_tax()
	update_ui()

#
#func _physics_process(delta):
	#if current_game_state == GameState.P1:
		#perform_AI_action()

func _on_p0_ratio_value_changed(value):
	P[0].tax_share = value
	update_ui()

func _on_p1_ratio_value_changed(value):
	P[1].tax_share = value
	update_ui()

func _on_action_0_pressed():
	end_turn()

func _on_action_1_pressed():
	
	var selected_position = Vector3(selected_tile[0], 0, selected_tile[1])
	select_tile(null)
	create_building(selected_position, current_game_state)
	calc_tax()

func _on_action_2_pressed():
	var target_house = houses[selected_tile[0]][selected_tile[1]]
	select_tile(null)
	convert_building(target_house, current_game_state)
	calc_tax()

func _on_action_3_pressed():
	var target_house = houses[selected_tile[0]][selected_tile[1]]
	select_tile(null)
	repair_building(target_house, current_game_state)

func _on_helper_button_pressed():
	if $Helper/HelperButton.text == "HIDE":
		$Helper.visible = false
	elif $Helper/HelperButton.text == "RESTART":
		get_tree().reload_current_scene()

func _on_continue_button_pressed():
	$Helper.visible = false
