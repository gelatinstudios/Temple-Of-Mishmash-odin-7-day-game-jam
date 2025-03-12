
package odin_7_day_jam_build

import "core:c/libc"

RUN :: 1

when RUN != 0 {
    cmd :: "run"
} else {
    cmd :: "build"
}

main :: proc() {
    libc.system("odin "+cmd+" source -debug -out:game.exe")
}