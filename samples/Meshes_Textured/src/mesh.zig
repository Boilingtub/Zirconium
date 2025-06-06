const zgltf = @import("zgltf");
const zobj = @import("zobj");
const std = @import("std");

pub const IndexType = u16;

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    texcoord: [2]f32,
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
    mesh: Model, 
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
    meshes_texcoords: *std.ArrayList([2]f32),
) void {
    meshes.append(.{
        .index_offset = @as(u32, @intCast(meshes_indices.items.len)),
        .vertex_offset = @as(i32, @intCast(meshes_positions.items.len)),
        .num_indices = @as(u32, @intCast(mesh.indices.len)),
        .num_vertices = @as(u32, @intCast(mesh.positions.len)),
    }) catch unreachable;
    
    meshes_indices.appendSlice(mesh.indices) catch unreachable;
    meshes_positions.appendSlice(mesh.positions) catch unreachable;
    meshes_normals.appendSlice(mesh.normals) catch unreachable;
    meshes_texcoords.appendSlice(mesh.texcoords) catch unreachable;
}

pub const Model = struct {
    positions: [][3]f32,
    normals: [][3]f32,
    texcoords: [][2]f32,
    indices: []IndexType,

    pub fn print(self:Model) void {
        std.debug.print("positions:\n", .{});
        for (self.positions) |item| {
            std.debug.print("{d}\n",.{item});
        }
        std.debug.print("indices:\n", .{});
        for (self.indices) |item| {
            std.debug.print("{d},",.{item});
        }
        std.debug.print(":normals\n", .{});
        for (self.normals) |item| {
            std.debug.print("{d},",.{item});
        }
        std.debug.print("texcoords:\n", .{});
        for (self.texcoords) |item| {
            std.debug.print("{d},",.{item});
        }
    }
};

//pub fn load_obj_file(allocator: std.mem.Allocator, path: []const u8,) !Model {}

pub fn load_gltf_file(
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

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var out_indices = std.ArrayList(IndexType).init(arena);
    var out_positions = std.ArrayList([3]f32).init(arena);
    var out_normals = std.ArrayList([3]f32).init(arena);
    var out_texcoords = std.ArrayList([2]f32).init(arena);

    const mesh = gltf.data.meshes.items[0];
    for (mesh.primitives.items) |primitive| {
        {
            const indices_idx = primitive.indices.?;
            const accessor = gltf.data.accessors.items[indices_idx];
            var iter = accessor.iterator(IndexType, &gltf, gltf.glb_binary.?);
            while(iter.next()) |v| {
                for (v) |a| {
                    try out_indices.append(a);
                }
            }
        }
        for (primitive.attributes.items) |attribute| {
            switch (attribute) {
                .position => |idx| {
                    const accessor = gltf.data.accessors.items[idx];
                    var iter = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                    while(iter.next()) |v| {
                        try out_positions.append(.{ v[0], v[1], v[2] });
                    }
                },
                .texcoord => |idx| {
                    const accessor = gltf.data.accessors.items[idx];
                    var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                    var i: u32 = 0;
                    while (it.next()) |v| : (i += 1) {
                        try out_texcoords.append(.{ v[0], v[1]});
                    }
                },
                .normal => |idx| {
                    const accessor = gltf.data.accessors.items[idx];
                    var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
                    var i: u32 = 0;
                    while (it.next()) |v| : (i += 1) {
                        try out_normals.append(.{ v[0], v[1], v[2]});
                    }
                },
                else => {}
            }
        }
    }
    return Model{
        .indices = out_indices.items[0..],
        .positions = out_positions.items[0..],
        .normals = out_normals.items[0..],
        .texcoords = out_texcoords.items[0..],
    };
}



pub const Primitive = struct {
    pub fn plane(allocator: std.mem.Allocator) !Model {
       return load_primitive(allocator,primitive_plane.len, &primitive_plane);
    }
    pub fn cube(allocator: std.mem.Allocator) !Model {
       return load_primitive(allocator,primitive_cube.len, &primitive_cube);
    }
    pub fn load_primitive(
        allocator: std.mem.Allocator, 
        vertex_count:usize, 
        data:[*]const Vertex) !Model {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const out_indices: [0]u16 = .{};
        var out_positions = try std.ArrayList([3]f32).initCapacity(arena,vertex_count);
        var out_normals = try std.ArrayList([3]f32).initCapacity(arena,vertex_count);
        var out_texcoords = try std.ArrayList([2]f32).initCapacity(arena,vertex_count);

        for(0..vertex_count)|v| {
            try out_positions.append(data[v].position);
            try out_normals.append(data[v].normal);
            try out_texcoords.append(data[v].texcoord);
        }
        return Model {
            .positions = out_positions.items[0..],
            .normals = out_normals.items[0..],
            .texcoords = out_texcoords.items[0..],
            .indices = out_indices[0..],
        };
    }
};
const primitive_plane: [6]Vertex = .{
    .{.position = .{-1, -1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}},
    .{.position = .{1, -1, -1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 1.0}},
    .{.position = .{1, -1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},
    .{.position = .{1, -1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},
    .{.position = .{-1, -1,  1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 0.0}},
    .{.position = .{-1, -1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}},
};
const primitive_cube : [36]Vertex = .{
   .{.position = .{-1, -1, -1 },.normal = .{0.0, 0.0, 0.0},.texcoord = .{0.0, 0.0}},
   .{.position = .{1, -1, -1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{  1.0, 0.0}},   
   .{.position = .{ 1,  1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 1.0, 1.0}},
   .{.position = .{1,  1, -1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 1.0}},
   .{.position = .{-1,  1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}},
   .{.position = .{-1, -1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 0.0}},

   .{.position = .{-1, -1,  1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 0.0}},
   .{.position = .{1, -1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},
   .{.position = .{1,  1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 1.0}},
   .{.position = .{1,  1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 1.0}},
   .{.position = .{-1,  1,  1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}},
   .{.position = .{-1, -1,  1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 0.0}},

   .{.position = .{-1,  1,  1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 1.0, 0.0}},
   .{.position = .{-1,  1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 1.0, 1.0}},
   .{.position = .{-1, -1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}},
   .{.position = .{-1, -1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}},
   .{.position = .{-1, -1,  1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 0.0}},
   .{.position = .{-1,  1,  1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 1.0, 0.0}},

   .{.position = .{1,  1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},
   .{.position = .{1,  1, -1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 1.0}},
   .{.position = .{1, -1, -1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{0.0, 1.0}},
   .{.position = .{1, -1, -1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{0.0, 1.0}},
   .{.position = .{1, -1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{0.0, 0.0}},
   .{.position = .{1,  1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},

   .{.position = .{-1, -1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}},
   .{.position = .{1, -1, -1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 1.0}},
   .{.position = .{1, -1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},
   .{.position = .{1, -1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},
   .{.position = .{-1, -1,  1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 0.0}},
   .{.position = .{-1, -1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}},

   .{.position = .{ -1,  1, -1},.normal = .{0.0, 0.0, 0.0},.texcoord = .{  0.0, 1.0}},
   .{.position = .{1,  1, -1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 1.0}},
   .{.position = .{1,  1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},
   .{.position = .{1,  1,  1, },.normal = .{0.0, 0.0, 0.0},.texcoord = .{1.0, 0.0}},
   .{.position = .{ -1,  1,  1},.normal = .{0.0, 0.0, 0.0},.texcoord = .{  0.0, 0.0}},
   .{.position = .{-1,  1, -1,},.normal = .{0.0, 0.0, 0.0},.texcoord = .{ 0.0, 1.0}}
};


