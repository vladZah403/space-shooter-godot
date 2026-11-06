#!/bin/bash
# Проверка перенесённого кода, пока игра собрана не полностью: копия проекта с заглушками недостающих
# модулей (mkcheck.py) + дымовой тест. Копия кладётся ВНЕ проекта, иначе Godot импортирует её как часть игры.
# Использование: GODOT=путь/Godot_v4.6.3-stable_win64_console.exe tools/check/run.sh smoke_bosses.gd [папка_копии]
set -e
[ -n "$GODOT" ] || { echo "Укажите GODOT=путь к Godot_*_console.exe"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
PROJ=$(cd "$HERE/../.." && pwd)
OUT=${2:-"${TEMP:-/tmp}/ss-godot-check"}
python "$HERE/mkcheck.py" "$PROJ" "$OUT"
mkdir -p "$OUT/scenes" && cp "$HERE/$1" "$OUT/smoke.gd" && cp "$HERE/fixture.gd" "$OUT/fixture.gd"
printf '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://smoke.gd" id="1"]\n\n[node name="Main" type="Node2D"]\nscript = ExtResource("1")\n' > "$OUT/scenes/main.tscn"
cd "$OUT"
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
timeout 300 "$GODOT" --headless --path . 2>&1 | grep -vE "^\s*$|Godot Engine|^OpenGL|^Vulkan" > "$OUT/smoke.log" || true
echo "== ошибки:"; grep -E "ERROR" -A1 "$OUT/smoke.log" | grep -E "ERROR|at:" | paste - - | sort | uniq -c | sort -rn | head -20
echo "== вывод:"; grep -vE "ERROR|^\s+at:|GDScript backtrace|^\s+\[[0-9]|^--" "$OUT/smoke.log" | head -60
