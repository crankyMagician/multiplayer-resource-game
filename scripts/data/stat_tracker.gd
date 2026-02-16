class_name StatTracker
extends RefCounted

## Server-side stat tracking utility. All methods operate on player data
## dictionaries from NetworkManager.player_data_store — call only on the server.
##
## Call StatTracker.init(player_data_store) once from NetworkManager._ready().
## Tests can set StatTracker._store directly.

static var _store: Dictionary = {}

static func init(store: Dictionary) -> void:
	_store = store

static func _ensure_stats(peer_id: int) -> Dictionary:
	if peer_id not in _store:
		return {}
	var data: Dictionary = _store[peer_id]
	if not data.has("stats"):
		data["stats"] = {}
	return data["stats"]

static func _ensure_compendium(peer_id: int) -> Dictionary:
	if peer_id not in _store:
		return {}
	var data: Dictionary = _store[peer_id]
	if not data.has("compendium"):
		data["compendium"] = {"items": [], "creatures_seen": [], "creatures_owned": []}
	return data["compendium"]

static func increment(peer_id: int, stat_key: String, amount: int = 1) -> void:
	if peer_id not in _store:
		return
	var stats = _ensure_stats(peer_id)
	stats[stat_key] = stats.get(stat_key, 0) + amount

static func increment_species(peer_id: int, stat_key: String, species_id: String, amount: int = 1) -> void:
	if peer_id not in _store:
		return
	var stats = _ensure_stats(peer_id)
	if stat_key not in stats:
		stats[stat_key] = {}
	stats[stat_key][species_id] = stats[stat_key].get(species_id, 0) + amount

static func unlock_compendium_item(peer_id: int, item_id: String) -> void:
	if peer_id not in _store:
		return
	var comp = _ensure_compendium(peer_id)
	var items: Array = comp.get("items", [])
	if item_id not in items:
		items.append(item_id)
		comp["items"] = items

static func unlock_creature_seen(peer_id: int, species_id: String) -> void:
	if peer_id not in _store:
		return
	var comp = _ensure_compendium(peer_id)
	var seen: Array = comp.get("creatures_seen", [])
	if species_id not in seen:
		seen.append(species_id)
		comp["creatures_seen"] = seen

static func unlock_creature_owned(peer_id: int, species_id: String) -> void:
	if peer_id not in _store:
		return
	var comp = _ensure_compendium(peer_id)
	var owned: Array = comp.get("creatures_owned", [])
	if species_id not in owned:
		owned.append(species_id)
		comp["creatures_owned"] = owned
	# Also mark as seen
	var seen: Array = comp.get("creatures_seen", [])
	if species_id not in seen:
		seen.append(species_id)
		comp["creatures_seen"] = seen
