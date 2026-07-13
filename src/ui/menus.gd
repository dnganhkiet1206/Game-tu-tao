class_name Menus
extends Control
## Title screen, pause menu, the house-upgrade dialog and the controls guide.

signal start_requested(load_save: bool)

var _main_menu: Control
var _pause_menu: Control
var _upgrade_menu: Control
var _help_menu: Control
var _quality_rows: Array[HBoxContainer] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_main_menu()
	_build_pause_menu()
	_build_upgrade_menu()
	_build_help_menu()  # built last so it overlays the menu that opened it


func any_open() -> bool:
	return _main_menu.visible or _pause_menu.visible or _upgrade_menu.visible \
		or _help_menu.visible


func is_pause_open() -> bool:
	return _pause_menu.visible


func is_upgrade_open() -> bool:
	return _upgrade_menu.visible


func is_help_open() -> bool:
	return _help_menu.visible


func _hud() -> Hud:
	return get_tree().get_first_node_in_group("hud")


# --- title screen -------------------------------------------------------------

func _build_main_menu() -> void:
	_main_menu = Control.new()
	_main_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu.visible = false
	add_child(_main_menu)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.1, 0.16, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := Label.new()
	title.text = "HÒN GIÓ"
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.98, 0.92, 0.75))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.3, 0.9))
	title.add_theme_constant_override("outline_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Một hòn đảo nhỏ • một cuộc sống mới\n— bản demo kỹ thuật —"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	box.add_child(subtitle)

	box.add_child(_spacer(18))

	var continue_btn := Button.new()
	continue_btn.name = "ContinueBtn"
	continue_btn.text = "▶  Chơi tiếp"
	continue_btn.custom_minimum_size = Vector2(320, 54)
	continue_btn.pressed.connect(func() -> void: _start(true))
	box.add_child(continue_btn)

	var new_btn := Button.new()
	new_btn.text = "✦  Chơi mới"
	new_btn.custom_minimum_size = Vector2(320, 54)
	new_btn.pressed.connect(func() -> void: _start(false))
	box.add_child(new_btn)

	box.add_child(_quality_row())
	box.add_child(_help_button())


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _quality_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "Đồ hoạ:"
	label.add_theme_font_size_override("font_size", 22)
	row.add_child(label)
	var names := ["Thấp", "Vừa", "Cao"]
	for i in 3:
		var btn := Button.new()
		btn.text = names[i]
		btn.toggle_mode = true
		btn.set_meta("quality", i)
		btn.button_pressed = Game.quality == i
		btn.custom_minimum_size = Vector2(92, 44)
		btn.pressed.connect(func() -> void:
			Game.quality = i
			Game.save_settings()
			_sync_quality_rows()
			if is_instance_valid(Game.world):
				Game.world.apply_quality()
		)
		row.add_child(btn)
	_quality_rows.append(row)
	return row


## Both menus (title + pause) show a quality row; keep every button in
## step with Game.quality — it can change from the other menu or a loaded save.
func _sync_quality_rows() -> void:
	for row in _quality_rows:
		if not is_instance_valid(row):
			continue
		for child in row.get_children():
			if child is Button:
				(child as Button).button_pressed = child.get_meta("quality") == Game.quality


# --- controls guide ----------------------------------------------------------------

func _help_button() -> Button:
	var btn := Button.new()
	btn.text = "📖  Hướng dẫn điều khiển"
	btn.custom_minimum_size = Vector2(320, 48)
	btn.pressed.connect(open_help)
	return btn


## Two-column cheat sheet: touch controls (the real target) + PC test keys.
## Opened from the title screen or the pause menu, so the game is already
## paused and input-blocked — this is a pure overlay on top.
func _build_help_menu() -> void:
	_help_menu = Control.new()
	_help_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_menu.visible = false
	add_child(_help_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "📖 HƯỚNG DẪN ĐIỀU KHIỂN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)

	_help_header(rows, "📱 Trên điện thoại")
	_help_row(rows, "Nửa trái màn hình", "Joystick ảo — chạm đâu hiện đó, kéo để đi")
	_help_row(rows, "Vuốt nửa phải", "Xoay camera")
	_help_row(rows, "Nút ❗ / ✋", "Tương tác: cửa, nói chuyện, mua bán, câu cá, lên xe")
	_help_row(rows, "Nút ⬆", "Nhảy / leo lên vật cản, gờ tường")
	_help_row(rows, "Nút 🏃", "Bật / tắt chạy nhanh")
	_help_row(rows, "Nút 👊", "Đấm (cẩn thận bị truy nã!)")
	_help_row(rows, "Chạm minimap", "Mở bản đồ toàn đảo")
	_help_row(rows, "Trong xe", "▲ ga  •  ▼ phanh/lùi  •  🅿 phanh tay  •  📢 còi  •  🚪 ra xe")

	_help_header(rows, "⌨️ Trên máy tính (bản test)")
	_help_row(rows, "W A S D / mũi tên", "Di chuyển — trong xe: W ga, S lùi, A-D lái")
	_help_row(rows, "Space", "Nhảy / leo — trong xe: phanh tay")
	_help_row(rows, "Shift", "Chạy nhanh")
	_help_row(rows, "E", "Tương tác / ra xe")
	_help_row(rows, "F", "Đấm")
	_help_row(rows, "H", "Còi xe")
	_help_row(rows, "Kéo chuột nửa phải", "Xoay camera")
	_help_row(rows, "M", "Bản đồ toàn đảo")
	_help_row(rows, "Esc", "Tạm dừng / đóng bảng đang mở")

	_help_header(rows, "💡 Mẹo nhanh")
	_help_row(rows, "Ngủ sau 19:00", "Lưu game và sang ngày mới (giường nhà bạn)")
	_help_row(rows, "Hết xăng", "Đổ ở trạm xăng, hoặc lấy can dự phòng trong cốp xe")
	_help_row(rows, "Bị truy nã ⭐", "Chạy trốn đủ lâu, nộp phạt ở trạm cảnh sát — hoặc bơi ra biển")

	var close := Button.new()
	close.text = "Đóng"
	close.pressed.connect(close_help)
	box.add_child(close)


func _help_header(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	parent.add_child(label)


func _help_row(parent: VBoxContainer, control_name: String, effect: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left := Label.new()
	left.text = control_name
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_font_size_override("font_size", 19)
	left.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	var right := Label.new()
	right.text = effect
	right.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_font_size_override("font_size", 19)
	right.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	row.add_child(left)
	row.add_child(right)
	parent.add_child(row)


func open_help() -> void:
	_help_menu.visible = true
	Audio.play_ui("click")


func close_help() -> void:
	_help_menu.visible = false
	Audio.play_ui("click")


func open_main(has_save: bool) -> void:
	_main_menu.visible = true
	_sync_quality_rows()
	var continue_btn: Button = _main_menu.find_child("ContinueBtn", true, false)
	if continue_btn != null:
		continue_btn.visible = has_save
	get_tree().paused = true
	_hud().push_block()


func _start(load_save: bool) -> void:
	_main_menu.visible = false
	get_tree().paused = false
	_hud().pop_block()
	Audio.play_ui("click")
	start_requested.emit(load_save)


# --- pause ---------------------------------------------------------------------

func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.visible = false
	add_child(_pause_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "TẠM DỪNG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	var resume := Button.new()
	resume.text = "▶  Tiếp tục"
	resume.pressed.connect(close_pause)
	box.add_child(resume)

	var save := Button.new()
	save.text = "💾  Lưu game"
	save.pressed.connect(func() -> void: Game.save_game())
	box.add_child(save)

	box.add_child(_quality_row())
	box.add_child(_help_button())

	var stats := Label.new()
	stats.name = "StatsLabel"
	stats.add_theme_font_size_override("font_size", 19)
	stats.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stats)


func open_pause() -> void:
	if any_open():
		return
	_pause_menu.visible = true
	_sync_quality_rows()
	get_tree().paused = true
	_hud().push_block()
	var stats: Label = _pause_menu.find_child("StatsLabel", true, false)
	if stats != null:
		stats.text = "🐟 %d cá  •  🌲 %d cây  •  ⛏ %d quặng\n🚕 %d cuốc xe  •  📦 %d chuyến giao\nTổng thu nhập: %s" % [
			Game.stats.fish_caught, Game.stats.trees_felled, Game.stats.ore_mined,
			Game.stats.taxi_fares, Game.stats.deliveries, Game.format_money(int(Game.stats.earned_total)),
		]


func close_pause() -> void:
	_pause_menu.visible = false
	get_tree().paused = false
	_hud().pop_block()


# --- house upgrade ----------------------------------------------------------------

func _build_upgrade_menu() -> void:
	_upgrade_menu = Control.new()
	_upgrade_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_upgrade_menu.visible = false
	add_child(_upgrade_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_upgrade_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_upgrade_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "UpgradeBox"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)


func open_upgrade() -> void:
	_upgrade_menu.visible = true
	_hud().push_block()
	var box: VBoxContainer = _upgrade_menu.find_child("UpgradeBox", true, false)
	for child in box.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "🏠 Nâng cấp nhà"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var tier: int = Game.house_tier
	var current := Label.new()
	current.text = "Hiện tại: %s" % Game.HOUSE_TIERS[tier].name
	current.add_theme_font_size_override("font_size", 22)
	current.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(current)

	if tier < Game.HOUSE_TIERS.size() - 1:
		var next: Dictionary = Game.HOUSE_TIERS[tier + 1]
		var buy := Button.new()
		buy.text = "Nâng lên: %s — %s" % [next.name, Game.format_money(next.price)]
		buy.disabled = Game.money < next.price
		buy.pressed.connect(func() -> void:
			if Game.try_spend(next.price):
				Game.house_tier += 1
				Audio.play_ui("save")
				Game.world.rebuild_player_home()
				Game.save_game()
				Events.toast.emit("🏠 Nhà đã được nâng cấp!")
				close_upgrade()
		)
		box.add_child(buy)
	else:
		var done := Label.new()
		done.text = "Nhà của bạn đã đẹp nhất đảo! ✨"
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.add_theme_font_size_override("font_size", 22)
		box.add_child(done)

	var close := Button.new()
	close.text = "Đóng"
	close.pressed.connect(close_upgrade)
	box.add_child(close)


func close_upgrade() -> void:
	_upgrade_menu.visible = false
	_hud().pop_block()
