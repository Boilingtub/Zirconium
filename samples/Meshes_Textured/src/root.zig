const version = "0.0.5";
const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
pub const zm = @import("zmath");
pub const model = @import("model");
pub const zimage = @import("image");
pub const Camera = @import("camera.zig").Camera;

pub const zstbi = zimage.zstbi;
pub const Vertex = model.Vertex;
pub const Mesh = model.Mesh;
pub const Drawable = model.Drawable;

const base_shader = @embedFile("./shaders/base.wgsl");

const FrameUniforms = struct {
    world_to_clip: zm.Mat,
    camera_position: [3]f32,
};
const DrawUniforms = struct {
    object_to_world: zm.Mat,
    basecolor_roughness: [4]f32,
    mip_level: f32,
};

fn initScene(
    allocator: std.mem.Allocator,
    drawables: *std.ArrayList(Drawable),
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(model.IndexType),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
) void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        const mesh = model.Primitive.cube(arena) catch unreachable;
        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 9, 1, 0 },
            .basecolor_roughness = .{ 1.0, 0.0, 0.0, 0.0 },
        }) catch unreachable;

        model.appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }

    {
        const mesh = model.Primitive.plane(arena) catch unreachable;
        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 0, -1, 0 },
            .basecolor_roughness = .{ 0.0, 1.0, 0.0, 0.0 },
        }) catch unreachable;
        model.appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    {
        const mesh = model.load_file(arena, "./content/ball_model.glb") catch unreachable ;
        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 6, 1, 0 },
            .basecolor_roughness = .{ 0.0, 0.0, 1.0, 0.6 },
        }) catch unreachable;
        model.appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    {
        const mesh = model.load_file(arena, "./content/chair.glb") catch unreachable;
        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 3, 1, 0 },
            .basecolor_roughness = .{ 0.5, 0.7, 0.2, 0.6 },
        }) catch unreachable;
        model.appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
}

pub const State = struct {
    camera: Camera,

    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle = .{},

    frame_bind_group: zgpu.BindGroupHandle,
    draw_bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,

    meshes: std.ArrayList(Mesh),
    drawables: std.ArrayList(Drawable),

    texture: zgpu.TextureHandle,
    texture_view: zgpu.TextureViewHandle,
    sampler: zgpu.SamplerHandle,

    mip_level: f32 = 0,
};

pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !*State {
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

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    zimage.init(arena);
    var texture_image = try zimage.load("./content/lava_solidified.jpg", 4);
    zimage.Force_image_MipMap_compatible(&texture_image);

    const texture = gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true},
        .size = .{
            .width = texture_image.width,
            .height = texture_image.height,
            .depth_or_array_layers = 1,
        },
        .format = zgpu.imageInfoToTextureFormat(
            texture_image.num_components,
            texture_image.bytes_per_component,
            texture_image.is_hdr
        ),
        .mip_level_count = std.math.log2_int(
            u32, 
            @max(texture_image.width, texture_image.height)) + 1
    });

    const texture_view = gctx.createTextureView(texture, .{});

    gctx.queue.writeTexture(
        .{
            .texture = gctx.lookupResource(texture).?
        }, 
        .{ 
            .bytes_per_row = texture_image.bytes_per_row,
            .rows_per_image = texture_image.height, 
        }, 
        .{ 
            .width = texture_image.width,
            .height = texture_image.height
        },
        u8,
        texture_image.data,
    );

    const sampler = gctx.createSampler(.{});
    const depth = createDepthTexture(gctx);
    //Create bind group layout needed for render pipeline.
    const frame_bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment=true }, .uniform, true, 0),
    });
    defer gctx.releaseResource(frame_bind_group_layout);
    //create frame_bind_group from frame_bind_group_layout;
    const frame_bind_group = gctx.createBindGroup(frame_bind_group_layout,&.{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(FrameUniforms),
        },
    });

    //Create bind group layout needed for render pipeline.
    const draw_bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment=true }, .uniform, true, 0),
        zgpu.textureEntry(1, .{.fragment = true}, .float, .tvdim_2d, false),
        zgpu.samplerEntry(2, .{.fragment = true} , .filtering),
    });
    defer gctx.releaseResource(draw_bind_group_layout);
    //create draw_bind_group from draw_bind_group_layout;
    const draw_bind_group = gctx.createBindGroup(draw_bind_group_layout,&.{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(DrawUniforms),
        },
        .{
            .binding = 1, .texture_view_handle = texture_view
        },
        .{
            .binding = 2, .sampler_handle = sampler
        }

    });
    var drawables = std.ArrayList(Drawable).init(allocator);
    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(model.IndexType).init(arena);
    var meshes_positions = std.ArrayList([3]f32).init(arena);
    var meshes_normals = std.ArrayList([3]f32).init(arena);
    initScene(allocator, &drawables, &meshes,
              &meshes_indices, &meshes_positions,
              &meshes_normals);
    const total_num_vertices = @as(u32, @intCast(meshes_positions.items.len));
    const total_num_indices = @as(u32, @intCast(meshes_indices.items.len));

    // Create a vertex buffer.
    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = total_num_vertices * @sizeOf(Vertex),
    });
    {
        var vertex_data = std.ArrayList(Vertex).init(arena);
        defer vertex_data.deinit();
        vertex_data.resize(total_num_vertices) catch unreachable;

        for (meshes_positions.items, 0..) |_, i| {
            vertex_data.items[i].position = meshes_positions.items[i];
            vertex_data.items[i].normal = meshes_normals.items[i];
        }
        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?,
                               0, Vertex, vertex_data.items);
    }

    // Create an index buffer.
    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = total_num_indices * @sizeOf(model.IndexType),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?,
                           0, model.IndexType, meshes_indices.items);


    const state = try allocator.create(State);
    state.* = .{
        .camera = Camera {},
        .gctx = gctx,
        .frame_bind_group = frame_bind_group,
        .draw_bind_group = draw_bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
        .meshes = meshes,
        .drawables = drawables,
        .texture = texture,
        .texture_view = texture_view,
        .sampler = sampler,
    };
    
    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        gctx.generateMipmaps(allocator, encoder, state.texture);
         
        break :commands encoder.finish(null);
    };
    defer commands.release();
    gctx.submit(&.{commands});
    // create render pipeline 
    const pipeline_layout = gctx.createPipelineLayout(&.{
        frame_bind_group_layout,
        draw_bind_group_layout,
    });
    defer gctx.releaseResource(pipeline_layout);

    const pipeline = pipeline: 
    {
        const vs_module = zgpu.createWgslShaderModule(gctx.device, base_shader, "vs");
        defer vs_module.release();

        const color_targets = [_]zgpu.wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ 
                .format = .float32x3, .offset = @offsetOf(Vertex,"normal"), 
                .shader_location = 1 
            },
            .{ 
                .format = .float32x2, .offset = @offsetOf(Vertex,"texcoord"),
                .shader_location = 2
            },
        };

        const vertex_buffers = [_]zgpu.wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(Vertex),            
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        const pipeline_descriptor = zgpu.wgpu.RenderPipelineDescriptor{ 
            .vertex = .{
                .module = vs_module,
                .entry_point = "vs_main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            }, 
            .primitive = .{
                .front_face = .cw,
                .cull_mode = .none,
                .topology = .triangle_list,
            }, 
            .depth_stencil = &.{
                .format = .depth32_float,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .fragment = &.{
                .module = vs_module,
                .entry_point = "fs_main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            } 
        };
        break :pipeline gctx.createRenderPipeline(
            pipeline_layout,
            pipeline_descriptor,
        );
    };

    state.pipeline = pipeline;
    
        return state;
}


pub fn deinit(allocator: std.mem.Allocator, state: *State) void {
    state.gctx.destroy(allocator);
    state.meshes.deinit();
    state.drawables.deinit();
    allocator.destroy(state);
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
        //.mip_level_count = 1,
        .sample_count = 1,
    });
    const view = gctx.createTextureView(texture, .{});
    return .{ .texture = texture, .view = view };
}

pub fn draw(state: *State) void {
    const gctx = state.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;
    //const t = @as(f32, @floatCast(gctx.stats.time));

    const cam_world_to_view = zm.lookToLh(
        zm.loadArr3(state.camera.position),
        zm.loadArr3(state.camera.forward),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(
        0.25 * std.math.pi, @as(f32, @floatFromInt(fb_width)) /
        @as(f32, @floatFromInt(fb_height)), 0.01, 100.0
    );
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);
    //const aspect_ratio = @as(
    //    f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height)
    //);


    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        pass: {
            const vb_info = gctx.lookupResourceInfo(state.vertex_buffer) orelse break :pass;
            const ib_info = gctx.lookupResourceInfo(state.index_buffer) orelse break :pass;
            const pipeline = gctx.lookupResource(state.pipeline) orelse break :pass;

            const frame_bind_group = gctx.lookupResource(state.frame_bind_group) orelse break :pass;
            const draw_bind_group = gctx.lookupResource(state.draw_bind_group) orelse break :pass;
            const depth_view = gctx.lookupResource(state.depth_texture_view) orelse break :pass;
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
            pass.setIndexBuffer(
                ib_info.gpuobj.?,
                if (model.IndexType == u16) .uint16 else .uint32,
                0,
                ib_info.size);
            pass.setPipeline(pipeline);
            // Update "world to clip" (camera) xform
            {   
                const mem = gctx.uniformsAllocate(FrameUniforms, 1);
                mem.slice[0].world_to_clip = zm.transpose(cam_world_to_clip);
                mem.slice[0].camera_position = state.camera.position;
                pass.setBindGroup(0, frame_bind_group, &.{mem.offset});
            }
            for (state.drawables.items) |drawable| {
                //Update "object to world" xform 
                const object_to_world = zm.translationV(zm.loadArr3(drawable.position));
                const mem = gctx.uniformsAllocate(DrawUniforms,1);
                mem.slice[0].object_to_world = zm.transpose(object_to_world);
                mem.slice[0].basecolor_roughness = drawable.basecolor_roughness;
                mem.slice[0].mip_level = state.mip_level;

                pass.setBindGroup(1, draw_bind_group, &.{mem.offset});

                //Draw
                if(state.meshes.items[drawable.mesh_index].num_indices == 0)
                    pass.draw(
                        state.meshes.items[drawable.mesh_index].num_vertices,
                        1,
                        @intCast(state.meshes.items[drawable.mesh_index].vertex_offset),
                        0,
                )
                else
                    pass.drawIndexed(
                        state.meshes.items[drawable.mesh_index].num_indices,
                        1,
                        state.meshes.items[drawable.mesh_index].index_offset,
                        state.meshes.items[drawable.mesh_index].vertex_offset,
                        0,
                    );
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


pub export fn print_version() void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    stdout.print("Zirconium {s} Loaded\n", .{version}) catch unreachable;
    bw.flush() catch unreachable;
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
