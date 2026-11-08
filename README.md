# Space Shooter — Godot-версия

Переписываем браузерную игру `../space-shooter-game` (JS, Canvas) на Godot 4.6, чтобы выпустить
полноценную игру для ПК и телефонов, а веб-версию собирать из того же проекта.

Сейчас это **прототип**: корабль, три вида врагов, волны, босс Страж с тремя фазами, очки, жизни,
пауза и экран итогов. Спрайты взяты из атласов JS-версии (`assets/sprites*.png`).

## Как открыть

1. Запустить Godot 4.6.3 → **Import** → выбрать `project.godot` в этой папке.
2. **F5** — запуск. Управление: вести пальцем или мышью (зажать и тянуть), стрелки или WASD;
   стрельба автоматическая. Пауза — кнопка «II», Esc или P.

## Устройство

| Файл | Что делает |
|---|---|
| `scenes/main.tscn`, `scripts/main.gd` | волны, босс каждые 5 волн, очки, жизни, пауза, итоги |
| `scripts/player.gd` | корабль: ведение пальцем/мышью/клавишами, автострельба, неуязвимость после попадания |
| `scripts/enemy.gd` | враги: разведчик (пикирует), дрон (строй), стрелок (веер) |
| `scripts/boss.gd` | Страж: три фазы, перестройка между ними, урон не перескакивает фазу |
| `scripts/bullet.gd` | снаряды корабля и врагов |
| `scripts/hud.gd` | интерфейс: жизни, волна, очки, полоса босса, баннеры, меню |
| `scripts/atlas.gd`, `scripts/atlas_data.gd` | кадры спрайтов по имени: `Atlas.sprite("ship1", 56)` |
| `scripts/starfield.gd`, `scripts/fx_sprite.gd` | фон со звёздами, взрывы и искры |

Слои столкновений: 1 — корабль, 2 — враги, 4 — снаряды корабля, 8 — вражеские пули.

`atlas_data.gd` сгенерирован из `../space-shooter-game/js/atlas.js`: после пересборки атласов
JS-версии его нужно сгенерировать заново и скопировать `assets/sprites*.png`.

## Проверка без рук

```bash
# бот-тестировщик: бессмертный корабль играет сам, в консоль пишутся волны и бои с боссом
Godot_v4.6.3-stable_win64_console.exe --headless --path . --fixed-fps 60 --quit-after 20000 -- --autoplay
# снимки экрана в папку (на 3, 12, 30, 55, 62 и 75 секунде)
Godot_v4.6.3-stable_win64_console.exe --path . --fixed-fps 60 --quit-after 4800 -- --autoplay --shots=C:/папка
```

Перенос полной игры (`scripts/game/`) ещё не подключён к сцене. Пока он не собран целиком, его
проверяет `tools/check/run.sh`: копия проекта вне папки с заглушками недостающих модулей + дымовой тест
(`smoke_bosses.gd` — все 13 боссов проходят три фазы и погибают; `smoke_foes.gd` — враги 3.1; `smoke_sectors.gd` — механики секторов; `smoke_skills.gd` — навыки и дроны; `smoke_store.gd` — сохранение и прогрессия; `smoke_events.gd` — события волн; `smoke_scenes.gd` — сцены узлов карты; `smoke_audio.gd` — звук; `smoke_run.gd` — целый забег ботом; общая подготовка забега — `fixture.gd`):

```bash
GODOT=путь/Godot_v4.6.3-stable_win64_console.exe tools/check/run.sh smoke_bosses.gd
```

## Звук

Эффекты и музыка синтезированы кодом JS-версии (`../space-shooter-game/js/audio.js`) и записаны в WAV:
`node tools/render_audio.mjs` (нужен Chrome или Edge) → `assets/audio/sfx/*.wav`, `assets/audio/music/<стиль>_<0|1|2>.wav`
(петли по 4 такта: меню, бой, босс) и `assets/audio/audio.json`. После правок звука в JS — запустить заново.

## Сборки

Пресеты `Windows` и `Web` (однопоточный — работает и на iOS) лежат в `export_presets.cfg`.
Для сборки нужны шаблоны экспорта: в редакторе **Editor → Manage Export Templates → Download**.
Android — после установки Android SDK и JDK 17 (Editor Settings → Export → Android).

## Язык (русский / английский)

Исходный язык — русский; перевод лежит в `data/i18n/en.json` (ключ — русская строка, значение — английская).
`scripts/core/lang.gd` (`Lang`): `Lang.t("ВОЛНА %d") % n` в коде, данные `D` переводятся при загрузке,
`Ctx.fill_text` и надписи Godot переводят сами. Язык по умолчанию — по языку системы (ru/uk/be/kk → русский),
переключатель — в Настройках (игра перезапускается). Проверка на английском: `-- --lang=en`.

После правок текстов:

```bash
python tools/i18n.py wrap      # обернуть новые русские строки в коде в Lang.t(...)
python tools/i18n.py extract   # обновить список ключей в en.json
python tools/i18n.py missing   # что ещё не переведено → перевести, вписать в en.json
python tools/i18n.py check     # %d/%s/{n} в переводе те же, что в оригинале
```
