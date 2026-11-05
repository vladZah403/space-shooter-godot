class_name Pl
extends RefCounted
## Корабль игрока (game.player в JS-версии).

var x := 0.0
var y := 0.0
var w := 56.0
var r := 6.0
var pickR := 28.0
var lives := 0
var maxLives := 0
var shield := false
var inv := 2.0
var bombs := 0
var bombCd := 0.0
var tilt := 0.0
var vxs := 0.0
var alive := true
var weapons: Array = []
var weapon := "laser"
var wcd := {}
var mag := {}                 # wid → { n, t }
var side := 1.0
var wingCd := 0.2
var lockT := 0.0
var lockHot := 0.0
var bumpT := 0.0
var kbx := 0.0
var kby := 0.0
var lx := NAN
var ly := NAN
var vxm := 0.0
var vym := 0.0
