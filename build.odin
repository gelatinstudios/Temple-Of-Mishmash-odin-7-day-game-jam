
package odin_7_day_jam_build

import "core:c/libc"

RUN :: 1
DEBUG :: 0
SPEED :: 1
NO_CONSOLE :: 1

when RUN != 0 {
    cmd :: "run"
} else {
    cmd :: "build"
}

when DEBUG != 0 {
    dbg :: "-debug"
} else {
    dbg :: ""
}

when SPEED != 0 {
    spd :: "-o:speed"
} else {
    spd :: ""
}

when NO_CONSOLE != 0 {
    sbs :: "-subsystem:windows"
} else {
    sbs :: ""
}

main :: proc() {
    libc.system("odin "+cmd+" source "+spd+" "+dbg+" -out:game.exe "+sbs)
}