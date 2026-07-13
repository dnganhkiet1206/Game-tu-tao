class_name MapLayout
## Single source of truth for the island layout.
## World space: X = 0..800 (west -> east), Z = 0..800 (north -> south), Y up.
## Sea lies to the west (x < ~120), sea level is y = 0.

const WORLD_SIZE := 800.0
const SEA_LEVEL := 0.0
const LAKE_LEVEL := 0.6

const TOWN_CENTER := Vector2(400, 400)
const LAKE_CENTER := Vector2(640, 180)
const LAKE_RADIUS := 55.0
const QUARRY_CENTER := Vector2(665, 615)
const QUARRY_RADIUS := 55.0
const FOREST_RECT := Rect2(150, 95, 215, 180)  # x, z, w, d
const BEACH_X_MIN := 85.0
const BEACH_X_MAX := 140.0

## Road polylines (center lines). Widths: main 7 m + shoulders.
const ROADS := [
	{"points": [Vector2(120, 400), Vector2(700, 400)], "width": 7.0},   # main street E-W
	{"points": [Vector2(400, 170), Vector2(400, 640)], "width": 6.0},   # north-south road
	{"points": [Vector2(400, 300), Vector2(664, 300)], "width": 5.5},   # residential street
	{"points": [Vector2(400, 220), Vector2(306, 220)], "width": 5.0},   # sawmill spur
	{"points": [Vector2(640, 400), Vector2(640, 566)], "width": 5.5},   # quarry road
	{"points": [Vector2(640, 300), Vector2(640, 196)], "width": 5.0},   # lake road
]

## Flatten pads: [center(x,z), radius, target height]. Applied smoothly.
const FLATTEN_PADS := [
	[Vector2(400, 400), 130.0, 3.0],    # town
	[Vector2(560, 300), 110.0, 3.4],    # residential
	[Vector2(300, 214), 45.0, 3.8],     # sawmill yard
	[Vector2(630, 545), 40.0, 5.2],     # quarry depot
	[Vector2(170, 420), 30.0, 1.8],     # fish market pad
	[Vector2(640, 235), 28.0, 1.6],     # lake shore / pier pad
]

## Buildings. rot = yaw degrees (0 faces +Z/south).
## kind: shop, cafe, garage, police, hospital, market, sawmill, depot, home, player_home
const BUILDINGS := [
	{"id": "shop", "kind": "shop", "name": "Tạp hoá Cô Ba", "pos": Vector2(350, 384), "size": Vector3(13, 4.2, 9), "rot": 0.0, "color": Color(0.93, 0.79, 0.62)},
	{"id": "cafe", "kind": "cafe", "name": "Quán Cơm Hải Âu", "pos": Vector2(320, 384), "size": Vector3(11, 4.0, 9), "rot": 0.0, "color": Color(0.72, 0.85, 0.78)},
	{"id": "garage", "kind": "garage", "name": "Gara Chú Tư", "pos": Vector2(468, 383), "size": Vector3(17, 5.0, 12), "rot": 0.0, "color": Color(0.72, 0.74, 0.78)},
	{"id": "police", "kind": "police", "name": "Trạm Cảnh Sát", "pos": Vector2(452, 418), "size": Vector3(15, 4.6, 10), "rot": 180.0, "color": Color(0.75, 0.82, 0.92)},
	{"id": "hospital", "kind": "hospital", "name": "Trạm Y Tế", "pos": Vector2(340, 418), "size": Vector3(15, 4.6, 10), "rot": 180.0, "color": Color(0.95, 0.95, 0.94)},
	{"id": "market", "kind": "market", "name": "Chợ Cá Bến Sóng", "pos": Vector2(170, 420), "size": Vector3(14, 4.2, 10), "rot": 180.0, "color": Color(0.62, 0.78, 0.86)},
	{"id": "sawmill", "kind": "sawmill", "name": "Xưởng Gỗ Sáu Bào", "pos": Vector2(300, 207), "size": Vector3(16, 4.6, 10), "rot": 0.0, "color": Color(0.78, 0.62, 0.45)},
	{"id": "depot", "kind": "depot", "name": "Trạm Thu Quặng", "pos": Vector2(622, 540), "size": Vector3(12, 4.2, 8), "rot": 90.0, "color": Color(0.66, 0.6, 0.55)},
	{"id": "fuel", "kind": "fuel", "name": "Trạm Xăng Hòn Gió", "pos": Vector2(566, 384), "size": Vector3(9, 3.8, 7), "rot": 0.0, "color": Color(0.92, 0.4, 0.32)},
	{"id": "town_house_1", "kind": "home", "name": "", "pos": Vector2(378, 384), "size": Vector3(10, 4.4, 8), "rot": 0.0, "color": Color(0.9, 0.86, 0.7)},
	{"id": "town_house_2", "kind": "home", "name": "", "pos": Vector2(426, 384), "size": Vector3(10, 4.6, 8), "rot": 0.0, "color": Color(0.85, 0.72, 0.6)},
	{"id": "player_home", "kind": "player_home", "name": "Nhà Của Bạn", "pos": Vector2(500, 284), "size": Vector3(11, 4.2, 8.5), "rot": 0.0, "color": Color(0.86, 0.89, 0.82)},
	{"id": "house_1", "kind": "home", "name": "", "pos": Vector2(534, 284), "size": Vector3(10, 4.0, 8), "rot": 0.0, "color": Color(0.92, 0.8, 0.66)},
	{"id": "house_2", "kind": "home", "name": "", "pos": Vector2(566, 284), "size": Vector3(9.5, 4.4, 8), "rot": 0.0, "color": Color(0.75, 0.82, 0.9)},
	{"id": "house_3", "kind": "home", "name": "", "pos": Vector2(598, 284), "size": Vector3(10, 4.2, 8), "rot": 0.0, "color": Color(0.88, 0.74, 0.72)},
	{"id": "house_4", "kind": "home", "name": "", "pos": Vector2(630, 284), "size": Vector3(9.5, 4.0, 8), "rot": 0.0, "color": Color(0.8, 0.87, 0.74)},
	{"id": "house_5", "kind": "home", "name": "", "pos": Vector2(518, 316), "size": Vector3(10, 4.2, 8), "rot": 180.0, "color": Color(0.9, 0.84, 0.68)},
	{"id": "house_6", "kind": "home", "name": "", "pos": Vector2(550, 316), "size": Vector3(9.5, 4.4, 8), "rot": 180.0, "color": Color(0.7, 0.8, 0.86)},
	{"id": "house_7", "kind": "home", "name": "", "pos": Vector2(582, 316), "size": Vector3(10, 4.0, 8), "rot": 180.0, "color": Color(0.87, 0.78, 0.62)},
	{"id": "house_8", "kind": "home", "name": "", "pos": Vector2(614, 316), "size": Vector3(9.5, 4.2, 8), "rot": 180.0, "color": Color(0.82, 0.76, 0.88)},
]

## Parked vehicles: kind = taxi | civic | pickup, owner "" = free/player-usable.
const VEHICLES := [
	{"id": "taxi_1", "kind": "taxi", "pos": Vector2(414, 388), "rot": 90.0, "owner": ""},
	{"id": "npc_car_1", "kind": "civic", "pos": Vector2(540, 292), "rot": 0.0, "owner": "npc"},
	{"id": "npc_car_2", "kind": "civic", "pos": Vector2(590, 307), "rot": 180.0, "owner": "npc"},
	{"id": "npc_car_3", "kind": "pickup", "pos": Vector2(310, 226), "rot": 90.0, "owner": "npc"},
	{"id": "npc_car_4", "kind": "pickup", "pos": Vector2(646, 528), "rot": 0.0, "owner": "npc"},
	{"id": "npc_car_5", "kind": "civic", "pos": Vector2(184, 416), "rot": 90.0, "owner": "npc"},
]

## Sea pier (into the sea, west) and lake pier.
const SEA_PIER := {"start": Vector2(118, 470), "dir": Vector2(-1, 0), "length": 46.0, "width": 3.2}
const LAKE_PIER := {"start": Vector2(640, 232), "dir": Vector2(0, -1), "length": 18.0, "width": 2.6}

const PLAYER_SPAWN := Vector3(500, 4.2, 293)  # in front of the player's house

## Taxi destinations (label + point).
const TAXI_SPOTS := [
	{"name": "Quảng trường thị trấn", "pos": Vector2(408, 392)},
	{"name": "Bãi biển", "pos": Vector2(140, 404)},
	{"name": "Chợ cá", "pos": Vector2(178, 420)},
	{"name": "Hồ Gương", "pos": Vector2(634, 244)},
	{"name": "Xưởng gỗ", "pos": Vector2(312, 226)},
	{"name": "Trạm thu quặng", "pos": Vector2(634, 532)},
	{"name": "Khu dân cư", "pos": Vector2(560, 306)},
	{"name": "Trạm y tế", "pos": Vector2(346, 420)},
]


static func building_by_id(id: String) -> Dictionary:
	for b in BUILDINGS:
		if b.id == id:
			return b
	return {}


## Door world position (front wall center) for a building entry.
static func door_pos(b: Dictionary) -> Vector2:
	var half_d: float = b.size.z * 0.5
	var yaw: float = deg_to_rad(b.rot)
	var forward := Vector2(sin(yaw), cos(yaw))  # +Z rotated by yaw
	return b.pos + forward * (half_d + 1.2)
