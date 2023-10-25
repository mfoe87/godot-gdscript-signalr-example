extends Control

@onready var signalr_client = $SignalRClient
@onready var connect_button = $VBoxContainer/HBoxContainer/ConnectButton
@onready var connection_string_textedit = $VBoxContainer/HBoxContainer/ConnectionStringTextEdit
@onready var validate_cert_checkbox = $VBoxContainer/HBoxContainer/ValidateCertCheckbox
@onready var username_textedit = $VBoxContainer/HBoxContainer/UsernameTextEdit
@onready var chat_message_textedit = $VBoxContainer/HBoxContainer2/ChatMessageTextEdit
@onready var send_chat_button = $VBoxContainer/HBoxContainer2/SendChatButton
@onready var chat_messages = $VBoxContainer/ChatMessages

func _ready():

	signalr_client.connect("connected", _signalr_connected)
	signalr_client.connect("disconnected", _signalr_disconnected)
	signalr_client.connect("reconnecting", _signalr_reconnecting)
	signalr_client.connect("message_received", _message_received)

	connect_button.connect("pressed", _connect_to_signalr)
	connection_string_textedit.text = signalr_client.connection_string
	validate_cert_checkbox.set_pressed_no_signal(signalr_client.validate_certificate)
	
	chat_message_textedit.connect("gui_input", _on_chattextedit_input)
	send_chat_button.connect("pressed", _send_chat_message)

func _connect_to_signalr():
	if connect_button.text == "Disconnect":
		print("Disconnecting from SignalR")
		signalr_client.disconnect_from_signalr()
		connect_button.text = "Connect"
		return

	print("Connecting to SignalR")
	signalr_client.connection_string = connection_string_textedit.text
	#Check if Certificate should be validated
	if validate_cert_checkbox.is_pressed():
		signalr_client.validate_certificate = true
	else:
		signalr_client.validate_certificate = false
	signalr_client.connect_to_signalr()

func _signalr_connected():
	print("Connected to SignalR")
	chat_messages.text += "** Connected to SignalR **\n"
	#enable chat textedit and button
	send_chat_button.disabled = false
	chat_message_textedit.editable = true
	connect_button.text = "Disconnect"

func _signalr_disconnected(code: int, reason: String):
	chat_messages.text += "** Disconnected from SignalR **\n"
	print("Disconnected from SignalR. code:%d, reason: %s" % [code, reason])
	#disable chat textedit and button
	send_chat_button.disabled = true
	chat_message_textedit.editable = false

func _signalr_reconnecting(attempt: int):
	print("Reconnecting to SignalR. Attempt %d" % [attempt])
	chat_messages.text += "** Reconnecting to SignalR, attempt: %d **\n" % [attempt]

func _message_received(message: Dictionary):
	print("Message received: %s" % [message])
	
	#Example using SignalR example ReceiveMessage that is sent from server upon receiving SendMessage
	if message.has("target"):
		if message["target"] == "ReceiveMessage":
			var chatMessage = "%s: %s" % [message["arguments"][0], message["arguments"][1]]
			chat_messages.text += chatMessage + "\n"

func _send_chat_message():
	var chatMessage = chat_message_textedit.text
	var user = username_textedit.text
	
	var arguments = [user, chatMessage]
	signalr_client.send_message("SendMessage", arguments)

	chat_message_textedit.text = ""

func _on_chattextedit_input(event):
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ENTER:
			_send_chat_message()
