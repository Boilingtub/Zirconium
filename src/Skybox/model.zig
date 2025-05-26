const zgltf = @import("zgltf");
const std = @import("std");

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    texcoord: [2]f32,
    tangent: [4]f32,
};

pub const Mesh = struct {
    index_offset: u32,
    vertex_offset: i32,
    num_indices: u32,
    num_vertices: u32,
};

pub const Model = struct {
    verticies: std.ArrayList(Vertex),
    indices: std.ArrayList(u16),
    pub fn create(allocator: std.mem.Allocator) !Model {
        const verticies = std.ArrayList(Vertex).init(allocator);
        const indices = std.ArrayList(u16).init(allocator);
        return Model {
            .verticies = verticies,
            .indices = indices,
        };
    }

    pub fn print(self:Model) void {
        std.debug.print("verticies:\n", .{});
        for (self.verticies.items) |item| {
            std.debug.print("[{d} {d}]\n",.{item.position,item.color});
        }
        std.debug.print("indices:\n", .{});
        for (self.indices.items) |item| {
            std.debug.print("{d},",.{item});
        }
    }

    pub fn free(self: Model) void {
        self.verticies.deinit();
        self.indices.deinit();
    }
};

pub fn load_file(
    allocator: std.mem.Allocator,
    path: []const u8) !Model {
    const buf = std.fs.cwd().readFileAllocOptions(
        allocator,
        path,
        512_000,
        null,
        4,
        null
    ) catch unreachable;
    defer allocator.free(buf);
    var gltf = zgltf.init(allocator);
    defer gltf.deinit();

    gltf.parse(buf) catch unreachable;
    var model = Model.create(allocator) catch unreachable;

    const mesh = gltf.data.meshes.items[0];
    for (mesh.primitives.items) |primitive| {
        {
            const indices_idx = primitive.indices.?;
            const accessor = gltf.data.accessors.items[indices_idx];
            var iter = accessor.iterator(u16, &gltf, gltf.glb_binary.?);
            while(iter.next()) |v| {
                for (v) |a| {
                    try model.indices.append(a);
                }
            }
        }
        for (primitive.attributes.items) |attribute| {
            switch (attribute) {
                .position => |idx| {
                    const accessor = gltf.data.accessors.items[idx];
                    var iter = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                    while(iter.next()) |v| {
                        try model.verticies.append(.{
                            .position = .{ v[0], v[1], v[2] },
                            .uv = .{0,0},
                        });
                    }
                },
                .texcoord => |idx| {
                    const accessor = gltf.data.accessors.items[idx];
                    var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                    var i: u32 = 0;
                    while (it.next()) |v| : (i += 1) {
                        model.verticies.items[i].uv = .{ v[0], v[1]};
                    }
                },
                else => {}
            }
        }
    }
    return model;
}

pub const Primitive = struct {
    pub fn cube(allocator: std.mem.Allocator) !Model {
        var model = try Model.create(allocator);
        for(primitive_cube) |v| {
            try model.verticies.append(v);
        }
        return model;
    }
};
const primitive_cube : [36]Vertex = .{
        .{.position = .{-1, -1, -1 }, .uv = .{0.0, 0.0}},
        .{.position = .{1, -1, -1, }, .uv = .{  1.0, 0.0}},
        .{.position = .{ 1,  1, -1,}, .uv = .{ 1.0, 1.0}},
        .{.position = .{1,  1, -1, }, .uv = .{1.0, 1.0}},
        .{.position = .{-1,  1, -1,}, .uv = .{ 0.0, 1.0}},
        .{.position = .{-1, -1, -1,}, .uv = .{ 0.0, 0.0}},

        .{.position = .{-1, -1,  1,}, .uv = .{ 0.0, 0.0}},
        .{.position = .{1, -1,  1, }, .uv = .{1.0, 0.0}},
        .{.position = .{1,  1,  1, }, .uv = .{1.0, 1.0}},
        .{.position = .{1,  1,  1, }, .uv = .{1.0, 1.0}},
        .{.position = .{-1,  1,  1,}, .uv = .{ 0.0, 1.0}},
        .{.position = .{-1, -1,  1,}, .uv = .{ 0.0, 0.0}},

        .{.position = .{-1,  1,  1,}, .uv = .{ 1.0, 0.0}},
        .{.position = .{-1,  1, -1,}, .uv = .{ 1.0, 1.0}},
        .{.position = .{-1, -1, -1,}, .uv = .{ 0.0, 1.0}},
        .{.position = .{-1, -1, -1,}, .uv = .{ 0.0, 1.0}},
        .{.position = .{-1, -1,  1,}, .uv = .{ 0.0, 0.0}},
        .{.position = .{-1,  1,  1,}, .uv = .{ 1.0, 0.0}},

        .{.position = .{1,  1,  1, }, .uv = .{1.0, 0.0}},
        .{.position = .{1,  1, -1, }, .uv = .{1.0, 1.0}},
        .{.position = .{1, -1, -1, }, .uv = .{0.0, 1.0}},
        .{.position = .{1, -1, -1, }, .uv = .{0.0, 1.0}},
        .{.position = .{1, -1,  1, }, .uv = .{0.0, 0.0}},
        .{.position = .{1,  1,  1, }, .uv = .{1.0, 0.0}},

        .{.position = .{-1, -1, -1,}, .uv = .{ 0.0, 1.0}},
        .{.position = .{1, -1, -1, }, .uv = .{1.0, 1.0}},
        .{.position = .{1, -1,  1, }, .uv = .{1.0, 0.0}},
        .{.position = .{1, -1,  1, }, .uv = .{1.0, 0.0}},
        .{.position = .{-1, -1,  1,}, .uv = .{ 0.0, 0.0}},
        .{.position = .{-1, -1, -1,}, .uv = .{ 0.0, 1.0}},

        .{.position = .{ -1,  1, -1}, .uv = .{  0.0, 1.0}},
        .{.position = .{1,  1, -1, }, .uv = .{1.0, 1.0}},
        .{.position = .{1,  1,  1, }, .uv = .{1.0, 0.0}},
        .{.position = .{1,  1,  1, }, .uv = .{1.0, 0.0}},
        .{.position = .{ -1,  1,  1}, .uv = .{  0.0, 0.0}},
        .{.position = .{-1,  1, -1,}, .uv = .{ 0.0, 1.0}}
};


