class_name ShopPanel
extends Control
## Modal buy/sell panel used by every vendor counter.

var _panel: PanelContainer
var _title: Label
var _money: Label
var _rows: VBoxContainer
var _kind := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(600, 380)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var header := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 24)
	_money.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	header.add_child(_title)
	header.add_child(_money)
	box.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 250)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	box.add_child(scroll)

	var close := Button.new()
	close.text = "Đóng"
	close.pressed.connect(close_panel)
	box.add_child(close)

	Events.money_changed.connect(func(_m: int) -> void:
		if visible:
			_refresh()
	)
	Events.inventory_changed.connect(func() -> void:
		if visible:
			_refresh()
	)


func _hud() -> Hud:
	return get_tree().get_first_node_in_group("hud")


func open(kind: String) -> void:
	_kind = kind
	visible = true
	_hud().push_block()
	Audio.play_ui("click")
	_refresh()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	_hud().pop_block()
	Audio.play_ui("click")


func _refresh() -> void:
	_money.text = Game.format_money(Game.money)
	for child in _rows.get_children():
		child.queue_free()
	match _kind:
		"shop":
			_title.text = "🏪 Tạp hoá Cô Ba"
			for item_id in ["banh_mi", "ca_phe", "rod", "axe", "pickaxe"]:
				_buy_row(item_id)
		"cafe":
			_title.text = "🍚 Quán Cơm Hải Âu"
			for item_id in ["banh_mi", "ca_phe"]:
				_buy_row(item_id)
		"garage":
			_title.text = "🚗 Gara Chú Tư"
			for car_id in Game.CAR_CATALOG:
				_car_row(car_id)
		"sell_fish":
			_title.text = "🐟 Chợ Cá Bến Sóng — thu mua"
			_sell_rows(["fish_common", "fish_fine", "fish_rare"])
		"sell_wood":
			_title.text = "🪵 Xưởng Gỗ — thu mua"
			_sell_rows(["log"])
		"sell_ore":
			_title.text = "⛏ Trạm Thu Quặng"
			_sell_rows(["ore_copper", "ore_iron", "ore_gold"])


func _make_row(left_text: String, btn_text: String, enabled: bool, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = left_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 22)
	row.add_child(label)
	var btn := Button.new()
	btn.text = btn_text
	btn.disabled = not enabled
	btn.custom_minimum_size = Vector2(170, 0)
	if cb.is_valid():
		btn.pressed.connect(cb)
	row.add_child(btn)
	_rows.add_child(row)


func _buy_row(item_id: String) -> void:
	var item: Dictionary = Game.ITEMS[item_id]
	var price: int = item.buy
	var owned := Game.count_item(item_id)
	var is_tool: bool = item_id in ["rod", "axe", "pickaxe"]
	var left: String = "%s %s   (có: %d)" % [item.icon, item.name, owned]
	if is_tool and owned > 0:
		_make_row(left, "Đã có ✓", false, Callable())
		return
	var buy_cb := func() -> void:
		if Game.try_spend(price):
			Game.add_item(item_id)
			Audio.play_ui("cash")
			if is_tool:
				Events.toast.emit("Đã mua %s — ra tìm việc thôi!" % item.name)
	_make_row(left, "Mua — %s" % Game.format_money(price), Game.money >= price, buy_cb)


func _car_row(car_id: String) -> void:
	var car: Dictionary = Game.CAR_CATALOG[car_id]
	var owned: bool = car_id in Game.owned_cars
	var left: String = "🚗 %s  •  tối đa %d km/h" % [car.name, int(car.top_speed * 3.6)]
	if owned:
		_make_row(left, "Đã mua ✓", false, Callable())
		return
	var buy_cb := func() -> void:
		if Game.try_spend(car.price):
			Game.owned_cars.append(car_id)
			Audio.play_ui("cash")
			var main := get_tree().get_first_node_in_group("main")
			if main != null:
				main.spawn_owned_car(car_id, true)
			Events.toast.emit("🔑 Xe %s đang đợi trước gara!" % car.name)
			Game.save_game()
	_make_row(left, "Mua — %s" % Game.format_money(car.price), Game.money >= car.price, buy_cb)


func _sell_rows(item_ids: Array) -> void:
	var any := false
	for item_id in item_ids:
		var count := Game.count_item(item_id)
		if count <= 0:
			continue
		any = true
		var item: Dictionary = Game.ITEMS[item_id]
		var total: int = item.sell * count
		# Lambda extracted to a local: a trailing multi-line lambda at this
		# indent level is rejected by Godot's tokenizer.
		var sell_cb := func() -> void:
			if Game.remove_item(item_id, count):
				Game.add_money(total, true)
				Audio.play_ui("cash")
		_make_row("%s %s × %d" % [item.icon, item.name, count],
			"Bán hết — %s" % Game.format_money(total), true, sell_cb)
	if not any:
		var label := Label.new()
		label.text = "Bạn chưa có gì để bán ở đây."
		label.add_theme_font_size_override("font_size", 22)
		_rows.add_child(label)
