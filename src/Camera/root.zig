const version = "0.0.4";
const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
pub const zm = @import("zmath");
pub const model = @import("model");
pub const image = @import("image");

pub const zstbi = image.zstbi;
const Vertex = model.Vertex;

pub const Uniforms = extern struct {
    object_to_clip: zm.Mat,
    aspect_ratio:f32,
    mip_level: f32,
};

pub const Scene = struct {
    shader: [*:0]const u8,
    verticies: []const Vertex,
    indices: []const u16, 
    texture_image: zstbi.Image,
    pub fn create(shader: [*:0]const u8,
    verticies: []const Vertex, indices: []const u16, texture_image: zstbi.Image) Scene {
        if(indices.len == 0) 
            std.debug.print("WARNING! indices_length = 0\n", .{});
        return Scene {
            .shader = shader,
            .verticies = verticies,
            .indices = indices,
            .texture_image = texture_image 
        };  
    }
};

pub const State = struct {
    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle = .{},
    bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,

    texture: zgpu.TextureHandle,
    texture_view: zgpu.TextureViewHandle,
    sampler: zgpu.SamplerHandle,

    mip_level:i32 = 0,
};

pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window, scene: *const Scene) !*State {
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

    //var arena_state = std.heap.ArenaAllocator.init(allocator);
    //defer arena_state.deinit();
    //const arena = arena_state.allocator();

    //Create bind group layout needed for render pipeline.
    const bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true }, .uniform, true, 0),
        zgpu.textureEntry(1, .{.fragment = true}, .float, .tvdim_2d, false),
        zgpu.samplerEntry(2, .{.fragment = true} , .filtering),
    });
    defer gctx.releaseResource(bind_group_layout);

    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true},
        .size = scene.verticies.len * @sizeOf(Vertex),
    });
    gctx.queue.writeBuffer(
        gctx.lookupResource(vertex_buffer).?,
        0,
        Vertex,
        scene.verticies[0..]
    );


    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = scene.indices.len * @sizeOf(u16),
    });
    gctx.queue.writeBuffer(
        gctx.lookupResource(index_buffer).?,
        0,
        u16,
        scene.indices[0..]
    );

    const texture = gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true},
        .size = .{
            .width = scene.texture_image.width,
            .height = scene.texture_image.height,
            .depth_or_array_layers = 1,
        },
        .format = zgpu.imageInfoToTextureFormat(
            scene.texture_image.num_components,
            scene.texture_image.bytes_per_component,
            scene.texture_image.is_hdr
        ),
        .mip_level_count = std.math.log2_int(
            u32, 
            @max(scene.texture_image.width, scene.texture_image.height)) + 1
    });

    const texture_view = gctx.createTextureView(texture, .{});

    gctx.queue.writeTexture(
        .{
            .texture = gctx.lookupResource(texture).?
        }, 
        .{ 
            .bytes_per_row = scene.texture_image.bytes_per_row,
            .rows_per_image = scene.texture_image.height, 
        }, 
        .{ 
            .width = scene.texture_image.width,
            .height = scene.texture_image.height
        },
        u8,
        scene.texture_image.data,
    );

    const sampler = gctx.createSampler(.{});

    const bind_group = gctx.createBindGroup(bind_group_layout, &.{
        .{ 
            .binding = 0, 
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0, 
            .size = 256,
        },
        .{
            .binding = 1, .texture_view_handle =texture_view
        },
        .{
            .binding = 2, .sampler_handle = sampler
        }
    });

    const depth = createDepthTexture(gctx);
    const state = try allocator.create(State);
    state.* = .{
        .gctx = gctx,
        .bind_group = bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
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
    // (async) create render pipeline 
    {
        const pipeline_layout = gctx.createPipelineLayout(&.{
            bind_group_layout,
        });
        defer gctx.releaseResource(pipeline_layout);

        const vs_module = zgpu.createWgslShaderModule(gctx.device, scene.shader, "vs");
        defer vs_module.release();

        const color_targets = [_]zgpu.wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ 
                .format = .float32x2, .offset = @offsetOf(Vertex, "uv"),
                .shader_location = 1 
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
                .front_face = .ccw,
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
        gctx.createRenderPipelineAsync(
            allocator,
            pipeline_layout,
            pipeline_descriptor,
            &state.pipeline
        );
    }
    return state;
}


pub fn free(allocator: std.mem.Allocator, state: *State) void {
    state.gctx.destroy(allocator);
    allocator.destroy(state);
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
    const t = @as(f32, @floatCast(gctx.stats.time));

    const cam_world_to_view = zm.lookAtLh(
        zm.f32x4(3.0, 3.0, -3.0, 1.0),
        zm.f32x4(0.0, 0.0, 0.0, 1.0),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(0.25 * std.math.pi, @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height)), 0.01, 100.0);
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);
    const aspect_ratio = @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height));


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

                const mem = gctx.uniformsAllocate(Uniforms, 1);
                mem.slice[0] = Uniforms {
                    .object_to_clip = zm.transpose(object_to_clip),
                    .aspect_ratio = aspect_ratio, 
                    .mip_level = @as(f32, @floatFromInt(state.mip_level)),
                }; 

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

                const mem = gctx.uniformsAllocate(Uniforms, 1);
                mem.slice[0] = Uniforms {
                    .object_to_clip = zm.transpose(object_to_clip),
                    .aspect_ratio = aspect_ratio,
                    .mip_level = @as(f32, @floatFromInt(state.mip_level)),
                }; 

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

pub export fn print_version() void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    stdout.print("Zirconium {s} Loaded\n", .{version}) catch unreachable;
    bw.flush() catch unreachable;
}


