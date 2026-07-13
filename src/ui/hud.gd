class_name Hud
extends CanvasLayer
## In-game HUD: floating joystick, contextual action buttons, status labels,
## objective arrow, toasts, dialogue, fishing bar and the modal panels.

var joystick_vector := Vector2.ZERO
var player: PlayerCharacter = null

var _joystick: VirtualJoystick
var _root: Control
var _foot_controls: Control
var _drive_controls: Control
var _interact_btn: TouchButton
var _jump_btn: TouchButton
var _sprint_btn: TouchButton
var _punch_btn: TouchButton
var _prompt_label: Label
var _money_label: Label
var _clock_label: Label
var _wanted_label: Label
var _toast_box: VBoxContainer
var _objective_panel: PanelContainer
var _objective_label: Label
var _arrow_layer: Control
var _fade_rect: ColorRect
var _dialogue_panel: PanelContainer
var _dialogue_name: Label
var _dialogue_text: Label
var _dialogue_action: Button
var _dialogue_cb: Callable = Callable()
var _fishing_ui: Control
var _fishing_label: Label
var _pause_btn: TouchButton

var _objective_pos := Vector3.ZERO
var _objective_active := false
var _sprint_idle_time := 0.0
var _blocked_count := 0

var shop_panel: ShopPanel
var menus: Menus
var _minimap: Minimap


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _build_theme()
	add_child(_root)

	_build_arrow_layer()
	_build_joystick()
	_build_buttons()
	_build_status()
	_build_dialogue()
	_build_fishing()

	shop_panel = ShopPanel.new()
	_root.add_child(shop_panel)
	menus = Menus.new()
	_root.add_child(menus)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade_rect)

	Events.money_changed.connect(func(m: int) -> void: _money_label.text = Game.format_money(m))
	Events.wanted_changed.connect(_on_wanted)
	Events.toast.connect(show_toast)
	Events.objective_changed.connect(_on_objective)
	Events.dialogue_opened.connect(_on_dialogue)
	Events.player_entered_vehicle.connect(func(_v: Node3D) -> void: _set_drive_mode(true))
	Events.player_exited_vehicle.connect(func(_v: Node3D) -> void: _set_drive_mode(false))
	Events.shop_requested.connect(_on_shop_requested)
	Events.sleep_requested.connect(_on_sleep)
	Events.upgrade_requested.connect(func() -> void: menus.open_upgrade())
	Events.player_busted.connect(_on_busted)
	_money_label.text = Game.format_money(Game.money)


static func _build_theme() -> Theme:
	var theme := Theme.new()
	# Route emoji through the OS emoji font (Godot's bundled font has none).
	var emoji_font := SystemFont.new()
	emoji_font.font_names = PackedStringArray(["Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji"])
	var base_font := FontVariation.new()
	base_font.base_font = ThemeDB.fallback_font
	base_font.fallbacks = [emoji_font]
	theme.default_font = base_font
	theme.default_font_size = 24
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.13, 0.86)
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(14)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.16, 0.22, 0.3, 0.95)
	btn.set_corner_radius_all(10)
	btn.set_content_margin_all(10)
	theme.set_stylebox("normal", "Button", btn)
	var btn_hover := btn.duplicate()
	btn_hover.bg_color = Color(0.22, 0.3, 0.4, 0.95)
	theme.set_stylebox("hover", "Button", btn_hover)
	var btn_press := btn.duplicate()
	btn_press.bg_color = Color(0.3, 0.42, 0.55, 0.95)
	theme.set_stylebox("pressed", "Button", btn_press)
	theme.set_font_size("font_size", "Button", 24)
	return theme


# --- construction ------------------------------------------------------------

func _build_joystick() -> void:
	_joystick = VirtualJoystick.new()
	_root.add_child(_joystick)
	_joystick.anchor_left = 0.0
	_joystick.anchor_right = 0.44
	_joystick.anchor_top = 0.14
	_joystick.anchor_bottom = 1.0
	_joystick.offset_left = 0
	_joystick.offset_right = 0
	_joystick.offset_top = 0
	_joystick.offset_bottom = 0
	_joystick.vector_changed.connect(func(v: Vector2) -> void: joystick_vector = v)


func _make_btn(parent: Control, label: String, radius: float, action: String, offset: Vector2) -> TouchButton:
	var btn := TouchButton.new(label, radius, action)
	parent.add_child(btn)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.position = Vector2.ZERO
	btn.set_meta("corner_offset", offset)
	return btn


func _build_buttons() -> void:
	_foot_controls = Control.new()
	_foot_controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	_foot_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_foot_controls)
	_interact_btn = _make_btn(_foot_controls, "✋", 52, "", Vector2(190, 190))
	_interact_btn.tapped.connect(_on_interact_tap)
	_jump_btn = _make_btn(_foot_controls, "⬆", 44, "jump", Vector2(330, 150))
	_sprint_btn = _make_btn(_foot_controls, "🏃", 38, "", Vector2(200, 330))
	_sprint_btn.tapped.connect(_toggle_sprint)
	_punch_btn = _make_btn(_foot_controls, "👊", 38, "", Vector2(330, 290))
	_punch_btn.tapped.connect(func() -> void:
		if player != null:
			player.try_punch()
	)

	_drive_controls = Control.new()
	_drive_controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drive_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drive_controls.visible = false
	_root.add_child(_drive_controls)
	_make_btn(_drive_controls, "▲", 54, "move_forward", Vector2(160, 200))
	_make_btn(_drive_controls, "▼", 46, "move_back", Vector2(300, 150))
	_make_btn(_drive_controls, "🅿", 40, "jump", Vector2(190, 350))
	_make_btn(_drive_controls, "📢", 34, "horn", Vector2(320, 300))

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_root.add_child(_prompt_label)

	get_viewport().size_changed.connect(_layout_buttons)
	_layout_buttons()


func _layout_buttons() -> void:
	var view_size: Vector2 = _root.get_viewport_rect().size
	for group in [_foot_controls, _drive_controls]:
		for child in group.get_children():
			if child is TouchButton:
				var off: Vector2 = child.get_meta("corner_offset")
				child.position = view_size - off
	_prompt_label.position = view_size - Vector2(420, 235)
	_prompt_label.size = Vector2(360, 30)
	if _wanted_label != null:
		_wanted_label.position = Vector2(view_size.x - 240, 16)
	if _pause_btn != null:
		_pause_btn.position = Vector2(view_size.x - 86, 12)
	if _toast_box != null:
		_toast_box.position = Vector2(view_size.x * 0.5 - 220, 64)


func _build_status() -> void:
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 30)
	_money_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_money_label.add_theme_constant_override("outline_size", 8)
	_money_label.position = Vector2(20, 14)
	_root.add_child(_money_label)

	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 22)
	_clock_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_clock_label.add_theme_constant_override("outline_size", 6)
	_clock_label.position = Vector2(20, 52)
	_root.add_child(_clock_label)

	_wanted_label = Label.new()
	_wanted_label.add_theme_font_size_override("font_size", 26)
	_wanted_label.size = Vector2(150, 32)
	_wanted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_wanted_label)

	_pause_btn = TouchButton.new("II", 30, "")
	_root.add_child(_pause_btn)
	_pause_btn.tapped.connect(func() -> void: menus.open_pause())

	_objective_panel = PanelContainer.new()
	_objective_panel.visible = false
	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 22)
	_objective_panel.add_child(_objective_label)
	_root.add_child(_objective_panel)

	_toast_box = VBoxContainer.new()
	_toast_box.size = Vector2(440, 200)
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_child(_toast_box)

	_minimap = Minimap.new()
	_minimap.position = Vector2(20, 92)
	_root.add_child(_minimap)
	if is_instance_valid(Game.world) and Game.world.has_method("make_map_texture"):
		_minimap.setup(Game.world.make_map_texture())
	_layout_buttons()


func _build_arrow_layer() -> void:
	_arrow_layer = Control.new()
	_arrow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_layer.draw.connect(_draw_objective_arrow)
	_root.add_child(_arrow_layer)


func _build_dialogue() -> void:
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.visible = false
	var box := VBoxContainer.new()
	_dialogue_name = Label.new()
	_dialogue_name.add_theme_font_size_override("font_size", 22)
	_dialogue_name.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	_dialogue_text = Label.new()
	_dialogue_text.add_theme_font_size_override("font_size", 24)
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text.custom_minimum_size = Vector2(520, 0)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_dialogue_action = Button.new()
	_dialogue_action.visible = false
	_dialogue_action.pressed.connect(func() -> void:
		if _dialogue_cb.is_valid():
			_dialogue_cb.call()
		_close_dialogue()
	)
	var ok := Button.new()
	ok.text = "Tạm biệt"
	ok.pressed.connect(_close_dialogue)
	buttons.add_child(_dialogue_action)
	buttons.add_child(ok)
	box.add_child(_dialogue_name)
	box.add_child(_dialogue_text)
	box.add_child(buttons)
	_dialogue_panel.add_child(box)
	_root.add_child(_dialogue_panel)


func _build_fishing() -> void:
	_fishing_ui = Control.new()
	_fishing_ui.visible = false
	_fishing_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fishing_ui.draw.connect(_draw_fishing_bar)
	_fishing_label = Label.new()
	_fishing_label.add_theme_font_size_override("font_size", 26)
	_fishing_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_fishing_label.add_theme_constant_override("outline_size", 8)
	_fishing_label.position = Vector2(-120, -96)
	_fishing_label.size = Vector2(240, 34)
	_fishing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fishing_ui.add_child(_fishing_label)
	_root.add_child(_fishing_ui)


# --- runtime ----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.move_input = Vector2.ZERO if _blocked_count > 0 else joystick_vector
	_clock_label.text = "🕐 %s  •  Ngày %d%s" % [DayNight.clock_text(), DayNight.day,
		"  🌧" if DayNight.rain_amount > 0.3 else ""]
	_minimap.visible = _blocked_count == 0
	# Sprint auto-off when idle.
	if joystick_vector.length() < 0.05:
		_sprint_idle_time += _delta
		if _sprint_idle_time > 0.7 and player.sprint_held:
			_set_sprint(false)
	else:
		_sprint_idle_time = 0.0
	# Contextual prompt.
	var prompt := ""
	if player.state == PlayerCharacter.State.DRIVING:
		prompt = "Ra xe"
		_interact_btn.set_label("🚪")
	elif player.state == PlayerCharacter.State.FISHING:
		_interact_btn.set_label("🎣")
	else:
		var target := player.current_interactable()
		if target != null:
			prompt = target.get_prompt()
		_interact_btn.set_label("✋" if prompt == "" else "❗")
	_prompt_label.text = prompt
	# Keyboard fallbacks (inactive while any modal/menu is up).
	if _blocked_count == 0 and not menus.any_open():
		if Input.is_action_just_pressed("interact"):
			_on_interact_tap()
		if Input.is_action_just_pressed("attack") and player.state == PlayerCharacter.State.GROUND:
			player.try_punch()
	if Input.is_action_just_pressed("pause"):
		if shop_panel.visible:
			shop_panel.close_panel()
		elif _dialogue_panel.visible:
			_close_dialogue()
		elif not menus.any_open():
			menus.open_pause()
	_update_fishing()
	_arrow_layer.queue_redraw()


func _on_interact_tap() -> void:
	if _dialogue_panel.visible:
		_close_dialogue()
		return
	if player != null:
		player.try_interact()


func _toggle_sprint() -> void:
	_set_sprint(not player.sprint_held if player != null else false)


func _set_sprint(on: bool) -> void:
	if player != null:
		player.sprint_held = on
	_sprint_btn.base_color = Color(0.9, 0.6, 0.2, 0.7) if on else Color(0.1, 0.12, 0.16, 0.55)
	_sprint_btn.queue_redraw()


func _set_drive_mode(driving: bool) -> void:
	_drive_controls.visible = driving
	_jump_btn.visible = not driving
	_sprint_btn.visible = not driving
	_punch_btn.visible = not driving
	if driving:
		_set_sprint(false)


# --- blocking / modal helpers --------------------------------------------------------

func push_block() -> void:
	_blocked_count += 1
	_joystick.set_blocked(true)
	Game.ui_blocked = true


func pop_block() -> void:
	_blocked_count = maxi(_blocked_count - 1, 0)
	if _blocked_count == 0:
		_joystick.set_blocked(false)
		Game.ui_blocked = false


func fade(to_black: bool, duration: float = 0.5) -> Tween:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0 if to_black else 0.0, duration)
	return tween


# --- events --------------------------------------------------------------------------

func show_toast(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 7)
	_toast_box.add_child(label)
	_toast_box.move_child(label, 0)
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(_toast_box.get_child_count() - 1).free()
	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _on_wanted(level: int) -> void:
	_wanted_label.text = "" if level <= 0 else "⭐".repeat(level)


func _on_objective(text: String, pos: Vector3, active: bool) -> void:
	_objective_active = active
	_objective_pos = pos
	if _minimap != null:
		_minimap.objective_active = active
		_minimap.objective_pos = pos
	_objective_label.text = text
	_objective_panel.visible = active
	if active:
		_objective_panel.reset_size()
		var view := _root.get_viewport_rect().size
		_objective_panel.position = Vector2((view.x - _objective_panel.size.x) * 0.5, 12)


func _on_dialogue(speaker: String, text: String) -> void:
	_dialogue_name.text = speaker
	_dialogue_text.text = text
	_dialogue_action.visible = false
	_dialogue_cb = Callable()
	_dialogue_panel.visible = true
	_dialogue_panel.reset_size()
	var view := _root.get_viewport_rect().size
	_dialogue_panel.position = Vector2((view.x - _dialogue_panel.size.x) * 0.5, view.y - _dialogue_panel.size.y - 30)


func show_dialogue_with_action(speaker: String, text: String, action_label: String, cb: Callable) -> void:
	_on_dialogue(speaker, text)
	_dialogue_action.text = action_label
	_dialogue_action.visible = true
	_dialogue_cb = cb


func _close_dialogue() -> void:
	_dialogue_panel.visible = false
	Events.dialogue_closed.emit()


func _on_shop_requested(kind: String) -> void:
	match kind:
		"delivery":
			var job := get_tree().get_first_node_in_group("delivery_job")
			if job != null:
				job.start()
		"police":
			var manager := get_tree().get_first_node_in_group("police_manager")
			var wanted: int = manager.wanted if manager != null else 0
			if wanted > 0:
				var fine: int = PoliceManager.FINE_PER_STAR * wanted
				show_dialogue_with_action("Trực ban", "Bạn đang bị truy nã %d sao. Nộp phạt để xoá hồ sơ?" % wanted,
					"Nộp %s" % Game.format_money(fine), func() -> void: manager.pay_off())
			else:
				_on_dialogue("Trực ban", "Hồ sơ của bạn trong sạch. Sống tốt nghen!")
		"hospital":
			_on_dialogue("Y tá Lan", "Nhìn bạn khoẻ re à! Nhớ ăn uống điều độ, khỏi khám.")
		_:
			shop_panel.open(kind)


func _on_sleep() -> void:
	if DayNight.time_hours > 6.0 and DayNight.time_hours < 19.0:
		show_toast("Trời còn sáng, chưa buồn ngủ. (Ngủ được sau 19:00)")
		return
	push_block()
	var tween := fade(true, 0.6)
	tween.tween_callback(func() -> void:
		DayNight.sleep_to_morning()
		Game.save_game()
		if player != null:
			player.teleport_to(Game.world.marker_global("player_home", "sleep") + Vector3(0.8, 0.2, 0))
	)
	tween.tween_interval(0.4)
	tween.tween_callback(func() -> void:
		fade(false, 0.7)
		pop_block()
		show_toast("☀ Một ngày mới bắt đầu! (Đã lưu game)")
	)


func _on_busted(_fine: int) -> void:
	push_block()
	var tween := fade(true, 0.5)
	tween.tween_callback(func() -> void:
		if player != null:
			var spot: Vector3 = Game.world.door_global("police") + Vector3(0, 0.1, 2.0)
			player.teleport_to(spot)
	)
	tween.tween_interval(0.5)
	tween.tween_callback(func() -> void:
		fade(false, 0.6)
		pop_block()
	)


# --- custom drawing -----------------------------------------------------------------

func _draw_objective_arrow() -> void:
	if not _objective_active or player == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var view_size := _arrow_layer.size
	var behind := camera.is_position_behind(_objective_pos)
	var screen_pos := camera.unproject_position(_objective_pos)
	var dist := player.global_position.distance_to(_objective_pos)
	var margin := 46.0
	var inside: bool = not behind \
		and screen_pos.x > margin and screen_pos.x < view_size.x - margin \
		and screen_pos.y > margin and screen_pos.y < view_size.y - margin
	var font := _arrow_layer.get_theme_default_font()
	if inside:
		# Marker above target.
		var tri := PackedVector2Array([
			screen_pos + Vector2(0, -18), screen_pos + Vector2(-11, -34), screen_pos + Vector2(11, -34),
		])
		_arrow_layer.draw_colored_polygon(tri, Color(1.0, 0.85, 0.2, 0.95))
		_arrow_layer.draw_string(font, screen_pos + Vector2(-40, -42), "%dm" % int(dist),
			HORIZONTAL_ALIGNMENT_CENTER, 80, 18, Color(1, 1, 1, 0.95))
	else:
		var center := view_size * 0.5
		var dir := (screen_pos - center)
		if behind:
			dir = -dir
		if dir.length_squared() < 1.0:
			dir = Vector2(0, -1)
		dir = dir.normalized()
		var edge := center + dir * (minf(view_size.x, view_size.y) * 0.5 - margin)
		edge.x = clampf(edge.x, margin, view_size.x - margin)
		edge.y = clampf(edge.y, margin, view_size.y - margin)
		var perp := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([
			edge + dir * 20.0, edge - dir * 6.0 + perp * 13.0, edge - dir * 6.0 - perp * 13.0,
		])
		_arrow_layer.draw_colored_polygon(tri, Color(1.0, 0.85, 0.2, 0.95))
		_arrow_layer.draw_string(font, edge - dir * 30.0 + Vector2(-40, 6), "%dm" % int(dist),
			HORIZONTAL_ALIGNMENT_CENTER, 80, 17, Color(1, 1, 1, 0.9))


func _update_fishing() -> void:
	var ctl := get_tree().get_first_node_in_group("fishing")
	if ctl == null or ctl.phase == FishingController.Phase.OFF:
		_fishing_ui.visible = false
		return
	_fishing_ui.visible = true
	var view := _root.get_viewport_rect().size
	_fishing_ui.position = Vector2(view.x * 0.5, view.y - 40)
	match ctl.phase:
		FishingController.Phase.WAITING:
			_fishing_label.text = "Chờ cá cắn câu…"
		FishingController.Phase.BITE:
			_fishing_label.text = "❗ KÉO NGAY ❗"
		FishingController.Phase.REELING:
			_fishing_label.text = "Bấm khi kim vào giữa!"
	_fishing_ui.queue_redraw()


func _draw_fishing_bar() -> void:
	var ctl := get_tree().get_first_node_in_group("fishing")
	if ctl == null or ctl.phase != FishingController.Phase.REELING:
		return
	var bar_w := 460.0
	var bar_h := 26.0
	var origin := Vector2(-bar_w * 0.5, -60)
	_fishing_ui.draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.55))
	# Green center zone (matching the 0.35 accuracy threshold ≈ 32% of bar).
	_fishing_ui.draw_rect(Rect2(origin + Vector2(bar_w * 0.34, 0), Vector2(bar_w * 0.32, bar_h)), Color(0.25, 0.7, 0.3, 0.8))
	_fishing_ui.draw_rect(Rect2(origin + Vector2(bar_w * 0.46, 0), Vector2(bar_w * 0.08, bar_h)), Color(0.95, 0.85, 0.3, 0.9))
	var x: float = origin.x + bar_w * ctl.cursor
	var tri := PackedVector2Array([
		Vector2(x, origin.y - 4), Vector2(x - 9, origin.y - 20), Vector2(x + 9, origin.y - 20),
	])
	_fishing_ui.draw_colored_polygon(tri, Color(1, 1, 1, 0.95))
