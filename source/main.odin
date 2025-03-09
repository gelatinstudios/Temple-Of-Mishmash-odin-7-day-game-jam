
package odin_7_day_jam

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import ba "core:container/bit_array"

import rl "vendor:raylib"

DEV :: true

main :: proc() {
    window_width  :: 1280
    window_height :: 720
    rl.InitWindow(window_width, window_height, "MotherBored")

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
    maze: Maze,
    window_dims: [2]int,

    player: Vector2,
    player_dir: Vector2,
    camera_plane: f32,
    fov: f32, // in degrees

    // TODO: index instead of pointer?
    player_cell: ^Cell,
    goal: ^Cell,

    var_cells: []i32,

    wall_texture: rl.Texture,

    // dev draw 2d
    draw_2d: bool,
    zoom_2d: f32,
}

game_init :: proc(g: ^Game, window_width, window_height: int) {
    maze_init(&g.maze)

    player_coords := [2]int {g.maze.dims.x/2, 1}
    {
        for &c in g.maze.cells {
            c = .Wall
        }
        p := player_coords

        for p.y < g.maze.dims.y - 2 {
            maze_cell_ptr(&g.maze, p.x, p.y)^ = .Empty
            dp_choices: [][2]int
            if p.x == 1 {
                dp_choices = {{0, 1}, {1, 0}}
            } else if p.x == g.maze.dims.x - 2 {
                dp_choices = {{0, 1}, {-1, 0}}
            } else {
                dp_choices = {{0, 1}, {-1, 0}, {1, 0}}
            }
            p += rand.choice(dp_choices)
        }
        g.goal = maze_cell_ptr(&g.maze, p.x, p.y)
        g.goal^ = .Empty

        var_cells: [dynamic]i32
        for y in 1 ..< g.maze.dims.y-1 {
            for x in 1 ..< g.maze.dims.x-1 {
                if maze_cell(&g.maze, x, y) == .Wall {
                    index := x + y * g.maze.dims.x
                    append(&var_cells, i32(index))
                }
            }
        }
        g.var_cells = var_cells[:]
    }


    cell_dims := to_Vector2(g.maze.cell_dims)

    g.window_dims = {window_width, window_height}
    g.player = to_Vector2(player_coords) * cell_dims + cell_dims*.5
    g.player_dir = {0, 1}
    g.camera_plane = 25
    g.fov = 55

    g.player_cell = maze_cell_ptr(&g.maze, player_coords.x, player_coords.y)

    g.wall_texture = load_texture("../assets/circuit.png")

    g.zoom_2d = 1
}

game_update :: proc(g: ^Game) {
    dt := rl.GetFrameTime()

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
    if maze_cell_pos(&g.maze, new_pos) == .Empty {
        moving = true
        g.player = new_pos
    }

    when DEV {
        if rl.IsKeyPressed(.M) {
            g.draw_2d = !g.draw_2d
        }

        if g.draw_2d {
            g.zoom_2d += rl.GetMouseWheelMove() * 0.05
        }
    }

    g.player_cell = maze_cell_pos_ptr(&g.maze, g.player)
    g.player_cell^ = .Empty

    if moving {
        ignore := make(map[i32]struct{}, context.temp_allocator)

        r := make_raycaster(g)
        for a in raycast_iter(&r) {
            p := g.player
            for maze_cell_pos(&g.maze, p) == .Empty {
                p += a
                cell := maze_cell_coords(&g.maze, p)
                index := cell.x + cell.y * g.maze.dims.x
                ignore[i32(index)] = {}
            }
            cell := maze_cell_coords(&g.maze, p)
            index := cell.x + cell.y * g.maze.dims.x
            ignore[i32(index)] = {}
        }

        player_cell := maze_cell_coords(&g.maze, g.player)
        for dy in -1..=1 {
            for dx in -1..=-1 {
                x := player_cell.x + dx
                y := player_cell.y + dy
                index := x + y * g.maze.dims.x
                ignore[i32(index)] = {}
            }
        }

        for i in g.var_cells {
            if i not_in ignore {
                g.maze.cells[i] = rand.choice_enum(Cell)
            }
        }
    }

    if g.player_cell == g.goal {
        fmt.println("YOU WIN!")
    }
}

game_draw :: proc(g: ^Game) {
    if g.draw_2d {
        game_draw_2d(g)
    } else {
        game_draw_raycast(g)
    }
}

game_draw_2d :: proc(g: ^Game) {
    cell_dims := to_Vector2(g.maze.cell_dims)

    camera: rl.Camera2D
    camera.target = g.player
    camera.offset = to_Vector2(g.window_dims) / 2
    camera.rotation = 0
    camera.zoom = g.zoom_2d

    rl.BeginMode2D(camera)
    defer rl.EndMode2D()

    player_cell := maze_cell_pos_ptr(&g.maze, g.player)

    for cell_y in 0 ..< g.maze.dims.y {
        for cell_x in 0 ..< g.maze.dims.x {
            p := to_Vector2({cell_x, cell_y}) * cell_dims
            cell := maze_cell_ptr(&g.maze, cell_x, cell_y)
            if cell^ == .Empty {
                if cell == g.goal {
                    rl.DrawRectangleV(p, cell_dims, rl.PURPLE)
                }
                if cell == player_cell {
                    rl.DrawRectangleV(p, cell_dims, rl.BLUE)
                }
                continue
            }
            rl.DrawRectangleV(p, cell_dims, rl.WHITE)
        }
    }

    player_size :: 5
    rl.DrawRectangleV(g.player - player_size/2, {player_size, player_size}, rl.GREEN)

    r := make_raycaster(g)
    for a in raycast_iter(&r) {
        rl.DrawLineV(g.player, nearest_wall_point(&g.maze, g.player, a), rl.RED)
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
    cells: []Cell,
    dims: [2]int,
    cell_dims: [2]int,
}

Cell :: enum {
    Empty,
    Wall,
}

maze_init :: proc(maze: ^Maze) {
    x :: 20
    y :: 20
    maze.cells = make([]Cell, x * y)
    maze.dims.x = x
    maze.dims.y = y

    maze.cell_dims = {50, 50}
}

maze_cell_ptr :: proc(maze: ^Maze, x, y: int) -> ^Cell {
    if x < 0 || x >= maze.dims.x do return nil
    if y < 0 || y >= maze.dims.y do return nil
    return &maze.cells[x + y * maze.dims.x]
}

maze_cell :: proc(maze: ^Maze, x, y: int) -> Cell {
    p := maze_cell_ptr(maze, x, y)
    if p == nil do return .Empty
    return p^
}

maze_cell_coords :: proc(maze: ^Maze, p: Vector2) -> [2]int {
    c := p / to_Vector2(maze.cell_dims)
    return {int(c.x), int(c.y)}
}

maze_cell_pos_ptr :: proc(maze: ^Maze, p: Vector2) -> ^Cell {
    cell := maze_cell_coords(maze, p)
    return maze_cell_ptr(maze, int(cell.x), int(cell.y))
}

maze_cell_pos :: proc(maze: ^Maze, p: Vector2) -> Cell {
    p := maze_cell_pos_ptr(maze, p)
    if p == nil do return .Empty
    return p^
}

nearest_wall_cell :: proc(maze: ^Maze, start: Vector2, dir: Vector2) -> [2]int {
    p := start
    dp := f32(min(maze.cell_dims.x, maze.cell_dims.y)) / 2
    for maze_cell_pos(maze, p) == .Empty {
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