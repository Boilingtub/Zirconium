const std = @import("std");
const Zr = @import("Zirconium");
const window_title = "Zirconium : textured_model (wgpu)";

const base_shader = @embedFile("./shaders/base.wgsl");

pub fn main() !void {
    std.debug.print("{s}\n", .{window_title});
    Zr.print_version();
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    std.posix.chdir(path) catch {};
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit(); 
    const allocator = gpa.allocator();
    
    Zr.Windowing.init();
    defer Zr.Windowing.terminate();
    const window = Zr.Windowing.create_window(1280, 720, window_title);
    defer window.destroy();
     

    Zr.image.init(allocator);
    defer Zr.image.deinit();
    var img = try Zr.image.load("./content/lava_solidified.jpg", 4);
    defer img.deinit();

    Zr.image.Force_image_MipMap_compatible(&img);

    var model = try Zr.model.Primitive.cube(allocator);
    defer model.free();

    var scene = Zr.Scene.create(
        base_shader,
        model.verticies.items,
        model.indices.items,
        img
    ); 
    

    var state = try Zr.init(allocator, window, &scene);
    defer Zr.free(allocator, state);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        Zr.Windowing.pollEvents();
        var recreate_state :bool = false;

        if(window.getKey( .one ) == .press) {
            img = try Zr.image.load("./content/paint_abstract.jpg", 4);
            recreate_state =true;
        }
        if(window.getKey( .two ) == .press) {
            img = try Zr.image.load("./content/dry_dusty_dirt.jpg", 4);
            recreate_state =true;
        }
        if(window.getKey( .three ) == .press) {
            img = try Zr.image.load("./content/lava_solidified.jpg", 4);
            recreate_state =true;
        }
        if(window.getKey( .four ) == .press) {
            img = try Zr.image.load("./content/face_img.jpg", 4);
            recreate_state =true;
        }
        if(window.getKey( .q ) == .press) { 
            model = try Zr.model.load_file(allocator, "./content/ball_model.glb");
            recreate_state =true;
        }
        if(window.getKey( .w ) == .press) {
            model = try Zr.model.Primitive.cube(allocator);
            recreate_state =true;
        }
        if(window.getKey( .e ) == .press) {
            model = try Zr.model.load_file(allocator, "./content/chair.glb");
            recreate_state =true;
        }

        if(recreate_state) {
            Zr.image.Force_image_MipMap_compatible(&img);

            scene = Zr.Scene.create(
                base_shader,
                model.verticies.items,
                model.indices.items,
                img
            ); 
            state = try Zr.init(allocator, window, &scene);
        }

        Zr.draw(state);
    }
}

test "base test" {}
