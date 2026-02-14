extends Control

@onready var name_input: LineEdit = $VBox/NameInput
@onready var ip_input: LineEdit = $VBox/IPInput
@onready var join_button: Button = $VBox/JoinButton
@onready var status_label: Label = $VBox/StatusLabel

const PREFS_PATH = "user://connect_prefs.cfg"
const PUBLIC_SERVER_IP = "207.32.216.76"
var DEFAULT_IP: String = "127.0.0.1" if OS.has_feature("editor") else PUBLIC_SERVER_IP

func _ready() -> void:
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	# Load saved preferences
	_load_prefs()

func _on_join_pressed() -> void:
	var player_name = name_input.text.strip_edges()
	if player_name == "":
		player_name = "Player"
	var address = ip_input.text.strip_edges()
	if address == "":
		address = DEFAULT_IP
	# Save preferences
	_save_prefs(player_name, address)
	var error = NetworkManager.join_game(address, player_name)
	if error == OK:
		status_label.text = "Connecting to %s..." % address
		join_button.disabled = true
	else:
		status_label.text = "Failed to connect: %s" % str(error)

func _on_connection_succeeded() -> void:
	status_label.text = "Connected! Loading world..."

func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"
	join_button.disabled = false

func _save_prefs(player_name: String, address: String) -> void:
	var config = ConfigFile.new()
	config.set_value("connect", "name", player_name)
	config.set_value("connect", "address", address)
	config.save(PREFS_PATH)

func _load_prefs() -> void:
	var config = ConfigFile.new()
	if config.load(PREFS_PATH) == OK:
		name_input.text = config.get_value("connect", "name", "Player")
		# In editor, always default to localhost; in export, use saved or public IP
		if OS.has_feature("editor"):
			ip_input.text = DEFAULT_IP
		else:
			var saved_ip: String = config.get_value("connect", "address", DEFAULT_IP)
			# Don't use saved localhost in exported builds — it's a dev artifact
			if saved_ip == "127.0.0.1" or saved_ip == "localhost":
				ip_input.text = DEFAULT_IP
			else:
				ip_input.text = saved_ip
	else:
		ip_input.text = DEFAULT_IP
