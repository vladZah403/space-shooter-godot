class_name Eb
extends RefCounted
## Вражеский снаряд (game.ebullets в JS-версии).

var x := 0.0
var y := 0.0
var px := 0.0
var py := 0.0
var vx := 0.0
var vy := 0.0
var type := "orb"
var sprite := ""
var cv: Texture2D = null
var w := 15.0
var r := 5.0
var color := "#ff6b3d"
var rotate := false
var life := 9.0
var age := 0.0
var dead := false
var accel := 0.0
var homing := 0.0
var fuse := 0.0
var maxSpd := 0.0
var redirT := 0.0
var redirSpd := 0.0
var redone := false
var burst = null              # { n, spd, type }
var bounce := 0
var ebc = null
var sine = null               # { amp, f, ph }
var tpT := 0.0
var escort := false
