const zgltf = @import("zgltf");
const std = @import("std");

pub const IndexType = u16;

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    texcoord: [2]f32,
    pub fn empty() Vertex {
        return Vertex {
            .position = .{0,0,0},
            .normal = .{0,0,0},
            .texcoord = .{0.0,0.0}
        };
    }
};

pub const Mesh = struct {
    index_offset: u32,
    vertex_offset: i32,
    num_indices: u32,
    num_vertices: u32,
};

pub const Drawable = struct {
    mesh_index: u32,
    texture_index: u32,
    position: [3]f32,
    basecolor_roughness: [4]f32,
};

pub fn appendMesh(
    allocator: std.mem.Allocator,
    model: Model, 
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_vertices: *std.ArrayList(Vertex),
) void {
    meshes.append(allocator, .{
        .index_offset = @as(u32, @intCast(meshes_indices.items.len)),
        .vertex_offset = @as(i32, @intCast(meshes_vertices.items.len)),
        .num_indices = @as(u32, @intCast(model.indices.len)),
        .num_vertices = @as(u32, @intCast(model.vertices.len)),
    }) catch unreachable;
    meshes_indices.appendSlice(allocator, model.indices) catch unreachable;
    meshes_vertices.appendSlice(allocator, model.vertices) catch unreachable;
}

pub const Model = struct {
    vertices: []const Vertex, 
    indices: []const IndexType,

    pub fn print(self:Model) void {
        std.debug.print("position \t normal \t texcoord\n", .{});
        for (self.vertices) |i| {
            std.debug.print("{d} \t {d} \t {d}\n",
                .{i.position, i.normal, i.texcoord});
        }
        std.debug.print("indices\n",.{});
        for (self.indices) |i| {
            std.debug.print("{d}, ", .{i});
        }
        std.debug.print("\n", .{});
    }
    pub fn deinit(self:*Model,allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
    } 
};

//pub fn load_obj_file(allocator: std.mem.Allocator, path: []const u8,) !Model {}

pub fn load_gltf_file(
    allocator: std.mem.Allocator,
    path: []const u8) !Model {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    
    const buf = std.fs.cwd().readFileAllocOptions(
        arena,
        path,
        512_000,
        null,
        std.mem.Alignment.@"4",
        null
    ) catch unreachable;
    defer arena.free(buf);
    var gltf = zgltf.Gltf.init(arena);
    defer gltf.deinit();

    gltf.parse(buf) catch unreachable;

    var out_indices = try std.ArrayList(IndexType).initCapacity(arena,4);
    var out_positions = try std.ArrayList([3]f32).initCapacity(arena,4);
    var out_normals = try std.ArrayList([3]f32).initCapacity(arena,4);
    var out_texcoords = try std.ArrayList([2]f32).initCapacity(arena,4);

    const mesh = gltf.data.meshes[0];
    for (mesh.primitives) |primitive| {
        {
            const indices_idx = primitive.indices.?;
            const accessor = gltf.data.accessors[indices_idx];
            var iter = accessor.iterator(IndexType, &gltf, gltf.glb_binary.?);
            while(iter.next()) |v| {
                for (v) |a| {
                    try out_indices.append(arena,a);
                }
            }
        }
        for (primitive.attributes) |attribute| {
            switch (attribute) {
                .position => |idx| {
                    const accessor = gltf.data.accessors[idx];
                    var iter = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                    while(iter.next()) |v| {
                        try out_positions.append(arena, .{ v[0], v[1], v[2] });
                    }
                },
                .texcoord => |idx| {
                    const accessor = gltf.data.accessors[idx];
                    var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                    var i: u32 = 0;
                    while (it.next()) |v| : (i += 1) {
                        try out_texcoords.append(arena, .{ v[0], v[1]});
                    }
                },
                .normal => |idx| {
                    const accessor = gltf.data.accessors[idx];
                    var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                    var i: u32 = 0;
                    while (it.next()) |v| : (i += 1) {
                        try out_normals.append(arena, .{ v[0], v[1], v[2]});
                    }
                },
                else => {}
            }
        }
    }

    var out_vertices = try std.ArrayList(Vertex).initCapacity(
        arena,out_positions.items.len
    );
    //defer out_vertices.deinit();
    out_vertices.resize(arena, out_positions.items.len) catch unreachable;
    for (0..out_positions.items.len) |i| {
        out_vertices.items[i].position = out_positions.items[i];
        out_vertices.items[i].normal = out_normals.items[i];
        out_vertices.items[i].texcoord = out_texcoords.items[i];
    }

    return Model{
        .indices = out_indices.items,
        .vertices = out_vertices.items,
    };
}

pub const primitive_plane = Model {
    .vertices = &.{
        .{.position = .{-1, -1, -1}, .normal = .{0.0, 0.0, 0.0}, .texcoord = .{0.0, 1.0}},
        .{.position = .{ 1, -1, -1}, .normal = .{0.0, 0.0, 0.0}, .texcoord = .{1.0, 1.0}},
        .{.position = .{ 1, -1,  1}, .normal = .{0.0, 0.0, 0.0}, .texcoord = .{1.0, 0.0}},
        .{.position = .{-1, -1,  1}, .normal = .{0.0, 0.0, 0.0}, .texcoord = .{0.0, 0.0}}
    },
    .indices = &.{0, 3, 2, 0, 2, 1,}
};

pub const primitive_cube = Model {
    .vertices = &.{
        // Back face (z = -1, normal = (0,0,-1))
        .{.position = .{-1, -1, -1}, .normal = .{0.0, 0.0, -1.0}, .texcoord = .{0.0, 0.0}},
        .{.position = .{-1,  1, -1}, .normal = .{0.0, 0.0, -1.0}, .texcoord = .{0.0, 1.0}},
        .{.position = .{ 1,  1, -1}, .normal = .{0.0, 0.0, -1.0}, .texcoord = .{1.0, 1.0}},
        .{.position = .{ 1, -1, -1}, .normal = .{0.0, 0.0, -1.0}, .texcoord = .{1.0, 0.0}},
    
        // Front face (z = 1, normal = (0,0,1))
        .{.position = .{-1, -1,  1}, .normal = .{0.0, 0.0, 1.0}, .texcoord = .{0.0, 0.0}},
        .{.position = .{ 1, -1,  1}, .normal = .{0.0, 0.0, 1.0}, .texcoord = .{1.0, 0.0}},
        .{.position = .{ 1,  1,  1}, .normal = .{0.0, 0.0, 1.0}, .texcoord = .{1.0, 1.0}},
        .{.position = .{-1,  1,  1}, .normal = .{0.0, 0.0, 1.0}, .texcoord = .{0.0, 1.0}},
    
        // Left face (x = -1, normal = (-1,0,0))
        .{.position = .{-1, -1, -1}, .normal = .{-1.0, 0.0, 0.0}, .texcoord = .{0.0, 1.0}},
        .{.position = .{-1,  1, -1}, .normal = .{-1.0, 0.0, 0.0}, .texcoord = .{1.0, 1.0}},
        .{.position = .{-1,  1,  1}, .normal = .{-1.0, 0.0, 0.0}, .texcoord = .{1.0, 0.0}},
        .{.position = .{-1, -1,  1}, .normal = .{-1.0, 0.0, 0.0}, .texcoord = .{0.0, 0.0}},
    
        // Right face (x = 1, normal = (1,0,0))
        .{.position = .{1, -1, -1}, .normal = .{1.0, 0.0, 0.0}, .texcoord = .{0.0, 1.0}},
        .{.position = .{1, -1,  1}, .normal = .{1.0, 0.0, 0.0}, .texcoord = .{0.0, 0.0}},
        .{.position = .{1,  1,  1}, .normal = .{1.0, 0.0, 0.0}, .texcoord = .{1.0, 0.0}},
        .{.position = .{1,  1, -1}, .normal = .{1.0, 0.0, 0.0}, .texcoord = .{1.0, 1.0}},
    
        // Bottom face (y = -1, normal = (0,-1,0))
        .{.position = .{-1, -1, -1}, .normal = .{0.0, -1.0, 0.0}, .texcoord = .{0.0, 1.0}},
        .{.position = .{ 1, -1, -1}, .normal = .{0.0, -1.0, 0.0}, .texcoord = .{1.0, 1.0}},
        .{.position = .{ 1, -1,  1}, .normal = .{0.0, -1.0, 0.0}, .texcoord = .{1.0, 0.0}},
        .{.position = .{-1, -1,  1}, .normal = .{0.0, -1.0, 0.0}, .texcoord = .{0.0, 0.0}},
    
        // Top face (y = 1, normal = (0,1,0))
        .{.position = .{-1,  1, -1}, .normal = .{0.0, 1.0, 0.0}, .texcoord = .{0.0, 1.0}},
        .{.position = .{ 1,  1, -1}, .normal = .{0.0, 1.0, 0.0}, .texcoord = .{1.0, 1.0}},
        .{.position = .{ 1,  1,  1}, .normal = .{0.0, 1.0, 0.0}, .texcoord = .{1.0, 0.0}},
        .{.position = .{-1,  1,  1}, .normal = .{0.0, 1.0, 0.0}, .texcoord = .{0.0, 0.0}},
    },
    .indices = &.{
        // Back face
        0, 1, 2,  0, 2, 3,
        // Front face
        4, 5, 6,  4, 6, 7,
        // Left face
        8, 9, 10, 8, 10, 11,
        // Right face
        12, 13, 14, 12, 14, 15,
        // Bottom face
        16, 17, 18, 16, 18, 19,
        // Top face
        20, 21, 22, 20, 22, 23,
        // Back face
        0, 1, 2,  0, 2, 3,
        // Front face
        4, 5, 6,  4, 6, 7,
        // Left face
        8, 9, 10, 8, 10, 11,
        // Right face
        12, 13, 14, 12, 14, 15,
        // Bottom face
        16, 17, 18, 16, 18, 19,
        // Top face
        20, 21, 22, 20, 22, 23
    },
 };
