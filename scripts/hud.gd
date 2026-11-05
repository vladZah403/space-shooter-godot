class_name Hud
extends CanvasLayer
## Интерфейс поверх игры: жизни, волна, очки, полоса босса, баннеры, пауза,
## стартовый экран и экран итогов. Работает и на паузе.

signal start_pressed
signal pause_pressed

const GOLD := Color(1.0, 0.82, 0.24)
const CYAN := Color(0.24, 0.88, 1.0)

var _lives_box: HBoxContainer
var _wave: Label
var _score: Label
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _banner: Label
var _banner_sub: Label
var _banner_tw: Tween
var _overlay: ColorRect
var _title: Label
var _subtitle: Label
var _button: Button
var _pause_btn: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# верхняя строка: пауза, жизни | волна | очки
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -12
	top.offset_top = 10
	top.offset_bottom = 54
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.custom_minimum_size = Vector2(44, 44)
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.add_theme_font_size_override("font_size", 18)
	_pause_btn.pressed.connect(func(): pause_pressed.emit())
	top.add_child(_pause_btn)
	_lives_box = HBoxContainer.new()
	_lives_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives_box.add_theme_constant_override("separation", 2)
	top.add_child(_lives_box)
	top.add_child(_spacer())
	_wave = _label("", 17, CYAN)
	top.add_child(_wave)
	top.add_child(_spacer())
	_score = _label("0", 20, Color.WHITE)
	top.add_child(_score)

	# полоса босса
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_box.offset_left = 24
	_boss_box.offset_right = -24
	_boss_box.offset_top = 62
	_boss_box.offset_bottom = 100
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	root.add_child(_boss_box)
	_boss_name = _label("", 14, Color(1.0, 0.45, 0.5))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(0, 10)
	_boss_bar.max_value = 1.0
	_boss_bar.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.25)))
	_boss_bar.add_theme_stylebox_override("fill", _box(Color(1.0, 0.24, 0.35), Color(1.0, 0.6, 0.65)))
	_boss_box.add_child(_boss_bar)

	# баннер по центру
	_banner = _label("", 34, Color.WHITE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.36
	_banner.anchor_bottom = 0.36
	root.add_child(_banner)
	_banner_sub = _label("", 15, Color(0.75, 0.82, 1.0))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_sub.anchor_left = 0.0
	_banner_sub.anchor_right = 1.0
	_banner_sub.anchor_top = 0.36
	_banner_sub.anchor_bottom = 0.36
	_banner_sub.offset_top = 52
	_banner_sub.offset_left = 24
	_banner_sub.offset_right = -24
	root.add_child(_banner_sub)
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0

	# затемнение со стартом / паузой / итогами
	_overlay = ColorRect.new()
	_overlay.color = Color(0.01, 0.02, 0.06, 0.72)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(box)
	_title = _label("", 36, CYAN)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_subtitle = _label("", 17, Color(0.8, 0.86, 1.0))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_subtitle)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(center)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(230, 58)
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_size_override("font_size", 22)
	_button.add_theme_stylebox_override("normal", _box(Color(0.1, 0.55, 0.85), CYAN, 14))
	_button.add_theme_stylebox_override("hover", _box(Color(0.15, 0.62, 0.95), CYAN, 14))
	_button.add_theme_stylebox_override("pressed", _box(Color(0.07, 0.42, 0.7), CYAN, 14))
	_button.pressed.connect(func(): start_pressed.emit())
	center.add_child(_button)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _box(bg: Color, border: Color, radius := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	return sb


func set_lives(n: int) -> void:
	for c in _lives_box.get_children():
		c.queue_free()
	for i in n:
		var r := TextureRect.new()
		r.texture = Atlas.tex("ship1")
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(20, 24)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lives_box.add_child(r)


func set_score(n: int) -> void:
	_score.text = str(n)


func set_wave(n: int) -> void:
	_wave.text = "ВОЛНА %d" % n


func show_boss(boss_name: String) -> void:
	_boss_name.text = boss_name
	_boss_bar.value = 1.0
	_boss_box.visible = true


func set_boss(ratio: float) -> void:
	_boss_bar.value = ratio


func hide_boss() -> void:
	_boss_box.visible = false


func banner(text: String, sub: String, color := Color.WHITE) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	if _banner_tw:
		_banner_tw.kill()
	_banner_tw = create_tween()
	_banner_tw.tween_property(_banner, "modulate:a", 1.0, 0.2)
	_banner_tw.parallel().tween_property(_banner_sub, "modulate:a", 1.0, 0.2)
	_banner_tw.tween_interval(1.4)
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.4)
	_banner_tw.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.4)


func show_menu() -> void:
	_show_overlay("SPACE SHOOTER", "Godot-версия · прототип\n\nВедите пальцем или мышью,\nстрельба автоматическая", "ИГРАТЬ")


func show_pause() -> void:
	_show_overlay("ПАУЗА", "", "ПРОДОЛЖИТЬ")


func show_game_over(score: int, wave: int) -> void:
	_show_overlay("ИГРА ОКОНЧЕНА", "Очки: %d\nВолна: %d" % [score, wave], "ЕЩЁ РАЗ")


func _show_overlay(title: String, sub: String, button: String) -> void:
	_title.text = title
	_subtitle.text = sub
	_subtitle.visible = sub != ""
	_button.text = button
	_overlay.visible = true
	_pause_btn.visible = false


func hide_overlay() -> void:
	_overlay.visible = false
	_pause_btn.visible = true
