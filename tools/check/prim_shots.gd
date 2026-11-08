extends Node2D
## Примитивы Ctx (запуск с окном): слева — новые (круг картинкой, штрихи одной командой), справа — как в Godot напрямую.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/prim_shots.tscn -- --shot=ФАЙЛ.png
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): out = a.substr(7)
	RenderingServer.set_default_clear_color(Color(0.02, 0.03, 0.1))
	var ctx := Ctx.new(get_canvas_item())
	ctx.begin()
	var y := 20.0
	for r in [1.5, 3.0, 6.0, 12.0, 24.0, 48.0]:
		ctx.fill = Color(1, 0.3, 0.4, 0.9)
		ctx.fill_circle(60, y + r, r)
		RenderingServer.canvas_item_add_circle(ctx._item(), Vector2(260, y + r), r, Color(1, 0.3, 0.4, 0.9))
		y += r * 2 + 10
	ctx.stroke = Color(1, 0.8, 0.3, 0.9)
	for lw in [1.0, 2.0, 4.0]:
		ctx.line_width = lw
		ctx.dash = PackedFloat32Array([8, 6])
		ctx.begin_path(); ctx.move_to(20, y); ctx.line_to(180, y + 40); ctx.stroke_path()
		ctx.dash = PackedFloat32Array()
		ctx.begin_path(); ctx.move_to(220, y); ctx.line_to(380, y + 40); ctx.stroke_path()
		y += 60
	ctx.line_width = 2.0
	ctx.begin_path(); ctx.arc(100, y + 60, 50, 0, TAU); ctx.stroke_path()
	ctx.fill = Color(0.2, 0.6, 1, 0.5)
	ctx.begin_path(); ctx.round_rect(200, y + 10, 150, 60, 16); ctx.fill_path(); ctx.stroke_path()
	ctx.begin_path(); ctx.arc(300, y + 130, 40, -PI / 2, PI * 0.8); ctx.stroke_path()
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if out != "": get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
