class_name NpcData
## Static cast of the island. 24 residents, each with a name, job, home and
## the anchor points their daily schedule moves between.
## role: vendor | outdoor | villager | police
## work: building id (vendor) or Vector2 outdoor spot

const CAST := [
	{"id": "co_ba", "name": "Cô Ba", "role": "vendor", "work": "shop", "home": "", "anim": "idle"},
	{"id": "chu_tu", "name": "Chú Tư", "role": "vendor", "work": "garage", "home": "", "anim": "idle"},
	{"id": "chi_hen", "name": "Chị Hến", "role": "vendor", "work": "market", "home": "house_5", "anim": "idle"},
	{"id": "chu_sau", "name": "Chú Sáu Bào", "role": "vendor", "work": "sawmill", "home": "", "anim": "idle"},
	{"id": "co_quyen", "name": "Cô Quyên", "role": "vendor", "work": "depot", "home": "house_8", "anim": "idle"},
	{"id": "di_bay", "name": "Dì Bảy", "role": "vendor", "work": "cafe", "home": "", "anim": "idle"},
	{"id": "chu_hai_xang", "name": "Chú Hai Xăng", "role": "vendor", "work": "fuel", "home": "house_1", "anim": "idle"},
	{"id": "y_ta_lan", "name": "Y tá Lan", "role": "vendor", "work": "hospital", "home": "house_2", "anim": "idle"},
	{"id": "y_ta_hung", "name": "Y tá Hùng", "role": "vendor", "work": "hospital", "home": "house_6", "anim": "idle"},

	{"id": "ngu_dan_teo", "name": "Anh Tèo", "role": "outdoor", "work": Vector2(96, 468), "home": "house_1", "anim": "fish"},
	{"id": "ngu_dan_muoi", "name": "Chú Mười", "role": "outdoor", "work": Vector2(112, 512), "home": "house_1", "anim": "fish"},
	{"id": "ngu_dan_ut", "name": "Cậu Út", "role": "outdoor", "work": Vector2(636, 220), "home": "house_3", "anim": "fish"},
	{"id": "tieu_phu_binh", "name": "Anh Bình", "role": "outdoor", "work": Vector2(250, 180), "home": "house_4", "anim": "work"},
	{"id": "tieu_phu_cu", "name": "Chú Cự", "role": "outdoor", "work": Vector2(210, 230), "home": "house_4", "anim": "work"},
	{"id": "tho_mo_dung", "name": "Anh Dũng", "role": "outdoor", "work": Vector2(650, 600), "home": "house_7", "anim": "work"},
	{"id": "tho_mo_phuc", "name": "Anh Phúc", "role": "outdoor", "work": Vector2(680, 625), "home": "house_7", "anim": "work"},
	{"id": "tho_mo_nam", "name": "Ông Năm", "role": "outdoor", "work": Vector2(665, 585), "home": "house_3", "anim": "work"},

	{"id": "ba_tam", "name": "Bà Tám", "role": "villager", "work": Vector2(420, 386), "home": "town_house_1", "anim": "talk"},
	{"id": "ong_chin", "name": "Ông Chín", "role": "villager", "work": Vector2(414, 390), "home": "town_house_1", "anim": "idle"},
	{"id": "chi_nga", "name": "Chị Nga", "role": "villager", "work": Vector2(560, 306), "home": "house_5", "anim": "idle"},
	{"id": "be_mai", "name": "Bé Mai", "role": "villager", "work": Vector2(130, 470), "home": "house_2", "anim": "idle"},
	{"id": "anh_khoa", "name": "Anh Khoa", "role": "villager", "work": Vector2(634, 246), "home": "house_6", "anim": "idle"},
	{"id": "chi_thu", "name": "Chị Thu", "role": "villager", "work": Vector2(348, 396), "home": "town_house_2", "anim": "idle"},

	{"id": "cs_long", "name": "CS Long", "role": "police", "work": "police", "home": "", "anim": "idle"},
	{"id": "cs_manh", "name": "CS Mạnh", "role": "police", "work": "police", "home": "", "anim": "idle"},
]

const SHIRTS := [
	Color(0.75, 0.3, 0.25), Color(0.3, 0.5, 0.65), Color(0.9, 0.75, 0.4),
	Color(0.4, 0.6, 0.4), Color(0.7, 0.55, 0.7), Color(0.85, 0.85, 0.8),
	Color(0.5, 0.35, 0.3), Color(0.35, 0.55, 0.55),
]
const PANTS := [
	Color(0.25, 0.28, 0.35), Color(0.4, 0.35, 0.3), Color(0.3, 0.4, 0.45), Color(0.2, 0.2, 0.22),
]
const SKINS := [
	Color(0.92, 0.76, 0.62), Color(0.85, 0.65, 0.5), Color(0.75, 0.58, 0.45),
]
const HAIRS := [
	Color(0.1, 0.09, 0.08), Color(0.25, 0.18, 0.12), Color(0.45, 0.45, 0.48), Color(0.15, 0.13, 0.1),
]

const LINES := {
	"vendor": [
		"Mua gì cứ xem thoải mái nghen!",
		"Dạo này biển động, hàng về chậm lắm.",
		"Chú Tư sửa xe mát tay nhất đảo đó.",
	],
	"outdoor": [
		"Trời đẹp thế này làm việc sướng thiệt.",
		"Hồi sáng tui thấy cá mú đỏ ở cầu tàu đó!",
		"Làm nghề này cực mà vui, chú em.",
	],
	"villager": [
		"Đảo Hòn Gió mình yên bình ha.",
		"Chiều chiều ra bãi biển hóng gió là nhất.",
		"Nghe nói trên mỏ có quặng vàng đó nghen.",
		"Quán cơm Dì Bảy nấu ngon nhức nách!",
	],
	"police": [
		"Giữ trật tự giùm nghen, tui đang trực.",
		"Chạy xe cẩn thận, trên đảo nhiều người già.",
	],
	"night": [
		"Khuya rồi, tui buồn ngủ quá…",
		"Về ngủ sớm đi, mai còn làm việc.",
	],
	"rain": [
		"Mưa gió vầy, nhớ mặc áo mưa nghen.",
		"Trú mưa chút đã rồi hẵng đi.",
	],
}


static func palette_for(seed_id: String) -> Array:
	var h := hash(seed_id)
	return [
		SHIRTS[h % SHIRTS.size()],
		PANTS[(h / 7) % PANTS.size()],
		SKINS[(h / 31) % SKINS.size()],
		HAIRS[(h / 131) % HAIRS.size()],
	]


static func line_for(role: String) -> String:
	var pool: Array = LINES.get(role, LINES.villager)
	if DayNight.is_night() and randf() < 0.5:
		pool = LINES.night
	elif DayNight.rain_amount > 0.4 and randf() < 0.5:
		pool = LINES.rain
	return pool[randi() % pool.size()]
