const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zm = @import("zmath");
const zgltf = @import("zgltf");

pub export const version = "0.0.2";

pub const Vertex = struct {
    position: [3]f32,
    color: [4]f32,
};

pub const Scene = struct {
    vs: [*:0]const u8,
    fs: [*:0]const u8,
    verticies: []const Vertex,
    indices: []const u16, 
    pub fn create(vs: [*:0]const u8, fs: [*:0]const u8,
    verticies: []const Vertex, indices: []const u16) Scene {
        if(indices.len == 0) 
            std.debug.print("WARNING! indices_length = 0\n", .{});
        return Scene {
            .vs = vs,
            .fs = fs,
            .verticies = verticies,
            .indices = indices,
        };  
    }
};

pub const State = struct {
    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,
};

pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window, scene: *const Scene) !State {
    const gctx = try zgpu.GraphicsContext.create(allocator, .{
        .window = window,
        .fn_getTime = @ptrCast(&zglfw.getTime),
        .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
        .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
        .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
        .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
        .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
        .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
        .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
    }, .{});
    errdefer gctx.destroy(allocator);

    //Create bind group layout needed for render pipeline.
    const bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true }, .uniform, true, 0),
    });
    defer gctx.releaseResource(bind_group_layout);

    const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});
    defer gctx.releaseResource(pipeline_layout);

    const pipeline = pipeline: {
        const vs_module = zgpu.createWgslShaderModule(gctx.device, scene.vs, "vs");
        defer vs_module.release();
        const fs_module = zgpu.createWgslShaderModule(gctx.device, scene.fs, "fs");
        defer fs_module.release();

        const color_targets = [_]zgpu.wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x4, .offset = @offsetOf(Vertex, "color"), .shader_location = 1 },
        };

        const vertex_buffers = [_]zgpu.wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        const pipeline_descriptor = zgpu.wgpu.RenderPipelineDescriptor{ .vertex = zgpu.wgpu.VertexState{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        }, .primitive = zgpu.wgpu.PrimitiveState{
            .front_face = .ccw,
            .cull_mode = .back,
            .topology = .triangle_list,
        }, .depth_stencil = &zgpu.wgpu.DepthStencilState{
            .format = .depth32_float,
            .depth_write_enabled = true,
            .depth_compare = .less,
        }, .fragment = &zgpu.wgpu.FragmentState{
            .module = fs_module,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        } };
        break :pipeline gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    };

    const bind_group = gctx.createBindGroup(bind_group_layout, &.{.{ .binding = 0, .buffer_handle = gctx.uniforms.buffer, .offset = 0, .size = @sizeOf(zm.Mat) }});

    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = scene.verticies.len * @sizeOf(Vertex),
    });
    gctx.queue.writeBuffer(
        gctx.lookupResource(vertex_buffer).?,
        0,
        Vertex,
        scene.verticies,
    );

    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = scene.indices.len * @sizeOf(u16),
    });
    gctx.queue.writeBuffer(
        gctx.lookupResource(index_buffer).?,
        0,
        u16,
        scene.indices,
    );

    const depth = createDepthTexture(gctx);

    return State{
        .gctx = gctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
    };
}

pub fn deinit(allocator: std.mem.Allocator, state: *State) void {
    state.gctx.destroy(allocator);
    state.* = undefined;
}

fn createDepthTexture(gctx: *zgpu.GraphicsContext) struct {
    texture: zgpu.TextureHandle,
    view: zgpu.TextureViewHandle,
} {
    const texture = gctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = gctx.swapchain_descriptor.width,
            .height = gctx.swapchain_descriptor.height,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const view = gctx.createTextureView(texture, .{});
    return .{ .texture = texture, .view = view };
}

pub fn draw(state: *State) void {
    const gctx = state.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;
    const t = @as(f32, @floatCast(gctx.stats.time));

    const cam_world_to_view = zm.lookAtLh(
        zm.f32x4(3.0, 3.0, -3.0, 1.0),
        zm.f32x4(0.0, 0.0, 0.0, 1.0),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(0.25 * std.math.pi, @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height)), 0.01, 100.0);
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        pass: {
            const vb_info = gctx.lookupResourceInfo(state.vertex_buffer) orelse break :pass;
            const ib_info = gctx.lookupResourceInfo(state.index_buffer) orelse break :pass;
            const pipeline = gctx.lookupResource(state.pipeline) orelse break :pass;
            const bind_group = gctx.lookupResource(state.bind_group) orelse break :pass;
            const depth_view = gctx.lookupResource(state.depth_texture_view) orelse break :pass;
            
            const index_count:u32 = @intCast(ib_info.size / @sizeOf(u16));
            const vertex_count:u32 = @intCast(vb_info.size / @sizeOf(Vertex));
            
            const color_attachments = [_]zgpu.wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .clear,
                .store_op = .store,
            }};
            const depth_attachment = zgpu.wgpu.RenderPassDepthStencilAttachment{
                .view = depth_view,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_clear_value = 1.0,
            };
            const render_pass_info = zgpu.wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
                .depth_stencil_attachment = &depth_attachment,
            };

            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
            pass.setIndexBuffer(ib_info.gpuobj.?, .uint16, 0, ib_info.size);
            pass.setPipeline(pipeline);

            // Draw triangle 1.
            {
                const object_to_world = zm.mul(zm.mul(zm.rotationY(t), zm.translation(-2.0, 0.0, 0.0)), zm.scaling(0.5,0.5,0.5));

                const object_to_clip = zm.mul(object_to_world, cam_world_to_clip);

                const mem = gctx.uniformsAllocate(zm.Mat, 1);
                mem.slice[0] = zm.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});

                if(index_count == 0)
                    pass.draw(vertex_count, 1, 0, 0)
                else
                    pass.drawIndexed(index_count, 1, 0, 0, 0);
            }

            // Draw triangle 2.
            {
                const object_to_world = zm.mul(zm.mul(zm.rotationY(0.75 * t), zm.translation(2.0, 0.0, 0.0)),zm.scaling(0.5 , 0.5 , 0.5));

                const object_to_clip = zm.mul(object_to_world, cam_world_to_clip);

                const mem = gctx.uniformsAllocate(zm.Mat, 1);
                mem.slice[0] = zm.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});

                if(index_count == 0) 
                    pass.draw(vertex_count, 1, 0, 0)
                else
                    pass.drawIndexed(index_count, 1, 0, 0, 0);
            }
        }
        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});

    if (gctx.present() == .swap_chain_resized) {
        // Release old depth texture.
        gctx.releaseResource(state.depth_texture_view);
        gctx.destroyResource(state.depth_texture);
        // Create a new depth texture to match the new window size.
        const depth = createDepthTexture(gctx);
        state.depth_texture = depth.texture;
        state.depth_texture_view = depth.view;
    }
}

pub const Windowing = struct {
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

pub fn load_model(
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
                            .color = .{v[0], v[1], v[2], 1.0},
                        });
                    }
                },
                else => {}
            }
        }
    }
    return model;
}

pub export fn print_version() void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    stdout.print("Zirconium {s} Loaded\n", .{version}) catch unreachable;
    bw.flush() catch unreachable;
}
