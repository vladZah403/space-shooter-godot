class_name Bl
extends RefCounted
## Снаряд игрока (game.bullets в JS-версии).

var x := 0.0
var y := 0.0
var px := 0.0
var py := 0.0
var vx := 0.0
var vy := 0.0
var dmg := 0.0
var r := 4.0
var kind := ""
var sprite := ""
var cv: Texture2D = null
var w := 10.0
var pierce := 0
var hit: Array = []
var life := 2.4
var life0 := 2.4
var age := 0.0
var w1 := 0.0
var ch := 0.0
var homing := 0.0
var aoe := 0.0
var aoeR := 0.0
var acc := 0.0
var maxSpd := 0.0
var bounced := false
var fade := 0.0
var tick := 0.0
var tickT := 0.0
var pull := 0.0
var burst := 0.0
var burstR := 0.0
var rot := 0.0
var wid := ""
var dead := false
var target: En = null
var prism := false
var tpT := 0.0
