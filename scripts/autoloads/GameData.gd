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

var gold: int = 500          ## Starting gold

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


# ---------------------------------------------------------------------------
# Shipping chest
# ---------------------------------------------------------------------------

func add_to_shipping(item_id: String, quantity: int) -> void:
	for entry in shipping_chest:
		if entry["item_id"] == item_id:
			entry["quantity"] += quantity
			return
	shipping_chest.append({"item_id": item_id, "quantity": quantity})


func _process_shipping() -> void:
	## Resolve overnight sales and credit gold.
	var total_earned: int = 0
	for entry in shipping_chest:
		var item = ItemDB.get_item(entry["item_id"])
		if item:
			total_earned += item["sell_price"] * entry["quantity"]
	shipping_chest.clear()
	if total_earned > 0:
		add_gold(total_earned)
		print("[GameData] Overnight sales: +%d gold" % total_earned)


# ---------------------------------------------------------------------------
# Sleep / overnight
# ---------------------------------------------------------------------------

func _on_sleep_triggered() -> void:
	_process_shipping()
	restore_energy()
	emit_signal("day_ended_processing")
	# Tell the clock to advance the day
	GameClock.end_day()


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
	emit_signal("gold_changed", gold)
	emit_signal("energy_changed", energy_current, energy_max)
