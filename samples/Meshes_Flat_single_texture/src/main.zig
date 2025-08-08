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
        std.debug.print("{s}\n",.{path});
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit(); 
    const allocator = gpa.allocator();
    
    Zr.Windowing.init();
    defer Zr.Windowing.terminate();
    const window = Zr.Windowing.create_window(1280, 720, window_title);
    defer window.destroy();
    try window.setInputMode(Zr.Windowing.CURSOR, Zr.Windowing.CURSOR_DISABLED);
     


    var state = try Zr.init(allocator, window);
    defer Zr.deinit(allocator, state);

  
   //state.camera.position = .{3.0,2.0,3.0};
   //state.camera.pitch = -(3.14/4.0);
   //state.camera.yaw = -(3.14/2.0);

   while (!window.shouldClose() and window.getKey(.escape) != .press) {
       Zr.Windowing.pollEvents();
       const delta_time = (state.gctx.stats.delta_time);

       const cursor_pos = window.getCursorPos();
       state.camera.mouse_rotate(
           .{@floatCast(cursor_pos[0]),@floatCast(cursor_pos[1])});

       if(window.getKey(.w) == .press) {
           state.camera.translate( .{1,0,0} , delta_time);
       }
       if(window.getKey(.s) == .press) {
           state.camera.translate( .{-1,0,0} , delta_time);
       }
       if(window.getKey(.d) == .press) {
           state.camera.translate( .{0,1,0} , delta_time);
       }
       if(window.getKey(.a) == .press) {
           state.camera.translate( .{0,-1,0} , delta_time);
       }
       if(window.getKey(.space) == .press) {
           state.camera.translate( .{0,0,1} , delta_time);
       }
       if(window.getKey(.left_shift) == .press) {
           state.camera.translate( .{0,0,-1} , delta_time);
       }

       Zr.draw(state);
   }
}

test "base test" {}
