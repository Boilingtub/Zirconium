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
     
    Zr.zstbi.init(allocator);
    defer Zr.zstbi.deinit();
    var image = try Zr.zstbi.Image.loadFromFile("./content/paint_abstract.jpg", 4);
    defer image.deinit();
    Zr.Force_image_MipMap_compatible(&image);

    const model = try Zr.load_model(allocator, "./content/ball_model.glb");
    defer model.free();

    const scene = Zr.Scene.create(
        base_shader,
        model.verticies.items,
        model.indices.items,
        image
    ); 
    

    const state = try Zr.init(allocator, window, &scene);
    defer Zr.free(allocator, state);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        Zr.Windowing.pollEvents();
        Zr.draw(state);
    }
}

test "base test" {}
