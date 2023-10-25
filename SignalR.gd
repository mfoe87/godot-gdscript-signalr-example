extends Node
var socket = WebSocketPeer.new()
var handshake_made : bool = false
var disconnect_sent : bool = false
var invocation_id : int = 0
const END_MESSAGE_MARKER = 0x1E
var reconnect_attempts: int = 0

@export var connection_string = "https://localhost:5011/chatHub"
@export var validate_certificate = true
@export var print_debug_messages = false
@export var auto_reconnect = true

var http_request = null

signal connected()
signal disconnected(code:int, reason: String)
signal reconnecting(attempt: int)
signal message_received(message: Dictionary)

func _ready() -> void:
	set_process(false) # Don't process until we're connected.
	

func connect_to_signalr() -> void:

	if http_request == null:
		http_request = HTTPRequest.new()
		self.add_child(http_request)

	var negotiate_url = connection_string + "/negotiate"
	var headers = ["Content-Type: application/json"]
	var negotiate_dict = {
			"clientProtocol": "1.1",
			"transport": "WebSockets"
	}
	
	var negotiate_json = JSON.stringify(negotiate_dict)
	
	if not validate_certificate:
		http_request.set_tls_options(TLSOptions.client_unsafe())
	http_request.request_completed.connect(_on_negotiation_complete)
	http_request.request(negotiate_url,headers,HTTPClient.METHOD_POST,negotiate_json)

func _on_negotiation_complete(result, response_code, _headers, body) -> void:
	#Check if there's any timers from reconnection attempt
	var timers = get_children()
	for timer in timers:
		if timer is Timer:
			timer.queue_free()
	
	if response_code != 200 or result != OK:
		print("Error negotiating with SignalR Server: " + str(response_code))
		if auto_reconnect:
			if reconnect_attempts >= 9:
				print("Failed to reconnect after 10 attempts")
				return
			var timer = Timer.new()
			timer.connect("timeout",connect_to_signalr)
			timer.wait_time = float(1 + reconnect_attempts)
			timer.one_shot = true
			emit_signal("reconnecting",reconnect_attempts)
			reconnect_attempts += 1
			self.add_child(timer)
			timer.start()
		return
	#Get the connectionId from the response
	var json = JSON.parse_string(body.get_string_from_utf8())
	_connecto_to_ws(json["connectionId"])

func disconnect_from_signalr() -> void:
	disconnect_sent = true
	socket.close()
	handshake_made = false

#Generic method to send a message to the server
func send_message(target: String, arguments: Array) -> void:
	var payload = {
		"arguments": arguments,
		"invocation_id": str(invocation_id),
		"steamIds":[],
		"target": target,
		"type": 1
	}
	var msg_payload = _convert_to_signalr_message(payload)
	invocation_id += 1
	socket.send(msg_payload,WebSocketPeer.WRITE_MODE_TEXT)
		
func _convert_to_signalr_message(payload: Dictionary) -> PackedByteArray:
	var json = JSON.stringify(payload)
	var payloadPacked = json.to_utf8_buffer()
	payloadPacked.append(END_MESSAGE_MARKER)
	return payloadPacked

	
func _process(_delta) -> void:
	
	socket.poll()
	var state = socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count():
			var packet = socket.get_packet().get_string_from_utf8()
			_process_message(packet)
			if print_debug_messages:
				print("Packet: ", packet)
		if not handshake_made:
			_handshake()
			handshake_made = true
	elif state == WebSocketPeer.STATE_CLOSING:
		# Keep polling to achieve proper close.
		if print_debug_messages:
			print("Closing socket")
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		var code = socket.get_close_code()
		var reason = socket.get_close_reason()
		if print_debug_messages:
			print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
		#Stop polling for more messages
		emit_signal("disconnected",code,reason)
		handshake_made = false
		if auto_reconnect and not disconnect_sent:
			connect_to_signalr()
		disconnect_sent = false
		set_process(false)

#Once the socket is open, send the handshake message
func _handshake() -> void:
	var jsonSend = {"protocol":"json","version":1}
	var json = JSON.stringify(jsonSend).to_utf8_buffer()
	json.append(END_MESSAGE_MARKER)
	var res = socket.send(json,WebSocketPeer.WRITE_MODE_TEXT)
	if res != OK:
		print("Error during handshake: " + str(res))
		return
	#hello_send = true

#Process a message received from the server
func _process_message(payload: String) -> void:
	payload = payload.substr(0,payload.length() - 1) #remove END_MESSAGE_MARKER
	if payload == "{}":
		#Handshake complete
		handshake_made = true
		emit_signal("connected")
		reconnect_attempts = 0
		return
	var parsed_payload = JSON.parse_string(payload)
	if "type" in parsed_payload.keys():
		if parsed_payload["type"] == 6:
			if print_debug_messages:
				print("Received ping")
			return #Keep alive message
	print("Received message: " + payload)
	emit_signal("message_received",parsed_payload)

func _connecto_to_ws(connectionId) -> void:
	if print_debug_messages:
		print("Connecting to WebSocket")
	socket.handshake_headers = PackedStringArray([
		"Content-Type: application/json"
	])
	
	var cert_validation = TLSOptions.client()
	if not validate_certificate:
		cert_validation = TLSOptions.client_unsafe()

	var res = socket.connect_to_url(_convert_url_to_ws(connection_string) + "?id=" + connectionId, cert_validation)	
	if res == OK:
		set_process(true)
	else:
		print("Error connecting to ws. Error code: " + res)
		set_process(false)


func _convert_url_to_ws(url) -> String:
	var ws_url = url.replace("http","ws")
	return ws_url
