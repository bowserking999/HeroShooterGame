extends Node

## Map-center objective; rim VFX is the child RimAreaVFX_02 (capture logic TBD).
@onready var capture_point: Node3D = $CapturePoint

@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry
@onready var team_option = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/TeamOption
@onready var hero_option = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/HeroOption
@onready var hud = $CanvasLayer/HUD
@onready var health_bar = $CanvasLayer/HUD/HealthBar
@onready var death_overlay = $CanvasLayer/DeathOverlay
@onready var respawn_countdown = $CanvasLayer/DeathOverlay/CenterContainer/VBoxContainer/RespawnCountdown
@onready var character_select: Control = $CanvasLayer/CharacterSelectMenu
@onready var debug_readout: Label = $CanvasLayer/DebugReadout

const Player = preload("res://player.tscn")
const TankExplosionVfxScene = preload("res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_06.tscn")
const TANK_EXPLOSION_VFX_CLEANUP_SEC := 3.5
const PORT = 9999
const TEAM_A_SPAWN_POS := Vector3(40, 3, 0)
const TEAM_B_SPAWN_POS := Vector3(-40, 3, 0)
const TEAM_A_YAW := PI / 2.0
const TEAM_B_YAW := -PI / 2.0
var enet_peer = ENetMultiplayerPeer.new()
var local_team_id := 0 # 0 = Team A, 1 = Team B
var local_hero_id := "dps_missile"
var peer_teams := {} # peer_id -> team_id
var peer_heroes := {} # peer_id -> hero_id
var recently_damaged_by_me := {} # peer_id -> timestamp (for enemy health bar visibility)
const DAMAGED_VISIBLE_MS := 5000
var respawn_end_ms: int = 0

func _ready() -> void:
	if team_option:
		team_option.clear()
		team_option.add_item("Team A", 0)
		team_option.add_item("Team B", 1)
		team_option.selected = 0
		local_team_id = team_option.selected
		team_option.item_selected.connect(_on_team_option_item_selected)
	if hero_option:
		hero_option.clear()
		for hid in HeroesRegistry.get_all_hero_ids():
			var hero: HeroResource = HeroesRegistry.get_hero(hid)
			hero_option.add_item(hero.display_name if hero else hid, hero_option.item_count)
			hero_option.set_item_metadata(hero_option.item_count - 1, hid)
		hero_option.item_selected.connect(_on_hero_option_item_selected)
		_sync_hero_option_to_id("dps_missile")
	if character_select:
		character_select.hide()
		character_select.hero_selected.connect(_on_character_select_hero_chosen)
	HeroEffectsPreload.warm(local_hero_id, self)

func _on_hero_option_item_selected(index: int) -> void:
	var meta = hero_option.get_item_metadata(index)
	if meta != null:
		local_hero_id = str(meta)
		HeroEffectsPreload.warm(local_hero_id, self)

func _sync_hero_option_to_id(hero_id: String) -> void:
	if hero_option == null:
		return
	for i in hero_option.item_count:
		if str(hero_option.get_item_metadata(i)) == hero_id:
			hero_option.select(i)
			local_hero_id = hero_id
			return
	if hero_option.item_count > 0:
		hero_option.select(0)
		local_hero_id = str(hero_option.get_item_metadata(0))

func set_local_player_hero(hero_id: String) -> void:
	if HeroesRegistry.get_hero(hero_id) == null:
		return
	HeroEffectsPreload.warm(hero_id, self)
	local_hero_id = hero_id
	_sync_hero_option_to_id(hero_id)
	var p := get_node_or_null(str(multiplayer.get_unique_id()))
	if p != null and p.is_multiplayer_authority():
		p.hero_id = hero_id
		p._apply_hero_stats()
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		peer_heroes[multiplayer.get_unique_id()] = hero_id
	else:
		request_hero.rpc_id(1, hero_id)

func _local_player_is_dead() -> bool:
	var p := get_node_or_null(str(multiplayer.get_unique_id()))
	return p != null and p.get("is_dead") == true

func is_character_select_open() -> bool:
	return character_select != null and character_select.visible

func _open_character_select() -> void:
	if character_select == null or main_menu.visible or _local_player_is_dead():
		return
	character_select.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_character_select() -> void:
	if character_select == null:
		return
	character_select.hide()
	var p := get_node_or_null(str(multiplayer.get_unique_id()))
	if p != null and p.is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_character_select_hero_chosen(hero_id: String) -> void:
	set_local_player_hero(hero_id)
	_close_character_select()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_tree().quit()
		get_viewport().set_input_as_handled()
		return
	if character_select and character_select.visible and event.is_action_pressed("ui_cancel"):
		_close_character_select()
		get_viewport().set_input_as_handled()
		return
	if character_select and event.is_action_pressed("toggle_hero_select") and not main_menu.visible:
		if character_select.visible:
			_close_character_select()
		else:
			_open_character_select()
		get_viewport().set_input_as_handled()

func _on_team_option_item_selected(index: int) -> void:
	local_team_id = clampi(index, 0, 1)


func _on_host_button_pressed() -> void:
	main_menu.hide()
	hud.show()
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	
	peer_teams[multiplayer.get_unique_id()] = local_team_id
	peer_heroes[multiplayer.get_unique_id()] = local_hero_id
	add_player(multiplayer.get_unique_id())
	
	#upnp_setup()



func _on_join_button_pressed() -> void:
	_join_to_address(address_entry.text)

func _on_join_local_button_pressed() -> void:
	# Localhost join for another instance on the same machine.
	_join_to_address("127.0.0.1")

func _join_to_address(ip: String) -> void:
	main_menu.hide()
	hud.show()
	enet_peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)

func _on_connected_to_server() -> void:
	# ENet: server is peer_id 1
	request_team.rpc_id(1, local_team_id)
	request_hero.rpc_id(1, local_hero_id)
	
	

func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	if peer_teams.has(peer_id):
		player.team_id = int(peer_teams[peer_id])
	if peer_heroes.has(peer_id):
		player.hero_id = str(peer_heroes[peer_id])
	add_child(player)
	respawn_player(player)
	if player.is_multiplayer_authority():
		player.health_changed.connect(update_health_bar)
		_connect_local_death_signals(player)

func remove_player(peer_id):
	peer_teams.erase(peer_id)
	peer_heroes.erase(peer_id)
	var player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()

func update_health_bar(health_value) -> void:
	var p := get_node_or_null(str(multiplayer.get_unique_id()))
	if p != null and p.get("max_health") != null:
		health_bar.max_value = float(p.max_health)
	health_bar.value = float(health_value)

func record_damaged_by_me(peer_id: int) -> void:
	recently_damaged_by_me[peer_id] = Time.get_ticks_msec()

func was_damaged_by_me_recently(peer_id: int) -> bool:
	if not recently_damaged_by_me.has(peer_id):
		return false
	var t: int = recently_damaged_by_me[peer_id]
	if Time.get_ticks_msec() - t > DAMAGED_VISIBLE_MS:
		recently_damaged_by_me.erase(peer_id)
		return false
	return true

func _process(_delta: float) -> void:
	# Prune old entries
	var now: int = Time.get_ticks_msec()
	for pid in recently_damaged_by_me.keys():
		if now - recently_damaged_by_me[pid] > DAMAGED_VISIBLE_MS:
			recently_damaged_by_me.erase(pid)

	# Update death countdown
	if death_overlay and death_overlay.visible:
		var ms_left: int = maxi(respawn_end_ms - Time.get_ticks_msec(), 0)
		var secs_left: int = int(ceil(float(ms_left) / 1000.0))
		if respawn_countdown:
			respawn_countdown.text = "Respawning in %d..." % secs_left

	_update_debug_readout()

func _update_debug_readout() -> void:
	if debug_readout == null:
		return
	if main_menu.visible:
		debug_readout.visible = false
		return
	debug_readout.visible = true
	var pos := Vector3.ZERO
	var p := get_node_or_null(str(multiplayer.get_unique_id()))
	if p != null:
		pos = p.global_position
	var hero: HeroResource = HeroesRegistry.get_hero(local_hero_id)
	var label := hero.display_name if hero else local_hero_id
	debug_readout.text = "X:%.1f Y:%.1f Z:%.1f  |  %s (%s)" % [pos.x, pos.y, pos.z, label, local_hero_id]

func _on_multiplayer_spawner_spawned(node):
	if node.is_multiplayer_authority():
		node.health_changed.connect(update_health_bar)
		node.team_id = local_team_id
		HeroEffectsPreload.warm(local_hero_id, self)
		node.hero_id = local_hero_id
		node._apply_hero_stats()
		_connect_local_death_signals(node)
		# Position/rotation are owned by this peer's authority — must apply here.
		respawn_player(node)

@rpc("any_peer", "reliable")
func request_team(team_id: int) -> void:
	# Client tells server which team they picked.
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var requested := clampi(team_id, 0, 1)
	peer_teams[sender] = requested
	var player := get_node_or_null(str(sender))
	if player:
		player.team_id = requested
		respawn_player(player)
	# Tell that client to apply spawn on their authoritative copy.
	client_respawn_at_team_spawn.rpc_id(sender)

@rpc("any_peer", "reliable")
func client_respawn_at_team_spawn() -> void:
	var me := multiplayer.get_unique_id()
	var p := get_node_or_null(str(me))
	if p != null and p.is_multiplayer_authority():
		respawn_player(p)

@rpc("any_peer", "reliable")
func request_hero(hero_id: String) -> void:
	if not multiplayer.is_server():
		return
	if HeroesRegistry.get_hero(hero_id) == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	# Owning client applies hero_id locally; server only tracks choice.
	peer_heroes[sender] = hero_id

func _connect_local_death_signals(player: Node) -> void:
	if not player:
		return
	if player.player_died.is_connected(_on_local_player_died) == false:
		player.player_died.connect(_on_local_player_died)
	if player.player_respawned.is_connected(_on_local_player_respawned) == false:
		player.player_respawned.connect(_on_local_player_respawned)

func _on_local_player_died() -> void:
	# Hide HUD (includes health bar) and show overlay
	if hud:
		hud.hide()
	if death_overlay:
		death_overlay.show()
	# 5 second respawn timer (matches Player.RESPAWN_DELAY)
	respawn_end_ms = Time.get_ticks_msec() + 5000

func _on_local_player_respawned() -> void:
	if death_overlay:
		death_overlay.hide()
	if hud:
		hud.show()

func respawn_player(player: Node3D) -> void:
	if not player:
		return
	if int(player.team_id) == 0:
		player.position = TEAM_A_SPAWN_POS
		player.rotation.y = TEAM_A_YAW
	else:
		player.position = TEAM_B_SPAWN_POS
		player.rotation.y = TEAM_B_YAW

func spawn_tank_explosion_vfx_at(pos: Vector3) -> void:
	_spawn_tank_binbun_explosion_at(pos)

## One RPC for all peers (call_local) so explosive tank VFX is not spawned once per simulating client.
@rpc("any_peer", "call_local", "reliable")
func sync_tank_explosion_vfx(pos: Vector3) -> void:
	_spawn_tank_binbun_explosion_at(pos)

func _spawn_tank_binbun_explosion_at(pos: Vector3) -> void:
	var vfx: Node3D = TankExplosionVfxScene.instantiate() as Node3D
	vfx.autoplay = false
	vfx.one_shot = true
	add_child(vfx)
	vfx.global_position = pos
	if vfx.has_method("play"):
		vfx.play()
	get_tree().create_timer(TANK_EXPLOSION_VFX_CLEANUP_SEC).timeout.connect(func () -> void:
		if is_instance_valid(vfx):
			vfx.queue_free()
	)

# (Optional) UPnP setup – keep disabled until needed.
# func upnp_setup():
# 	var upnp = UPNP.new()
# 	var discover_result = upnp.discover()
# 	assert(discover_result == UPNP.UPNP_RESULT_SUCCESS, \
# 		"UPNP Discover Failed! Error %s" % discover_result)
# 	assert(upnp.get_gateway() and upnp.get_gateway().is_vaild_gateway(), \
# 		"UPNP Invalid gateway")
# 	var map_result = upnp.add_port_mapping(PORT)
# 	assert(map_result == UPNP.UPNP_RESULT_SUCCESS, \
# 	"UPNP Port Mapping Failed! Error %s" % map_result)
# 	print("Success! Join Address: %s" % upnp.query_external_address())
