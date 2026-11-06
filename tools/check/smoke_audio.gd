extends Node2D
## Дымовой тест звука (audio.gd): все эффекты загружены и играются, ограничение частоты работает,
## музыка каждого стиля запускается тремя слоями в такт, интенсивность и «приглушение» плавно меняются.

func _ready() -> void:
	M.s = M.defaults()
	print("эффектов загружено: %d из %d" % [A.sfx.size(), A.meta.sfx.size()])
	var played := 0
	for name in A.sfx:
		A.play(name)
		for p in A._pool:
			if p.playing and p.stream == A.sfx[name]: played += 1; break
	print("заиграли: %d" % played)
	# частые звуки ограничены: второй лазер сразу после первого не играет
	var before := 0
	for p in A._pool: if p.playing: before += 1
	A.play("laser"); A.play("laser")
	var after := 0
	for p in A._pool: if p.playing: after += 1
	print("голосов занято: %d (лимит %d), лазер дважды подряд добавил: %d" % [after, A.VOICES, after - before])
	for id in A.STYLE_IDS:
		A.music_play(id, 1)
		for i in 60: A._process(1.0 / 60)
		var vols: Array = A._layers.map(func(p): return "%.0f" % p.volume_db)
		var looped: Array = A._layers.map(func(p): return p.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD if p.stream is AudioStreamWAV else false)
		A.setIntensity(2)
		for i in 60: A._process(1.0 / 60)
		var vols2: Array = A._layers.map(func(p): return "%.0f" % p.volume_db)
		print("%-10s играют %s  петля %s  громкость слоёв бой %s → босс %s  длина %.2f с" % [id, A._layers.map(func(p): return p.playing), looped, vols, vols2, A.meta.music[id + "_0"].dur])
	A.muffle(true)
	for i in 60: A._process(1.0 / 60)
	print("приглушение: срез %.0f Гц" % A._lowpass.cutoff_hz)
	A.music_stop(true)
	for i in 60: A._process(1.0 / 60)
	print("после остановки стиль '%s', играет %s" % [A.style, A._layers.any(func(p): return p.playing)])
	print("SMOKE DONE")
	get_tree().quit()
