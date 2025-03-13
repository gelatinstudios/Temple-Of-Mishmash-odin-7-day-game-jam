
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

screen_width  :: 640
screen_height :: 480

screen_dims  :: [2]int {screen_width, screen_height}
screen_dimsf :: Vector2 {screen_width, screen_height}

// VISUALS:
// TODO: give keys outline
// TODO: Intro and outro words make look better (font and stuff)
// TODO: Intro cutscene of logo?

// GAME DESIGN:
// TODO: keys spawn in extra paths
// TODO: for Randomized, save ALL paths and rearrange any extra paths you aren't in
// TODO: some kind of difficulty progression throughout?

// AUDIO:
// TODO: music
// TODO: sound effects:
//         - footsteps
//         - key pickup
//         - doors
//         - idol pickup

main :: proc() {
    rl.InitWindow(0, 0, "THE TEMPLE OF MISHMASH")

    mon := rl.GetCurrentMonitor()
    w, h: i32 = screen_width, screen_height
    for i: i32 = 1; true; i += 1{
        nw, nh := w*i, h*i
        if nw > rl.GetMonitorWidth (mon) do break
        if nh > rl.GetMonitorHeight(mon) do break
        w, h = nw, nh
    }
    rl.SetWindowSize(w, h)
    rl.SetWindowPosition(rl.GetMonitorWidth (mon)/2 - w/2,
                         rl.GetMonitorHeight(mon)/2 - h/2)

    rl.DisableCursor()

    rend_tex := rl.LoadRenderTexture(screen_width, screen_height)
    rl.SetTextureFilter(rend_tex.texture, .POINT)

    @static game: Game
    g := &game
    game_init(g, screen_width, screen_height)

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        g.raycast_results = {}
        game_update(g)

        rl.BeginDrawing()
        rl.BeginTextureMode(rend_tex)
        rl.ClearBackground(rl.BLACK)
        game_draw(g)
        rl.DrawFPS(5, 5)
        rl.EndTextureMode()

        rl.DrawTexturePro(texture =  rend_tex.texture, 
                          source = {0, 0, screen_width, -screen_height},
                          dest = {0, 0, f32(w), f32(h)},
                          origin = {}, 
                          rotation = 0, 
                          tint = rl.WHITE)
        rl.EndDrawing()
    }
}

load_image :: proc($path: string) -> rl.Image {
    png_data :: #load(path)
    im := rl.LoadImageFromMemory(".png", raw_data(png_data), i32(len(png_data)))
    return im
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
    raycast_results: Maybe(Raycast_Results),

    maze: Maze,

    state: Game_State,

    level: Level,

    segment_walls: [Segment_Count]int,

    player: Vector2,
    player_dir: Vector2,
    camera_plane: f32,
    fov: f32, // in degrees

    player_keys: bit_set[Door_Color],

    player_cell_index: int, // index

    wall_texture: rl.Texture,
    key_texture: rl.Texture,

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

Door_Color :: enum u8 { Red, Yellow, Black, White }
door_rl_color :: proc(d: Door_Color) -> rl.Color {
    switch d {
        case .Red: return rl.RED
        case .Yellow: return rl.PURPLE + {40, 40, 40, 0}
        case .Black: return {109, 0, 183, 255}
        case .White: return rl.WHITE
    }
    return rl.PINK
}

Raycast_Results :: #soa[]Raycast_Result_Column
Raycast_Result_Column :: struct {
    point: Vector2,
    dist: f32,
    hit_cell: Cell,
    tex_u_coord: f32,
    cells_in_view: [][2]int,
}

Segment_Count :: 4

Level :: enum { Normal, Randomize, Idol }

Player_Spawn :: [2]int {Maze_Width/2, 1}

game_init :: proc(g: ^Game, screen_width, screen_height: int) {
    m := &g.maze

    game_reset(g)

    g.wall_texture = load_texture("../assets/circuit.png")
    g.key_texture = load_texture("../assets/key.png")

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
    key_range_start := 1
    for &y, i in key_y_positions {
        for {
            seg_wall := g.segment_walls[i]
            n := rand_int_range(key_range_start, seg_wall-1)
            if !slice.contains(g.segment_walls[:], n) && 
               !slice.contains(key_y_positions[:], n)
            {
                y = n
                key_range_start = n + 5
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
        start_of_path := true
        for p.y < seg_wall {
            // extra paths
            if p.x < m.dims.x-3 && rand.float64() < 0.05 {
                maze_cell_ptr(m, p + {1, 0}).open = true
                rand_path(m, p + {2, 0}, seg_wall-1)
            }
            if p.x > 3          && rand.float64() < 0.05 {
                maze_cell_ptr(m, p - {1, 0}).open = true
                rand_path(m, p - {2, 0}, seg_wall-1)
            }

            index := maze_cell_index(m, p)

            // canon path
            maze_cell_ptr(m, p).open = true
            sa.append(&g.canon_path_indices, index)

            p += start_of_path ? {0, 1} : rand_step(m, p)
            for k, i in key_y_positions {
                if p.y == k {
                    door_keys[i] = index
                }
            }
            start_of_path = false
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

    g.player_keys = {}
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

    g.player_keys = {}

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
    // TODO: scale this correctly???
    // a += dt * rl.GetMouseDelta().x * 100

    g.player_dir = to_normal(a)
    forward := g.player_dir
    right   := Vector2 {forward.y, -forward.x}
    dp :: 75
    new_pos: Vector2
    if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) {
        new_pos = g.player + forward * dt * dp
    }
    if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) {
        new_pos = g.player - forward * dt * dp
    }
    if rl.IsKeyDown(.A) {
        new_pos = g.player + right * dt * dp
    } 
    if rl.IsKeyDown(.D)  {
        new_pos = g.player - right * dt * dp
    }


    next_cell := maze_cell_pos_ptr(m, new_pos)
    if next_cell.open {
        moving = true
        g.player = new_pos
    } else if next_cell.is_door && next_cell.color in g.player_keys {
        if next_cell.color == .White {
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

        cols := get_raycast_results(g)
        for col in cols {
            for coord in col.cells_in_view {
                ignore[maze_cell_index(m, coord)] = {}
            }
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
                    m.cells[index].open = rand.float64() < .4
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

    game_draw_ui(g)

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
    camera.offset = screen_dimsf / 2
    camera.rotation = 0
    camera.zoom = g.zoom_2d

    rl.BeginMode2D(camera)
    defer rl.EndMode2D()

    player_cell := maze_cell_pos_ptr(m, g.player)

    start := g.player - (screen_dimsf + cell_dims) / g.zoom_2d
    end   := g.player + (screen_dimsf + cell_dims) / g.zoom_2d

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

    for col in get_raycast_results(g) {
        color := rl.RED
        color.a = 10
        rl.DrawLineV(g.player, col.point, color)
    }
}

game_draw_raycast :: proc(g: ^Game) {
    rl.ClearBackground(rl.PINK)
    rl.DrawRectangle(0,              0, 
                     screen_width,   screen_height/2, 
                     rl.BROWN + {40, 40, 40, 0})
    rl.DrawRectangle(0,            screen_height/2, 
                     screen_width, screen_height/2, 
                     rl.BROWN + {50, 50, 50, 0})

    m := &g.maze

    cell_dims := to_Vector2(m.cell_dims)

    keys_drawn: bit_set[Door_Color]
    Key_Draw_Info :: struct {
        pos: Vector2,
        scale: f32,
        dist: f32,
        color: rl.Color,
    }

    keys: sa.Small_Array(Segment_Count, Key_Draw_Info)

    camera_plane_dir := Vector2 {-g.player_dir.y, g.player_dir.x}
    half_screen_height :: screen_height / 2
    half_screen_width  :: screen_width / 2

    @static z_buffer: [screen_width][screen_height]f32
    for &col in z_buffer {
        for &z in col {
            z = max(f32)
        }
    }

    Wall_Column :: struct {
        z: f32,
        x, y0, y1: i32,
        source, dest: rl.Rectangle,
        color: rl.Color,
    }

    @static wall_cols: [screen_width]Wall_Column

    // draw walls
    for col, col_index in get_raycast_results(g) {
        depth := g.camera_plane / col.dist

        x := i32(col_index)
        dy := i32(depth * half_screen_height)
        y0 := half_screen_height - dy
        y1 := half_screen_height + dy

        cell := col.hit_cell
        color := rl.BROWN
        if cell.is_door {
            color = door_rl_color(cell.color)
        }

        for y in max(y0, 0)..<min(y1, screen_height-1) {
            z_buffer[x][y] = col.dist
        }

        source := rl.Rectangle {
            x = col.tex_u_coord * f32(g.wall_texture.width),
            y = 0,
            width = 1,
            height = f32(g.wall_texture.height),
        }

        dest := rl.Rectangle {
            x = f32(x),
            y = f32(y0),
            width = 1,
            height = f32(y1-y0),
        }

        rl.DrawTexturePro(g.wall_texture, source, dest, {}, 0, color)

        wall_cols[col_index] = {col.dist, x, y0, y1, source, dest, color}
    }

    { // draw keys
        for col in get_raycast_results(g) {
            for coord in col.cells_in_view {
                cell := maze_cell(m, coord)
                if cell.has_key && cell.color not_in keys_drawn {
                    keys_drawn += {cell.color}

                    k := to_Vector2(coord) * cell_dims + cell_dims/2
                    dist := linalg.distance(g.player, k)

                    N :: 7
                    sa.append(&keys, Key_Draw_Info {
                        pos = k,
                        scale = clamp(N * g.camera_plane / dist, 0, N),
                        color = door_rl_color(cell.color),
                        dist = dist,
                    })
                }
            }
        }

        slice.reverse_sort_by_key(sa.slice(&keys), proc(k: Key_Draw_Info) -> f32 {
            return k.dist
        })

        camera: rl.Camera
        camera.position = {g.player.x, g.player.y, 0}
        camera.target = camera.position + {g.player_dir.x, g.player_dir.y, 0}
        camera.up = {0, 0, -1}
        camera.fovy = 40 // idfk where this number comes from it just feels best
        camera.projection = .PERSPECTIVE
        for k in sa.slice(&keys) {
            s := rl.GetWorldToScreenEx({k.pos.x, k.pos.y, 0}, camera, screen_width, screen_height)
            w := f32(g.key_texture.width)  * k.scale
            h := f32(g.key_texture.height) * k.scale
            s -= {w, h} * .5
            x_start := max(int(s.x), 0)
            y_start := max(int(s.y), 0)
            x_end := min(int(s.x+w-1), screen_width-1)
            y_end := min(int(s.y+h-1), screen_height-1)
            for x in x_start..=x_end {
                for y in y_start..=y_end {
                    z_buffer[x][y] = k.dist
                }
            }
            rl.DrawTextureEx(g.key_texture, s, 0, k.scale, k.color)
        }
    }

    // draw walls again
    // we draw the walls twice because of z buffering stupidity
    for c in wall_cols {
        draw := true
        for y in max(c.y0, 0)..<min(c.y1, screen_height-1) {
            if z_buffer[c.x][y] < c.z {
                draw = false
                break
            }
        }
        if draw {
            rl.DrawTexturePro(g.wall_texture, c.source, c.dest, {}, 0, c.color)
        }
    }
}

game_draw_ui :: proc(g: ^Game) {
    border :: 5
    padding :: -5
    x: i32 = border
    y: i32 = screen_height - border - g.key_texture.height
    for k in g.player_keys {
        rl.DrawTexture(g.key_texture, x, y, door_rl_color(k))
        x += g.key_texture.width + padding
    }
}

get_camera_plane_extent :: proc(g: ^Game) -> Vector2 {
    camera_plane_dir := Vector2 {-g.player_dir.y, g.player_dir.x}
    camera_plane_extent := camera_plane_dir
    camera_plane_extent *= tan(g.fov / 2) * g.camera_plane
    return camera_plane_extent   
}

get_raycast_results :: proc(g: ^Game) -> Raycast_Results {
    Raycaster :: struct {
        g: ^Game,
        camera_plane_extent: Vector2,
        col: int,
    }

    make_raycaster :: proc(g: ^Game) -> Raycaster {
        r: Raycaster
        r.g = g
        r.camera_plane_extent = get_camera_plane_extent(g)
        r.col = 0
        return r
    }

    raycast_iter :: proc(r: ^Raycaster) -> (Vector2, int, bool) {
        g := r.g
        if r.col >= screen_width {
            return {}, r.col, false
        }
        defer r.col += 1
        d := f32(r.col) / screen_width
        d = d * 2 - 1
        p := g.player
        p += g.player_dir * g.camera_plane
        p += r.camera_plane_extent * d
        dir := noz(p - g.player)
        return dir, r.col, true
    }

    if results, ok := g.raycast_results.?; ok {
        return results
    }

    results := make(Raycast_Results, screen_width, context.temp_allocator)

    m := &g.maze

    cell_dims := to_Vector2(m.cell_dims)
    unit2 := cell_dims.x * cell_dims.y

    r := make_raycaster(g)
    for dir, i in raycast_iter(&r) {
        cells_in_view := make([dynamic][2]int, context.temp_allocator)

        // https://www.youtube.com/watch?v=NbSee-XM7WA
        p := g.player
        coord := maze_cell_coords(m, p)
        p /= cell_dims
        ray_unit := Vector2{ math.sqrt(1 + square(dir.y / dir.x)),
                             math.sqrt(1 + square(dir.x / dir.y))}
        ray_len: Vector2
        step: [2]int
        dist: f32
        x_side: bool
        if dir.x < 0 {
            step.x = -1
            ray_len.x = (p.x - f32(coord.x)) * ray_unit.x
        } else {
            step.x = 1
            ray_len.x = (f32(coord.x + 1) - p.x) * ray_unit.x
        }
        if dir.y < 0 {
            step.y = -1
            ray_len.y = (p.y - f32(coord.y)) * ray_unit.y
        } else {
            step.y = 1
            ray_len.y = (f32(coord.y + 1) - p.y) * ray_unit.y
        }
        for maze_cell(m, coord).open {
            if ray_len.x < ray_len.y {
                coord.x += step.x
                dist = ray_len.x
                ray_len.x += ray_unit.x
                x_side = true
            } else {
                coord.y += step.y
                dist = ray_len.y
                ray_len.y += ray_unit.y
                x_side = false
            }
            append(&cells_in_view, coord)
        }

        dist *= cell_dims.x
        point := g.player + dist * dir

        // https://lodev.org/cgtutor/raycasting.html
        tex_u_coord: f32
        if x_side do tex_u_coord = p.y + (ray_len.x - ray_unit.x) * dir.y
        else      do tex_u_coord = p.x + (ray_len.y - ray_unit.y) * dir.x
        tex_u_coord -= math.floor(tex_u_coord)
        if  x_side && dir.x > 0 do tex_u_coord = 1 - tex_u_coord
        if !x_side && dir.y < 0 do tex_u_coord = 1 - tex_u_coord

        results[i] = Raycast_Result_Column {
            point = point,
            dist = dist,
            hit_cell = maze_cell(m, coord),
            tex_u_coord = tex_u_coord,
            cells_in_view = cells_in_view[:]
        }
    }

    g.raycast_results = results

    return results
}



Maze :: struct {
    cells: [Maze_Cell_Array_Size]Cell,
    dims: [2]int,
    cell_dims: [2]int,
}

Maze_Width :: 100

//Min_Segment_Len :: 50
Min_Segment_Len :: 10
//Max_Segment_Len :: 100
Max_Segment_Len :: 20

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



draw_text :: proc(g: ^Game, titles: ..cstring) {
    height :: 24
    padding :: 5
    total_height := len(titles) * height
    total_height += (len(titles)-1) * padding

    y := screen_height/2 - total_height/2

    total_width := 0
    for t in titles {
        total_width = max(total_width, int(rl.MeasureText(t, height)))
    }

    x := screen_width/2 - total_width/2 
    rl.DrawRectangle(i32(x), i32(y), i32(total_width), i32(total_height), rl.BROWN)

    for t in titles {
        width := int(rl.MeasureText(t, height))
        x := screen_width/2 - width/2
        rl.DrawText(t, i32(x), i32(y), height, rl.RAYWHITE)
        y += height + padding
    }
}