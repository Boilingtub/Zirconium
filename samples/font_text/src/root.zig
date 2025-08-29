const do_checks = true;
const version = "0.0.7";
const gpu = @import("gpu");
const std = gpu.std;
const zglfw = gpu.zglfw;
const zgpu = gpu.zgpu;
const State = gpu.State;
const Camera = gpu.Camera;
const mesh = gpu.mesh;
pub const Mesh = mesh.Mesh;
pub const Vertex = mesh.Vertex;
pub const IndexType = mesh.IndexType;
pub const Drawable = mesh.Drawable;
const zstbi = gpu.zstbi;
const Image = zstbi.Image;
pub const text = gpu.text;
pub const TextObject = text.TextObject;
pub const TextDrawable = text.TextDrawable;
pub const TextUniform = text.TextUniform;
pub const IntArrayFromTo = text.IntArrayFromTo;
pub const FontTextureAtlas = text.FontTextureAtlas;
pub const pipelines = @import("pipelines.zig");

const base_shader = @embedFile("./shaders/base.wgsl");
const text_base_shader = @embedFile("./shaders/text.wgsl");
const ttf_default_font = @embedFile("./embed/ttf/GoNotoCurrent-Regular.ttf");
const png_default_font = @embedFile("./embed/png/Roboto-Medium.png");



fn initScene(
    allocator: std.mem.Allocator,
    font_texture_atlas: *const FontTextureAtlas,
    textobjects: *std.ArrayList(TextObject),
    textdrawables: *std.ArrayList(TextDrawable),
    drawables: *std.ArrayList(Drawable),
    meshes: *std.ArrayList(Mesh),
    images: *std.ArrayList(Image),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        const new_mesh = mesh.primitive_cube;
        var new_image = zstbi.Image.loadFromFile("./content/128x128_textures/genart.png", 4) 
        catch unreachable;
        Force_image_MipMap_compatible(&new_image);


        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .texture_index = @as(u32, @intCast(images.items.len)),
            .position = .{ 9, 0, 5 },
            .basecolor_roughness = .{ 1.0, 1.0, 1.0, 0.0 },
        }) catch unreachable;

        images.append(new_image) catch unreachable;
        mesh.appendMesh(
            new_mesh,
            meshes,
            meshes_indices,
            meshes_vertices,
        );
    }

    {
        const new_mesh = mesh.primitive_plane;
        var new_image = zstbi.Image.loadFromFile("./content/128x128_textures/face_img.jpg", 4) 
        catch unreachable;
        Force_image_MipMap_compatible(&new_image);
        //std.debug.print("primitive_plane mesh data!\n", .{}); new_mesh.print();


        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .texture_index = @as(u32, @intCast(images.items.len)),
            .position = .{ 6, 0, 5 },
            .basecolor_roughness = .{ 1.0, 1.0, 1.0, 0.0 },
        }) catch unreachable;

        images.append(new_image) catch unreachable;
        mesh.appendMesh(
            new_mesh,
            meshes,
            meshes_indices,
            meshes_vertices,
        );
    }
    {
        const new_mesh = mesh.load_gltf_file(arena,"./content/cube.glb") catch unreachable;
        //const new_mesh = mesh.primitive_cube;
        var new_image = zstbi.Image.loadFromFile("./content/128x128_textures/stone_rocks.jpg", 4) 
        catch unreachable;
        Force_image_MipMap_compatible(&new_image);
        //std.debug.print("cube.glb mesh data!\n", .{}); new_mesh.print();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .texture_index = @as(u32, @intCast(images.items.len)),
            .position = .{ 3, 0, 5 },
            .basecolor_roughness = .{ 1.0, 1.0, 1.0, 0.0 },
        }) catch unreachable;

        images.append(new_image) catch unreachable;
        mesh.appendMesh(
            new_mesh,
            meshes,
            meshes_indices,
            meshes_vertices,
        );
    }
    {
        const new_mesh = mesh.load_gltf_file(arena, "./content/ball_model.glb") catch unreachable ;
        var new_image = zstbi.Image.loadFromFile("./content/128x128_textures/paint_abstract.jpg", 4) 
        catch unreachable;
        Force_image_MipMap_compatible(&new_image);
        //std.debug.print("ball_mode.glb mesh data!\n", .{}); new_mesh.print();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .texture_index = @as(u32, @intCast(images.items.len)),
            .position = .{ 0, 0, 5 },
            .basecolor_roughness = .{ 0.0, 0.0, 1.0, 0.6 },
        }) catch unreachable;

        images.append(new_image) catch unreachable;
        mesh.appendMesh(
            new_mesh,
            meshes,
            meshes_indices,
            meshes_vertices,
        );
    }
    {
        const new_mesh = mesh.load_gltf_file(arena, "./content/chair.glb") catch unreachable;
        var new_image = zstbi.Image.loadFromFile("./content/128x128_textures/lava_solidified.jpg", 4) 
        catch unreachable;
        Force_image_MipMap_compatible(&new_image);


        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .texture_index = @as(u32, @intCast(images.items.len)),
            .position = .{ -3, 0, 5 },
            .basecolor_roughness = .{ 0.5, 0.7, 0.2, 0.6 },
        }) catch unreachable;

        images.append(new_image) catch unreachable;
        mesh.appendMesh(
            new_mesh,
            meshes,
            meshes_indices,
            meshes_vertices,
        );
    }
    {
        const new_text = TextObject.string_to_textobj(
            allocator, 
            font_texture_atlas, 
            //" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",
            "Zirconium:font_text V-0.0.7",
            .{0.062,0.062},
        );
        textdrawables.append(.{
            .textobj_index = @as(u32, @intCast(textobjects.items.len)), 
            .position = .{-1,0.97}, 
            .scale = .{0.03,0.03},
            .color = .{1,1,1,1}
        }) catch unreachable;
        textobjects.append(new_text) catch unreachable;
    

    }
}

pub fn create_default_state(allocator: std.mem.Allocator,
    window: *zglfw.Window) !*State {
    const state = try State.init_empty(allocator,window);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    zstbi.init(arena);

    //Init Scene data
    var textobjects = std.ArrayList(TextObject).init(allocator);
    var textdrawables = std.ArrayList(TextDrawable).init(allocator);
    var meshes = std.ArrayList(Mesh).init(allocator);
    var drawables = std.ArrayList(Drawable).init(allocator);
    
    const font_chars = comptime IntArrayFromTo(32, 127);
    //remember: font texture atlas allocated with arena will clear at end of init 
    const font_texture_atlas = try FontTextureAtlas.from_png(
        allocator, png_default_font, &font_chars
    );
    
    var images = std.ArrayList(Image).init(arena);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_vertices = std.ArrayList(Vertex).init(arena);
    
    initScene(
        allocator,
        &font_texture_atlas,&textobjects, &textdrawables,
        &drawables, &meshes, &images,
        &meshes_indices, &meshes_vertices,
    );

    state.textobjects = textobjects;
    state.textdrawables = textdrawables;

    state.meshes = meshes;
    state.drawables = drawables;
    state.camera = Camera {};

    state.text_instance_buffers = try std.ArrayList(zgpu.BufferHandle).initCapacity(
        allocator, state.textobjects.items.len
    );
    pipelines.text_pipeline(state,&font_texture_atlas,text_base_shader);
    pipelines.render_pipeline(
        state,
        meshes_vertices.items,
        meshes_indices.items,
        images.items,
        base_shader,
    );
    pipelines.create_commands(allocator,state);
    
    if(do_checks == true) {
        for (state.textobjects.items) |to| {
            to.print();
        }
    } 

    return state;
}

pub export fn Force_image_MipMap_compatible(image: *zstbi.Image) void {
    const square_size = round_pow_2_up(@max(image.width, image.height));
    image.* = image.*.resize(square_size,square_size);
}

pub export fn round_pow_2_down(a:u32) u32 {
    var x = a;
    x |= x>>1;
    x |= x>>2;
    x |= x>>4;
    x |= x>>8;
    x |= x>>16;
    x = (x>>1) + 1;
    return x;
}
pub export fn round_pow_2_up(a:u32) u32 {
    var x = a;
    x -=1;   
    x |= x>>1;
    x |= x>>2;
    x |= x>>4;
    x |= x>>8;
    x |= x>>16;
    x+=1;
    return x;
}

pub const Windowing = struct {
    pub const CURSOR = zglfw.InputMode.cursor;
    pub const CURSOR_NORMAL = zglfw.InputMode.cursor.ValueType().normal;
    pub const CURSOR_HIDDEN = zglfw.InputMode.cursor.ValueType().hidden;
    pub const CURSOR_DISABLED = zglfw.InputMode.cursor.ValueType().disabled;
    pub const CURSOR_CAPTURED = zglfw.InputMode.cursor.ValueType().captured;

    pub fn init() void {
        zglfw.init() catch {
            std.debug.print("Error! failed to initialize zglfw for windowing!\n\n", .{});
            unreachable;
        };
        zglfw.windowHint(.client_api, .no_api);
    }
    pub fn create_window(width: u16, height: u16, title: [:0]const u8) *zglfw.Window {
        const window = zglfw.Window.create(width, height, title, null) catch {
            std.debug.print("Error! Could not create zglfw window!\n\n", .{});
            unreachable;
        };
        return window;
    }
    pub fn terminate() void {
        zglfw.terminate();
    }
    pub fn pollEvents() void {
        zglfw.pollEvents();
    }
    pub fn setCursorPos(window:*zglfw.Window,x:f64,y:f64) void {
        zglfw.setCursorPos(window,x,y);      
    }
    pub fn setInputMode(window:*zglfw.Window,mode:u32,mode_value:u32) void {
        zglfw.setInputMode(window,mode,mode_value);      
    }
};

pub export fn print_version() void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    stdout.print("Zirconium {s} Loaded\n", .{version}) catch unreachable;
    bw.flush() catch unreachable;
}
