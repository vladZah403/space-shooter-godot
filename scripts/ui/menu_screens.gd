extends Control
## Экраны главного меню (перенос #scr-hangar, #scr-arsenal, #scr-skills, #scr-missions, #scr-relics,
## #scr-achievements, #scr-codex, #scr-settings из JS): шапка с «назад» и кошельком, содержимое по разделу.

var cur := ""
var title: Label
var coins: Label
var body: VBoxContainer
var scroll: ScrollContainer

const TITLES := {"hangar": "АНГАР", "arsenal": "АРСЕНАЛ", "skills": "НАВЫКИ", "missions": "ЗАДАНИЯ", "relics": "РЕЛИКВИИ",
	"achievements": "НАГРАДЫ", "codex": "СПРАВОЧНИК", "settings": "НАСТРОЙКИ"}


func _ready() -> void:
	Kit.full(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bgc := ColorRect.new(); bgc.color = Color(Kit.BG, 0.94); Kit.full(bgc); add_child(bgc)
	var m := Kit.margin(14, 12, 14, 12)
	Kit.full(m)
	add_child(m)
	var v := Kit.vbox(10)
	m.add_child(v)
	var head := Kit.hbox(8)
	head.add_child(Kit.button("‹", func(): back(), "", "sm"))
	title = Kit.label("", 20, Kit.TEXT, 900)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Kit.tex_icon(G.proc("coin"), 20))
	coins = Kit.label("", 16, Kit.GOLD, 900)
	head.add_child(coins)
	v.add_child(head)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = Kit.vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	v.add_child(scroll)


func open(id: String) -> void:
	cur = id
	title.text = TITLES.get(id, id.to_upper())
	visible = true
	refresh_wallet()
	render()


func close() -> void:
	visible = false
	cur = ""


func back() -> void:
	A.play("back")
	close()
	if Ui.menu: Ui.menu.refresh()


func refresh_wallet() -> void:
	coins.text = U.fmt(M.s.coins)


func render() -> void:
	Kit.clear(body)
	if has_method("_render_" + cur): call("_render_" + cur)
	else: body.add_child(Kit.para("Раздел переносится в Godot-версию.", 15, Kit.MUTED))
