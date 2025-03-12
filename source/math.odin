
package odin_7_day_jam

import "core:math"
import "core:math/linalg"
import "core:math/rand"

import rl "vendor:raylib"

Vector2 :: rl.Vector2
to_Vector2 :: proc(v: [2]int) -> Vector2 { return {f32(v.x), f32(v.y)} }

to_angle :: proc(v: Vector2) -> f32 { return atan2(v.y, v.x) }
to_normal :: proc(angle: f32) -> Vector2 { return {cos(angle), sin(angle)} }

square :: proc(x: $T) -> T { return x*x }

tan :: proc(x: f32) -> f32 { return math.tan(math.to_radians(x)) } 
cos :: proc(x: f32) -> f32 { return math.cos(math.to_radians(x)) } 
sin :: proc(x: f32) -> f32 { return math.sin(math.to_radians(x)) } 
atan2 :: proc(y, x: f32) -> f32 { return math.to_degrees(math.atan2(y, x)) } 

noz :: proc(v: Vector2) -> Vector2 { return linalg.normalize0(v) }

rand_int_range :: proc(x, y: int) -> int {
    return x + rand.int_max(y-x)
}