extends Button

@export var game: Node
@export var prompt_box: TextEdit
var http_request

var api_key
var settings_path = "res://config.json"
var saved_api_key = false

enum State {
	READY,
	API_ASK,
	BUSY,
	CODE_LEASE,
}
var state: State

#see https://ai.google.dev/tutorials/rest_quickstart

# var api_key = ""
func _ready():
	state = State.BUSY
	http_request = $HTTPRequest
	print("Check API")
	var save_file = FileAccess.get_file_as_string(settings_path)
	if(save_file != ""):
		var settings = JSON.parse_string(save_file)
		state = State.READY
		if settings != null:
			self.disabled = false
			api_key = settings.api_key
			saved_api_key = true
		else:
			lease_code()

func lease_code():
	print("TRY")
	if(state != State.READY):
		return false
	print("TRY")
	state = State.CODE_LEASE
	var url = "https://ragav.pages.dev/temp"
	saved_api_key = false
	var error = http_request.request(url, ["Content-Type: application/text"], HTTPClient.METHOD_GET)
	
	if error != OK:
		push_error("Not connected to network %s"%error)
		state = State.READY

func _on_pressed():
	if(state == State.API_ASK):
		save_key(prompt_box.text)
		state = State.READY
		prompt_box.placeholder_text = "Communicate with neighbor"
		self.text = "Send"
	if(state == State.READY):
		state = State.BUSY
		var gamestate = "Current Trust level is " + "%.0f" % (game.mutual_trust*100) + "%"
		gamestate += "\nYour Finances: " + str(game.P[1].money+game.P[1].tax_acc)
		gamestate += "\nTheir Finances: " + str(game.P[0].money+game.P[0].tax_acc)
		
		var prompt = prompt_box.text
		prompt = """ Imagine yourself being the supervisor of your clan, in a fantasy.
		As the supervisor, you can't negotiate the details as much, as you have limited scope,
		your response can only be cooperate or not cooperate with few reasons.
		Your neighbor and you need to help each other out as much as possible.
		Being stranded in a planet, you also need to make you are not taken advantage of,
		You can only build houses, convert to and from the neighbor and repair from natural destruction.
		""" + gamestate + """
		This is the message you've received from your neighbour, read it carefully,
		take a step back, and decided how you want to proceed. Write a short response
		explaining your situation and tell whether you will cooperate or not cooperate.
		If you decided to not cooperate, make sure to include "NOT COOPERATE" in the response.
		Keep the response short, in less than three sentances and one paragraph
		
		--MESSAGE FROM NEIGHBOR--
		""" + prompt
		
		_request_text(prompt)
		

func save_key(code):
	var json_text = JSON.stringify({"api_key": code.strip_escapes()})
	var file = FileAccess.open(settings_path,FileAccess.WRITE)
	file.store_string(json_text)
	file.close()

func _on_http_request_request_completed(result, response_code, headers, body):
	if(state == State.CODE_LEASE):
		state = State.READY
		if(response_code == 200):
			print(response_code)
			var code: String = body.get_string_from_utf8()
			api_key = code.strip_escapes()
		else:
			prompt_box.placeholder_text = "Enter your own API key to negotiate with Neighbor"
			self.text = "Set"
			self.disabled = false
			state = State.API_ASK
	elif(state == State.BUSY):
		print("HMM")
		#self.disabled = false
		var json = JSON.new()
		json.parse(body.get_string_from_utf8())
		var response = json.get_data()
		print("response")
		prompt_box.text = ""
		var response_text = response.candidates[0].content.parts[0].text
		prompt_box.placeholder_text = response_text
		if response_text.find("NOT COOPERATE"):
			game.mutual_trust -= 0.1
			game.mutual_trust = clamp(game.mutual_trust, 0, 1)
		else:
			game.mutual_trust += 0.1
			game.mutual_trust = clamp(game.mutual_trust, 0, 1)
		state = State.READY
		
		if response == null:
			prompt_box.placeholder_text = "//The response from the Neighbor was lost."
			return
		#
		if response.has("error"):
			prompt_box.placeholder_text = "//Neighbor got sick, we will continue our plan."
			#maybe blocked
			return
		#
		#No Answer
		if !response.has("candidates"):
			prompt_box.placeholder_text = "//Neighbour sent an empty letter back, was is washed out?, did the ink dissolve?"
			#maybe blocked
			return
			#
		##I can not talk about
		if response.candidates[0].finishReason != "STOP" and response.candidates[0].finishReason !="MAX_TOKENS":
			prompt_box.placeholder_text = "//Neighbour is annoyed by you."

func _request_text(prompt):
	# var url = "https://generativelanguage.googleapis.com/v1/models/gemini-pro:generateContent?key=%s"%api_key
	var url = "https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=%s"%api_key
	
	var stop_sequence = ""
	var tempature = randf()*0.4+0.6
	var output_length = 360
	var top_k=randi()%2+3
	var top_p=randf()*0.2+0.8
	var body = JSON.new().stringify({
		"contents":[
			{ "parts":[{
				"text": prompt
			}]
			}
			
		],"safety_settings":[
			{
			"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
			"threshold": "BLOCK_LOW_AND_ABOVE",
			},
			{
			"category": "HARM_CATEGORY_HATE_SPEECH",
			"threshold": "BLOCK_LOW_AND_ABOVE",
			},
			{
			"category": "HARM_CATEGORY_HARASSMENT",
			"threshold": "BLOCK_LOW_AND_ABOVE",
			},
			{
			"category": "HARM_CATEGORY_DANGEROUS_CONTENT",
			"threshold": "BLOCK_LOW_AND_ABOVE",
			},
			],
			"generationConfig": {
			"stopSequences": [
				stop_sequence
			],
			"temperature": tempature,
			"maxOutputTokens": output_length,
			"topP": top_p,
			"topK": top_k
		}
	})
	
	print("send-content"+str(body))
	self.disabled = true
	var error = http_request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("requested but error happen code = %s"%error)
