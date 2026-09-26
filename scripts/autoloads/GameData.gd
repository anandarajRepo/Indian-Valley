extends Node
## GameData.gd — Autoload holding global player state.
##
## Single source of truth for:
##   gold, player name, energy, skill levels, farm progress, shipping chest
##
## Does NOT handle saving/loading (that's SaveManager).
## Does NOT manage time (that's GameClock).

signal gold_changed(new_amount: int)
signal energy_changed(new_energy: int, max_energy: int)
signal day_ended_processing()  ## Fired during overnight processing before clock ticks

# ---------------------------------------------------------------------------
# Player identity
# ---------------------------------------------------------------------------

var player_name: String    = "Arya"
var player_skin: int       = 0
var player_hair: int       = 0

# ---------------------------------------------------------------------------
# Economy
# ---------------------------------------------------------------------------

const STARTING_GOLD: int = 500

var gold: int = STARTING_GOLD          ## Starting gold

## Gold earned from the most recent overnight shipping run (for the day summary).
var last_earnings: int = 0

# ---------------------------------------------------------------------------
# Energy
# ---------------------------------------------------------------------------

var energy_max: int     = 100
var energy_current: int = 100

# ---------------------------------------------------------------------------
# Skills  (0–10 each)
# ---------------------------------------------------------------------------

var skill_farming:  int = 0
var skill_mining:   int = 0
var skill_foraging: int = 0
var skill_fishing:  int = 0
var skill_combat:   int = 0

const XP_PER_LEVEL: int = 100   ## XP needed per skill level (simple linear for now)

var _skill_xp: Dictionary = {
	"farming":  0,
	"mining":   0,
	"foraging": 0,
	"fishing":  0,
	"combat":   0,
}

# ---------------------------------------------------------------------------
# Shipping chest
# ---------------------------------------------------------------------------

## Array of { "item_id": String, "quantity": int } dicts
var shipping_chest: Array = []

# ---------------------------------------------------------------------------
# Lifetime stats (shown in the journal and the year-end review)
# ---------------------------------------------------------------------------

const DEFAULT_STATS: Dictionary = {
	"total_earned":       0,
	"crops_harvested":    0,
	"fish_caught":        0,
	"items_foraged":      0,
	"gifts_given":        0,
	"festivals_attended": 0,
	"days_played":        0,
}

var stats: Dictionary = DEFAULT_STATS.duplicate()

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Connect to clock so we can do overnight processing
	GameClock.sleep_triggered.connect(_on_sleep_triggered)


# ---------------------------------------------------------------------------
# Gold
# ---------------------------------------------------------------------------

func add_gold(amount: int) -> void:
	gold += amount
	emit_signal("gold_changed", gold)


func spend_gold(amount: int) -> bool:
	## Returns false if player can't afford it.
	if gold < amount:
		return false
	gold -= amount
	emit_signal("gold_changed", gold)
	return true


# ---------------------------------------------------------------------------
# Energy
# ---------------------------------------------------------------------------

func spend_energy(amount: int) -> bool:
	## Deduct energy. Returns false if not enough (caller should block action).
	if energy_current <= 0:
		return false
	energy_current = max(0, energy_current - amount)
	emit_signal("energy_changed", energy_current, energy_max)
	if energy_current == 0:
		# Force sleep immediately
		GameClock._trigger_sleep()
	return true


func restore_energy(amount: int = -1) -> void:
	## Pass -1 to fully restore (on sleep).
	if amount == -1:
		energy_current = energy_max
	else:
		energy_current = min(energy_max, energy_current + amount)
	emit_signal("energy_changed", energy_current, energy_max)


func get_energy_ratio() -> float:
	return float(energy_current) / float(energy_max)


# ---------------------------------------------------------------------------
# Skills / XP
# ---------------------------------------------------------------------------

func add_skill_xp(skill: String, xp: int) -> void:
	if not _skill_xp.has(skill):
		return
	_skill_xp[skill] += xp
	var current_level = get_skill_level(skill)
	if current_level >= 10:
		return
	if _skill_xp[skill] >= XP_PER_LEVEL * (current_level + 1):
		_level_up_skill(skill)


func get_skill_level(skill: String) -> int:
	match skill:
		"farming":  return skill_farming
		"mining":   return skill_mining
		"foraging": return skill_foraging
		"fishing":  return skill_fishing
		"combat":   return skill_combat
	return 0


func _level_up_skill(skill: String) -> void:
	match skill:
		"farming":  skill_farming  = min(10, skill_farming  + 1)
		"mining":   skill_mining   = min(10, skill_mining   + 1)
		"foraging": skill_foraging = min(10, skill_foraging + 1)
		"fishing":  skill_fishing  = min(10, skill_fishing  + 1)
		"combat":   skill_combat   = min(10, skill_combat   + 1)
	print("[GameData] Levelled up %s to %d!" % [skill, get_skill_level(skill)])


func get_skill_xp(skill: String) -> int:
	return int(_skill_xp.get(skill, 0))


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

func record_stat(stat: String, amount: int = 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + amount


func get_stat(stat: String) -> int:
	return int(stats.get(stat, 0))


# ---------------------------------------------------------------------------
# Shipping chest
# ---------------------------------------------------------------------------

func add_to_shipping(item_id: String, quantity: int) -> void:
	for entry in shipping_chest:
		if entry["item_id"] == item_id:
			entry["quantity"] += quantity
			return
	shipping_chest.append({"item_id": item_id, "quantity": quantity})


func process_shipping() -> int:
	## Resolve overnight sales and credit gold. Returns the amount earned.
	var total_earned: int = 0
	for entry in shipping_chest:
		var item = ItemDB.get_item(entry["item_id"])
		if not item.is_empty():
			total_earned += item.get("sell_price", 0) * entry["quantity"]
	shipping_chest.clear()
	last_earnings = total_earned
	if total_earned > 0:
		add_gold(total_earned)
		record_stat("total_earned", total_earned)
		print("[GameData] Overnight sales: +%d gold" % total_earned)
	return total_earned


# ---------------------------------------------------------------------------
# Sleep / overnight
# ---------------------------------------------------------------------------

func _on_sleep_triggered() -> void:
	## Overnight orchestration. Runs whenever the player sleeps or passes out.
	var earnings := process_shipping()
	restore_energy()
	record_stat("days_played")
	emit_signal("day_ended_processing")

	# Advance the calendar to the next morning.
	GameClock.end_day()

	# Let the game manager advance the farm simulation, persist, and show the
	# day summary. Looked up via group rather than the GameManager class, since
	# autoloads compile before global class names are registered.
	var gm = get_tree().get_first_node_in_group("game")
	if gm != null:
		gm.on_overnight(earnings)


func reset_to_new_game() -> void:
	## Reset all player state for a fresh game.
	player_name    = "Arya"
	player_skin    = 0
	player_hair    = 0
	gold           = STARTING_GOLD
	last_earnings  = 0
	energy_max     = 100
	energy_current = energy_max
	skill_farming  = 0
	skill_mining   = 0
	skill_foraging = 0
	skill_fishing  = 0
	skill_combat   = 0
	_skill_xp      = {"farming": 0, "mining": 0, "foraging": 0, "fishing": 0, "combat": 0}
	shipping_chest = []
	stats          = DEFAULT_STATS.duplicate()
	emit_signal("gold_changed", gold)
	emit_signal("energy_changed", energy_current, energy_max)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"player_name":   player_name,
		"player_skin":   player_skin,
		"player_hair":   player_hair,
		"gold":          gold,
		"energy_max":    energy_max,
		"energy_current":energy_current,
		"skill_farming":  skill_farming,
		"skill_mining":   skill_mining,
		"skill_foraging": skill_foraging,
		"skill_fishing":  skill_fishing,
		"skill_combat":   skill_combat,
		"skill_xp":       _skill_xp,
		"shipping_chest": shipping_chest,
		"stats":          stats,
	}


func from_dict(d: Dictionary) -> void:
	player_name    = d.get("player_name",    "Arya")
	player_skin    = d.get("player_skin",    0)
	player_hair    = d.get("player_hair",    0)
	gold           = d.get("gold",           500)
	energy_max     = d.get("energy_max",     100)
	energy_current = d.get("energy_current", 100)
	skill_farming  = d.get("skill_farming",  0)
	skill_mining   = d.get("skill_mining",   0)
	skill_foraging = d.get("skill_foraging", 0)
	skill_fishing  = d.get("skill_fishing",  0)
	skill_combat   = d.get("skill_combat",   0)
	_skill_xp      = d.get("skill_xp",       {"farming":0,"mining":0,"foraging":0,"fishing":0,"combat":0})
	shipping_chest = d.get("shipping_chest", [])
	stats          = DEFAULT_STATS.duplicate()
	var saved_stats: Dictionary = d.get("stats", {})
	for key in saved_stats:
		stats[key] = int(saved_stats[key])   # JSON numbers load as floats
	emit_signal("gold_changed", gold)
	emit_signal("energy_changed", energy_current, energy_max)
