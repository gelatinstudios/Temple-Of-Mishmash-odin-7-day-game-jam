
package odin_7_day_jam

import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import sa "core:container/small_array"
import ba "core:container/bit_array"

import rl "vendor:raylib"

DEV :: true

main :: proc() {
    window_width  :: 640
    window_height :: 480
    rl.InitWindow(window_width, window_height, "THE TEMPLE OF MISHMASH")

    @static game: Game
    g := &game
    game_init(g, window_width, window_height)

    //rl.SetTargetFPS(60)
    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        game_update(g)

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        game_draw(g)
        rl.DrawFPS(5, 5)
        rl.EndDrawing()
    }
}

load_texture :: proc($path: string) -> rl.Texture {
    png_data :: #load(path)
    im := rl.LoadImageFromMemory(".png", raw_data(png_data), i32(len(png_data)))
    defer rl.UnloadImage(im)
    tex := rl.LoadTextureFromImage(im)
    rl.SetTextureFilter(tex, .POINT)
    rl.SetTextureWrap(tex, .MIRROR_REPEAT)
    return tex
}

Game :: struct {
    canon_path_indices: sa.Small_Array(Maze_Cell_Array_Size, int),
    maze: Maze,

    state: Game_State,

    window_dims: [2]int,
    level: Level,

    segment_walls: [Segment_Count]int,

    player: Vector2,
    player_dir: Vector2,
    camera_plane: f32,
    fov: f32, // in degrees

    player_keys: bit_set[Door_Color],

    player_cell_index: int, // index

    wall_texture: rl.Texture,

    // dev draw 2d
    draw_2d: bool,
    zoom_2d: f32,
}

Game_State :: enum {
    Intro = 0,
    Playing,
    Win,
}

Win_Door_Color :: Door_Color.Yellow

Trap :: enum u8 { } // TODO

Door_Color :: enum u8 { Red, Yellow, Black, White }
door_rl_color :: proc(d: Door_Color) -> rl.Color {
    switch d {
        case .Red: return rl.RED
        case .Yellow: return rl.YELLOW
        case .Black: return rl.BLACK
        case .White: return rl.WHITE
    }
    return rl.PINK
}

Segment_Count :: 4

Level :: enum { Normal, Randomize, Idol }

Player_Spawn :: [2]int {Maze_Width/2, 1}

game_init :: proc(g: ^Game, window_width, window_height: int) {
    m := &g.maze

    game_reset(g)

    g.wall_texture = load_texture("../assets/circuit.png")

    g.window_dims = {window_width, window_height}
    g.camera_plane = 25
    g.fov = 55
    g.zoom_2d = 1
}

game_reset :: proc(g: ^Game) {
    m := &g.maze

    m.cells = {}
    m.cell_dims = {50, 50}
    cell_dims := to_Vector2(m.cell_dims)
    m.dims.x = Maze_Width
    m.dims.y = 0
    for &s in g.segment_walls {
        n := rand_int_range(Min_Segment_Len, Max_Segment_Len)
        m.dims.y += n
        s = m.dims.y
    }
    m.dims.y += 1

    // choose y positions for keys
    key_y_positions: [Segment_Count]int
    for &y, i in key_y_positions {
        for {
            seg_wall := g.segment_walls[i]
            n := rand_int_range(1, seg_wall-1)
            if !slice.contains(g.segment_walls[:], n) && 
               !slice.contains(key_y_positions[:], n)
            {
                y = n
                break
            }
        }
    }

    // create path to each door
    rand_step :: proc(m: ^Maze, p: [2]int) -> [2]int {
        dp_choices: [][2]int
        if p.x == 1 {
            dp_choices = {{0, 1}, {1, 0}}
        } else if p.x == m.dims.x - 2 {
            dp_choices = {{0, 1}, {-1, 0}}
        } else {
            dp_choices = {{0, 1}, {-1, 0}, {1, 0}}
        }
        return rand.choice(dp_choices)
    }
    rand_path :: proc(m: ^Maze, start: [2]int, stop_y: int) {
        e := start
        for e.y < stop_y {
            maze_cell_ptr(m, e).open = true
            e += rand_step(m, e)
        }
    }

    door_keys: [Segment_Count]int
    
    sa.clear(&g.canon_path_indices)

    p := Player_Spawn
    for seg_wall, i in g.segment_walls {
        for p.y < seg_wall {
            // extra paths
            if p.x < m.dims.x-3 && rand.float64() < 0.01 {
                maze_cell_ptr(m, p + {1, 0}).open = true
                rand_path(m, p + {2, 0}, seg_wall-1)
            }
            if p.x > 3          && rand.float64() < 0.01 {
                maze_cell_ptr(m, p - {1, 0}).open = true
                rand_path(m, p - {2, 0}, seg_wall-1)
            }

            index := maze_cell_index(m, p)

            // canon path
            maze_cell_ptr(m, p).open = true
            sa.append(&g.canon_path_indices, index)

            p += rand_step(m, p)
            for k, i in key_y_positions {
                if p.y == k {
                    door_keys[i] = index
                }
            }
        }
        cell := maze_cell_ptr(m, p)
        cell.is_door = true
        cell.color   = Door_Color(i)
        p.y += 1
    }

    // set door key cells
    for index, color_index in door_keys {
        if index == 0 {
            game_reset(g) // awful hack absolutely awful
        }
        m.cells[index].has_key = true
        m.cells[index].color = Door_Color(color_index)
    }

    g.player = to_Vector2(Player_Spawn) * cell_dims + cell_dims*.5
    g.player_dir = {0, 1}

    g.player_cell_index = maze_cell_index(m, Player_Spawn)
}

game_reset_idol :: proc(g: ^Game) {
    m := &g.maze

    m.cells = {}
    m.cell_dims = {50, 50}
    cell_dims := to_Vector2(m.cell_dims)
    m.dims.x = Maze_Width
    m.dims.y = 10

    g.player = to_Vector2(Player_Spawn) * cell_dims + cell_dims*.5
    g.player_dir = {0, 1}

    g.player_cell_index = maze_cell_index(m, Player_Spawn)

    for y in 1 ..< m.dims.y-2 {
        for x in 1 ..< m.dims.x-2 {
            maze_cell_ptr(m, {x, y}).open = true
        }
    }

    maze_cell_ptr(m, {Maze_Width/2, 0}).is_door = true
    maze_cell_ptr(m, {Maze_Width/2, 0}).color = Win_Door_Color

    maze_cell_ptr(m, {Maze_Width/2, m.dims.y-3}).has_key = true
    maze_cell_ptr(m, {Maze_Width/2, m.dims.y-3}).color = Win_Door_Color
}

game_update :: proc(g: ^Game) {
    switch g.state {
        case .Intro:
            if rl.IsKeyPressed(.ENTER) {
                g.state = .Playing
            }
        case .Playing: game_update_playing(g)
        case .Win:
    }
}

game_update_playing :: proc(g: ^Game) {
    dt := rl.GetFrameTime()
    m := &g.maze

    moving := false

    a := to_angle(g.player_dir)
    da :: 100
    if rl.IsKeyDown(.RIGHT) {
        moving = true
        a += dt * da
    }
    if rl.IsKeyDown(.LEFT) {
        moving = true
        a -= dt * da
    }
    g.player_dir = to_normal(a)


    dp :: 100
    new_pos: Vector2
    if rl.IsKeyDown(.UP) {
        new_pos = g.player + g.player_dir * dt * dp
    }
    if rl.IsKeyDown(.DOWN) {
        new_pos = g.player - g.player_dir * dt * dp
    }
    next_cell := maze_cell_pos_ptr(m, new_pos)
    if next_cell.open {
        moving = true
        g.player = new_pos
    } else if next_cell.is_door && next_cell.color in g.player_keys {
        if next_cell.color == .White { // Reached White Door
            switch g.level {
                case .Normal:
                    game_reset(g)
                    g.level = .Randomize
                    return
                case .Randomize:
                    game_reset_idol(g)
                    g.level = .Idol
                case .Idol: unreachable()
            }
        } else if next_cell.color == Win_Door_Color && g.level == .Idol {
            g.state = .Win
            return
        } else {
            moving = true
            g.player.x = new_pos.x
            c := maze_cell_coords(m, new_pos)
            h := f32(m.cell_dims.y)
            cell_center_y := f32(c.y) * h + h/2
            if new_pos.y < cell_center_y {
                g.player.y = f32(c.y + 1) * h + 1
            } else {
                g.player.y = f32(c.y + 0) * h - 1
            }
        }
    }

    when DEV {
        if rl.IsKeyPressed(.M) {
            g.draw_2d = !g.draw_2d
        }

        if rl.IsKeyPressed(.L) {
            game_reset(g)
            g.level = .Randomize
        }

        if rl.IsKeyPressed(.I) {
            game_reset_idol(g)
            g.level = .Idol
        }

        if g.draw_2d {
            g.zoom_2d += rl.GetMouseWheelMove() * 0.05
        }
    }

    g.player_cell_index = maze_cell_pos_index(m, g.player)

    player_cell := &m.cells[g.player_cell_index]

    if player_cell.has_key {
        player_cell.has_key = false
        g.player_keys += {player_cell.color}
    }

    if moving && g.level == .Randomize {
        ignore := make(map[int]struct{}, context.temp_allocator)

        for index in sa.slice(&g.canon_path_indices) {
            ignore[index] = {}
        }

        r := make_raycaster(g)
        for a in raycast_iter(&r) {
            p := g.player
            for maze_cell_pos(m, p).open {
                p += a
                cell := maze_cell_coords(m, p)
                ignore[maze_cell_index(m, cell)] = {}
            }
            cell := maze_cell_coords(m, p)
            ignore[maze_cell_index(m, cell)] = {}
        }

        player_cell := maze_cell_coords(m, g.player)
        for dy in -1..=1 {
            for dx in -1..=1 {
                p := player_cell + {dx, dy}
                if maze_cell_ptr(m, p) != nil {
                    ignore[maze_cell_index(m, p)] = {}
                }
            }
        }

        start_y := 1
        end_y := 2
        for y in g.segment_walls {
            if y > player_cell.y {
                end_y = y - 1
                break
            }
            start_y = y + 1
        }

        start_x := 1
        end_x := m.dims.x-2
        for y in start_y..=end_y {
            for x in start_x..=end_x {
                index := maze_cell_index(m, {x, y})
                if index not_in ignore {
                    m.cells[index].open = rand.float64() < .3
                }
            }
        }
    }
}

game_draw :: proc(g: ^Game) {
    if g.draw_2d {
        game_draw_2d(g)
    } else {
        game_draw_raycast(g)
    }

    if g.state == .Intro {
        draw_text(g, "Welcome to THE TEMPLE OF MISHMASH", 
                     "Use Arrow Keys To Move",
                     "Press Enter To Begin")
    }

    if g.state == .Win {
        draw_text(g, "Congratulations!", 
                     "You found the idol and made it out",
                     "Let's hope this ends up in a museum!")
    }
}

game_draw_2d :: proc(g: ^Game) {
    m := &g.maze

    rl.ClearBackground(rl.GRAY)

    cell_dims := to_Vector2(m.cell_dims)

    camera: rl.Camera2D
    camera.target = g.player
    camera.offset = to_Vector2(g.window_dims) / 2
    camera.rotation = 0
    camera.zoom = g.zoom_2d

    rl.BeginMode2D(camera)
    defer rl.EndMode2D()

    player_cell := maze_cell_pos_ptr(m, g.player)

    start := g.player - (to_Vector2(g.window_dims) + cell_dims)
    end   := g.player + (to_Vector2(g.window_dims) + cell_dims)

    start_cell := maze_cell_coords(m, start)
    end_cell   := maze_cell_coords(m, end)

    start_cell.x = max(start_cell.x, 0)
    start_cell.y = max(start_cell.y, 0)
    end_cell.x = min(end_cell.x, m.dims.x-1)
    end_cell.y = min(end_cell.y, m.dims.y-1)

    for cell_y in start_cell.y ..= end_cell.y {
        for cell_x in start_cell.x ..= end_cell.x {
            p := [2]int {cell_x, cell_y}
            pos := to_Vector2(p) * cell_dims
            cell := maze_cell_ptr(m, p)
            if cell.open {
                if cell == player_cell {
                    rl.DrawRectangleV(pos, cell_dims, rl.BLUE)
                }
                if cell.has_key {
                    size :: 5
                    k := pos + cell_dims/2 - size/2
                    color := door_rl_color(cell.color)
                    rl.DrawRectangleV(k, {size, size}, color)
                }
                continue
            }
            color := rl.BROWN
            if cell.is_door {
                color = door_rl_color(cell.color)
            }
            rl.DrawRectangleV(pos, cell_dims, color)
        }
    }

    player_size :: 5
    rl.DrawRectangleV(g.player - player_size/2, {player_size, player_size}, rl.GREEN)

    r := make_raycaster(g)
    for a in raycast_iter(&r) {
        color := rl.RED
        color.a = 10
        p := nearest_wall_point(&g.maze, g.player, a)
        rl.DrawLineV(g.player, p, color)
    }
}

game_draw_raycast :: proc(g: ^Game) {
    r := make_raycaster(g)

    for norm, col in raycast_iter(&r) {
        p := nearest_wall_point(&g.maze, g.player, norm)

        dist := linalg.distance(p, g.player)
        depth := clamp(g.camera_plane / dist, 0, 1)

        half_screen_height := i32(g.window_dims.y/2)
        x := i32(col)
        dy := i32(depth * f32(g.window_dims.y/2))
        y0 := half_screen_height - dy
        y1 := half_screen_height + dy

        rl.DrawLine(x, y0, x, y1, rl.WHITE)

        source := rl.Rectangle {
            x = f32(x + y0),
            y = f32(y0),
            width = f32(100 + x/2),
            height = f32(y1-y0),
        }

        dest := rl.Rectangle {
            x = f32(x),
            y = f32(y0),
            width = 1,
            height = f32(y1-y0),
        }

//        rl.DrawTexturePro(g.wall_texture, source, dest, {}, 0, rl.WHITE)
    }
}



Raycaster :: struct {
    g: ^Game,
    camera_plane_extent: Vector2,
    col: int,
}

make_raycaster :: proc(g: ^Game) -> Raycaster {
    camera_plane_dir := Vector2 {-g.player_dir.y, g.player_dir.x}
    camera_plane_extent := camera_plane_dir
    camera_plane_extent *= tan(g.fov / 2) * g.camera_plane

    r: Raycaster
    r.g = g
    r.camera_plane_extent = camera_plane_extent
    r.col = 0
    return r
}

raycast_iter :: proc(r: ^Raycaster) -> (Vector2, int, bool) {
    g := r.g
    if r.col >= g.window_dims.x {
        return {}, r.col, false
    }
    defer r.col += 1
    d := f32(r.col) / f32(g.window_dims.x)
    d = d * 2 - 1
    p := g.player
    p += g.player_dir * g.camera_plane
    p += r.camera_plane_extent * d
    dir := noz(p - g.player)
    return dir, r.col, true
}



Maze :: struct {
    cells: [Maze_Cell_Array_Size]Cell,
    dims: [2]int,
    cell_dims: [2]int,
}

Maze_Width :: 100

Min_Segment_Len :: 50
//Min_Segment_Len :: 10
Max_Segment_Len :: 100
//Max_Segment_Len :: 20

Maze_Cell_Array_Size :: Maze_Width * (Max_Segment_Len+1) * Segment_Count

Cell :: bit_field u8 {
    open:     bool | 1,
    is_door:  bool | 1,
    has_key:  bool | 1,
    has_trap: bool | 1,
    color: Door_Color | 2,
    trap: Trap | 2,
}

maze_cell_index :: proc(maze: ^Maze, p: [2]int) -> int {
    return p.x + p.y * maze.dims.x
}

maze_cell_ptr :: proc(maze: ^Maze, p: [2]int) -> ^Cell {
    if p.x < 0 || p.x >= maze.dims.x do return nil
    if p.y < 0 || p.y >= maze.dims.y do return nil
    return &maze.cells[maze_cell_index(maze, p)]
}

maze_cell :: proc(maze: ^Maze, p: [2]int) -> Cell {
    p := maze_cell_ptr(maze, p)
    if p == nil do return {}
    return p^
}

maze_cell_coords :: proc(maze: ^Maze, p: Vector2) -> [2]int {
    c := p / to_Vector2(maze.cell_dims)
    return {int(c.x), int(c.y)}
}

maze_cell_pos_ptr :: proc(maze: ^Maze, p: Vector2) -> ^Cell {
    return maze_cell_ptr(maze, maze_cell_coords(maze, p))
}

maze_cell_pos :: proc(maze: ^Maze, p: Vector2) -> Cell {
    p := maze_cell_pos_ptr(maze, p)
    if p == nil do return {}
    return p^
}

maze_cell_pos_index :: proc(maze: ^Maze, p: Vector2) -> int {
    return maze_cell_index(maze, maze_cell_coords(maze, p))
}

nearest_wall_cell :: proc(maze: ^Maze, start: Vector2, dir: Vector2) -> [2]int {
    p := start
    for maze_cell_pos(maze, p).open {
        p += dir
    }
    return maze_cell_coords(maze, p)
}

nearest_wall_point :: proc(maze: ^Maze, start: Vector2, dir: Vector2) -> Vector2 {
    cell := nearest_wall_cell(maze, start, dir)

    cell_min := to_Vector2(cell * maze.cell_dims)
    cell_max := cell_min + to_Vector2(maze.cell_dims)

    box := rl.BoundingBox {
        min = {cell_min.x, cell_min.y, 0},
        max = {cell_max.x, cell_max.y, 0},
    }

    ray := rl.Ray {
        position = {start.x, start.y, 0},
        direction = {dir.x, dir.y, 0},
    }

    rc := rl.GetRayCollisionBox(ray, box)

    return rc.point.xy
}



draw_text :: proc(g: ^Game, titles: ..cstring) {
    height :: 24
    padding :: 5
    total_height := len(titles) * height
    total_height += (len(titles)-1) * padding

    y := g.window_dims.y/2 - total_height/2

    total_width := 0
    for t in titles {
        total_width = max(total_width, int(rl.MeasureText(t, height)))
    }

    x := g.window_dims.x/2 - total_width/2 

    rl.DrawRectangle(i32(x), i32(y), i32(total_width), i32(total_height), rl.BROWN)

    for t in titles {
        width := int(rl.MeasureText(t, height))
        x := g.window_dims.x/2 - width/2
        rl.DrawText(t, i32(x), i32(y), height, rl.RAYWHITE)
        y += height + padding
    }
}