
package odin_7_day_jam_build

import "core:c/libc"

main :: proc() {
    libc.system("odin run source -debug -out:game.exe")
}