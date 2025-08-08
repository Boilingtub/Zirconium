pub const std = @import("std");
pub const zgpu = @import("zgpu");
pub const zglfw = @import("zglfw");
pub const zstbi = @import("zstbi");
pub const Image = zstbi.Image;
pub const zm = @import("zmath");
pub const text = @import("text");
pub const TextObject = text.TextObject;
pub const TextDrawable = text.TextDrawable;
pub const IntArrayFromTo = text.IntArrayFromTo;
pub const FontTextureAtlas = text.FontTextureAtlas;
pub const TextUniform = text.TextUniform;
pub const mesh = @import("mesh");
pub const Mesh = mesh.Mesh;
pub const Drawable = mesh.Drawable;
pub const IndexType = mesh.IndexType;
pub const camera = @import("camera");
pub const Camera = camera.Camera;

pub const FrameUniforms = struct {
    world_to_clip: zm.Mat,
    camera_position: [3]f32,
};
pub const DrawUniforms = struct {
    object_to_world: zm.Mat,
    texture_index: u32,
    basecolor_roughness: [4]f32,
};

pub const State = struct {
    gctx: *zgpu.GraphicsContext,
    
    //UI render pipeline
    text_pipeline: zgpu.RenderPipelineHandle = .{},
    text_bind_group: zgpu.BindGroupHandle, 

    text_vertex_buffer: zgpu.BufferHandle,
    text_index_buffer: zgpu.BufferHandle,

    font_texture: zgpu.TextureHandle,
    font_texture_view: zgpu.TextureViewHandle,

    textobjects: std.ArrayList(TextObject),
    textdrawables: std.ArrayList(TextDrawable),

    //World render pipeline and dependencies.
    camera: Camera,

    render_pipeline: zgpu.RenderPipelineHandle = .{},

    frame_bind_group: zgpu.BindGroupHandle,
    draw_bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,

    meshes: std.ArrayList(Mesh),
    drawables: std.ArrayList(Drawable),

    diffuse_texture_array: zgpu.TextureHandle,
    diffuse_texture_array_view: zgpu.TextureViewHandle,

    // General structures
    sampler: zgpu.SamplerHandle,
    mip_level: f32 = 0,

    pub fn init_empty(allocator: std.mem.Allocator,
        window: *zglfw.Window,
        ) !*State {
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
            const sampler = gctx.createSampler(.{});
            
            const state = try allocator.create(State);
            state.gctx = gctx;
            state.sampler = sampler;

            return state;
    }

    pub fn draw_render(state: *State) void {
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
                const vb_info = gctx.lookupResourceInfo(state.vertex_buffer)
                    orelse break :pass;
                const ib_info = gctx.lookupResourceInfo(state.index_buffer)
                    orelse break :pass;
                const render_pipeline = gctx.lookupResource(state.render_pipeline) 
                    orelse break :pass;
                const frame_bind_group = gctx.lookupResource(state.frame_bind_group)
                    orelse break :pass;
                const draw_bind_group = gctx.lookupResource(state.draw_bind_group)
                    orelse break :pass;
                const depth_view = gctx.lookupResource(state.depth_texture_view)
                    orelse break :pass;
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
                //DRAW RENDER 
                pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
                pass.setIndexBuffer(
                    ib_info.gpuobj.?,
                    if (IndexType == u16) .uint16 else .uint32,
                    0,
                    ib_info.size
                );
                pass.setPipeline(render_pipeline);
                // Update "world to clip" (camera) xform
                {   
                    const mem = gctx.uniformsAllocate(FrameUniforms, 1);
                    mem.slice[0].world_to_clip = zm.transpose(cam_world_to_clip);
                    mem.slice[0].camera_position = state.camera.position;
                    pass.setBindGroup(0, frame_bind_group, &.{mem.offset});
                }
                for (state.drawables.items) |drawable| {
                    //Update "object to world" xform 
                    const object_to_world = zm.translationV(zm.loadArr3(drawable.position)               );
                    const mem = gctx.uniformsAllocate(DrawUniforms,1);
                    mem.slice[0].object_to_world = zm.transpose(object_to_world);
                    mem.slice[0].texture_index = drawable.texture_index;
                    mem.slice[0].basecolor_roughness = drawable.basecolor_roughness;
                    //mem.slice[0].mip_level = state.mip_level;
                    pass.setBindGroup(1, draw_bind_group, &.{mem.offset});
                    //Draw
                    if(state.meshes.items[drawable.mesh_index].num_indices == 0)
                        pass.draw(
                            state.meshes.items[drawable.mesh_index].num_vertices,
                            1,
                            @intCast(state.meshes.items[drawable.mesh_index].
                                vertex_offset),
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
                //DRAW TEXT
                const text_vb_info = gctx.lookupResourceInfo(state.text_vertex_buffer)
                    orelse break :pass;
                const text_ib_info = gctx.lookupResourceInfo(state.text_index_buffer)
                    orelse break :pass;
                const text_pipeline = gctx.lookupResource(state.text_pipeline) 
                    orelse break :pass;
                const text_bind_group = gctx.lookupResource(state.text_bind_group)
                    orelse break :pass;
                
                pass.setVertexBuffer(0, text_vb_info.gpuobj.?, 0, text_vb_info.size);
                pass.setIndexBuffer(
                    text_ib_info.gpuobj.?,
                    if (IndexType == u16) .uint16 else .uint32,
                    0,
                    text_ib_info.size
                );
                pass.setPipeline(text_pipeline);

                for (state.textdrawables.items) |td| {
                    const mem = gctx.uniformsAllocate(TextUniform,1);
                    mem.slice[0].position = td.position;
                    mem.slice[0].color = td.color;
                    //mem.slice[0].mip_level = state.mip_level;
                    pass.setBindGroup(0, text_bind_group, &.{mem.offset});
                    //Draw
                    pass.drawIndexed(
                        mesh.primitive_plane.indices.len,
                        @intCast(state.textobjects.items[td.textobj_index].charobjs.len),
                        0,
                        0,
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

    pub fn deinit(state: *State, allocator: std.mem.Allocator) void {
        state.gctx.destroy(allocator);
        state.meshes.deinit();
        state.drawables.deinit();
        for(state.textobjects.items) |t| {
            t.deinit(allocator);
        }
        state.textobjects.deinit();
        state.textdrawables.deinit();
        allocator.destroy(state);
        //state.* = undefined;
    }
};

pub fn createDepthTexture(gctx: *zgpu.GraphicsContext) struct {
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



