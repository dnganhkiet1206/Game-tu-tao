extends Node
## Central game state: money, inventory, ownership, stats, save/load.
## Everything that must survive a save/load round-trip lives here.

const SAVE_PATH := "user://hongio_save.json"
const SAVE_VERSION := 1

## Item database. sell = price NPC vendors pay, buy = price in shops (0 = not sold).
const ITEMS := {
	"fish_common": {"name": "Cá rô phi", "sell": 12, "buy": 0, "icon": "🐟"},
	"fish_fine": {"name": "Cá chẽm", "sell": 35, "buy": 0, "icon": "🐟"},
	"fish_rare": {"name": "Cá mú đỏ", "sell": 110, "buy": 0, "icon": "🐠"},
	"log": {"name": "Gỗ tròn", "sell": 18, "buy": 0, "icon": "🪵"},
	"ore_copper": {"name": "Quặng đồng", "sell": 22, "buy": 0, "icon": "🪨"},
	"ore_iron": {"name": "Quặng sắt", "sell": 40, "buy": 0, "icon": "⛏"},
	"ore_gold": {"name": "Quặng vàng", "sell": 150, "buy": 0, "icon": "✨"},
	"banh_mi": {"name": "Bánh mì", "sell": 3, "buy": 8, "icon": "🥖"},
	"ca_phe": {"name": "Cà phê sữa", "sell": 4, "buy": 10, "icon": "☕"},
	"rod": {"name": "Cần câu", "sell": 0, "buy": 60, "icon": "🎣"},
	"axe": {"name": "Rìu chặt gỗ", "sell": 0, "buy": 90, "icon": "🪓"},
	"pickaxe": {"name": "Cuốc chim", "sell": 0, "buy": 120, "icon": "⛏"},
	"package": {"name": "Kiện hàng", "sell": 0, "buy": 0, "icon": "📦"},
}

## Vehicles purchasable at the garage.
const CAR_CATALOG := {
	"minica": {"name": "Cá Con 1.0", "price": 900, "color": Color(0.85, 0.35, 0.2), "top_speed": 16.0},
	"sedan": {"name": "Sóng Biển GT", "price": 2400, "color": Color(0.15, 0.4, 0.75), "top_speed": 22.0},
}

const HOUSE_TIERS := [
	{"name": "Nhà trống", "price": 0},
	{"name": "Nội thất cơ bản", "price": 500},
	{"name": "Nội thất đầy đủ", "price": 1500},
	{"name": "Nhà ven biển mơ ước", "price": 4000},
]

var money: int = 150
var inventory: Dictionary = {}
var owned_cars: Array = []
var house_tier: int = 0
var stats: Dictionary = {
	"fish_caught": 0,
	"trees_felled": 0,
	"ore_mined": 0,
	"taxi_fares": 0,
	"deliveries": 0,
	"earned_total": 0,
	"fines_paid": 0,
}
var quality: int = 1  # 0 = low, 1 = medium, 2 = high
var ui_blocked: bool = false  # true while a modal panel / menu / fade owns input
var player: Node3D = null
var world: Node3D = null
var loaded_from_save: bool = false
var pending_spawn: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# --- Money ------------------------------------------------------------------

func add_money(amount: int, silent: bool = false) -> void:
	money += amount
	if amount > 0:
		stats.earned_total += amount
	Events.money_changed.emit(money)
	if not silent and amount != 0:
		var sign_txt := "+" if amount > 0 else "-"
		Events.toast.emit("%s%s₫" % [sign_txt, _fmt(absi(amount))])


func try_spend(amount: int) -> bool:
	if money < amount:
		Events.toast.emit("Không đủ tiền (cần %s₫)" % _fmt(amount))
		Audio.play_ui("denied")
		return false
	money -= amount
	Events.money_changed.emit(money)
	return true


static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return out


static func format_money(n: int) -> String:
	return _fmt(n) + "₫"


# --- Inventory --------------------------------------------------------------

func add_item(item_id: String, count: int = 1) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + count
	Events.inventory_changed.emit()
	Events.item_picked_up.emit(item_id, count)


func remove_item(item_id: String, count: int = 1) -> bool:
	var have := int(inventory.get(item_id, 0))
	if have < count:
		return false
	if have == count:
		inventory.erase(item_id)
	else:
		inventory[item_id] = have - count
	Events.inventory_changed.emit()
	return true


func count_item(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func has_tool(tool_id: String) -> bool:
	return count_item(tool_id) > 0


func item_name(item_id: String) -> String:
	if ITEMS.has(item_id):
		return ITEMS[item_id].name
	return item_id


# --- Save / load ------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"money": money,
		"inventory": inventory,
		"owned_cars": owned_cars,
		"house_tier": house_tier,
		"stats": stats,
		"quality": quality,
		"time_hours": DayNight.time_hours,
		"day": DayNight.day,
	}
	if is_instance_valid(player):
		data["player_pos"] = _v3_to_arr(player.global_position)
		data["player_yaw"] = player.rotation.y
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		Events.toast.emit("Không thể lưu game!")
		return
	file.store_string(JSON.stringify(data))
	file.close()
	Events.game_saved.emit()
	Events.toast.emit("Đã lưu game ✓")
	Audio.play_ui("save")


func load_game() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return false
	var data: Dictionary = parsed
	money = int(data.get("money", 150))
	inventory = data.get("inventory", {})
	owned_cars = data.get("owned_cars", [])
	house_tier = int(data.get("house_tier", 0))
	var saved_stats: Dictionary = data.get("stats", {})
	for key in saved_stats:
		stats[key] = saved_stats[key]
	quality = int(data.get("quality", 1))
	DayNight.time_hours = float(data.get("time_hours", 8.0))
	DayNight.day = int(data.get("day", 1))
	pending_spawn = {}
	if data.has("player_pos"):
		pending_spawn["pos"] = _arr_to_v3(data.player_pos)
		pending_spawn["yaw"] = float(data.get("player_yaw", 0.0))
	loaded_from_save = true
	Events.game_loaded.emit()
	return true


func new_game() -> void:
	money = 150
	inventory = {"rod": 1, "banh_mi": 2}
	owned_cars = []
	house_tier = 0
	for key in stats:
		stats[key] = 0
	DayNight.time_hours = 7.5
	DayNight.day = 1
	loaded_from_save = false
	pending_spawn = {}


static func _v3_to_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _arr_to_v3(a: Array) -> Vector3:
	if a.size() != 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
