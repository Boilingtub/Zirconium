const std = @import("std");
const Zr = @import("Zirconium");
const window_title = "Zirconium : triangle (wgpu)";

const wgsl_vs =
\\  @group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;
\\  struct VertexOut {
\\      @builtin(position) position_clip: vec4<f32>,
\\      @location(0) color: vec3<f32>,
\\  }
\\  @vertex fn main(
\\      @location(0) position: vec3<f32>,
\\      @location(1) color: vec3<f32>,
\\  ) -> VertexOut {
\\      var output: VertexOut;
\\      output.position_clip = vec4(position, 1.0) * object_to_clip;
\\      output.color = color;
\\      return output;
\\  }
;
const wgsl_fs =
\\  @fragment fn main(
\\      @location(0) color: vec3<f32>,
\\  ) -> @location(0) vec4<f32> {
\\      return vec4(color, 1.0);
\\  }
// zig fmt: on
;

const vertex_data = [_]Zr.Vertex{
    .{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [3]f32{ 1.0, 0.0, 0.0 } },
    .{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [3]f32{ 0.0, 1.0, 0.0 } },
    .{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [3]f32{ 0.0, 0.0, 1.0 } },
};
const index_data = [_]u32{ 0, 1, 2 };

pub fn main() !void {
    std.debug.print("Running triangle.zig", .{});
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
    
    const scene = Zr.Scene.create(wgsl_vs,wgsl_fs,vertex_data[0..],index_data[0..]); 

    var state = try Zr.init(allocator, window, &scene);
    defer Zr.deinit(allocator, &state);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        Zr.Windowing.pollEvents();
        Zr.draw(&state);
    }
}

test "base test" {}
