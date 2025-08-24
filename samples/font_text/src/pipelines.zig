const gpu = @import("gpu");
const zgpu = gpu.zgpu;
const text = gpu.text;
const Image = gpu.Image;
const std = gpu.std;
const State = gpu.State;
const mesh = gpu.mesh;
const Vertex = mesh.Vertex;
const IndexType = mesh.IndexType;
const IntArrayFromTo = gpu.IntArrayFromTo;
const FontTextureAtlas = gpu.FontTextureAtlas;
const TextUniform = gpu.TextUniform;
const FrameUniforms = gpu.FrameUniforms;
const DrawUniforms = gpu.DrawUniforms;
const createDepthTexture = gpu.createDepthTexture;

pub fn create_commands(allocator: std.mem.Allocator,
    state: *State) void {
    //Create commands 
    const commands = commands: {
        const encoder = state.gctx.device.createCommandEncoder(null);
        defer encoder.release();

        state.gctx.generateMipmaps(
            allocator, 
            encoder, 
            state.diffuse_texture_array
        );
        //gctx.generateMipmaps(allocator, encoder, font_texture);
         
        break :commands encoder.finish(null);
    };
    defer commands.release();
    state.gctx.submit(&.{commands});

}

pub fn text_pipeline(
    state: *State,
    font_texture_atlas: *const FontTextureAtlas,
    text_shader: [*:0]const u8,
    ) void {
    const gctx = state.gctx;
    const sampler = state.sampler;

    //INIT Text Render bindgroups
    const font_texture = gctx.createTexture(.{
       .usage = .{ .texture_binding = true, .copy_dst = true},
       .size = .{
           .width = font_texture_atlas.width,
           .height = font_texture_atlas.height,
           .depth_or_array_layers = 1,
       },
       .format = zgpu.imageInfoToTextureFormat(
           font_texture_atlas.num_components,
           font_texture_atlas.bytes_per_component,
           false, 
       ),
       .mip_level_count = std.math.log2_int(
           u32, 
           @max(font_texture_atlas.width, font_texture_atlas.height)) + 1
   });
   const font_texture_view = gctx.createTextureView(font_texture,.{});
   gctx.queue.writeTexture(
       .{
           .texture = gctx.lookupResource(font_texture).?
       }, 
       .{ 
           .bytes_per_row = font_texture_atlas.bytes_per_row(),
           .rows_per_image = font_texture_atlas.height, 
       }, 
       .{ 
           .width = font_texture_atlas.width,
           .height = font_texture_atlas.height
       },
       u8,
       font_texture_atlas.data,
   );
   
    const text_bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{.vertex=true, .fragment=true}, .uniform, true, 0),
        zgpu.textureEntry(1, .{.fragment=true}, .float, .tvdim_2d, false),
        zgpu.samplerEntry(2, .{.fragment = true} , .filtering),

    });
    defer gctx.releaseResource(text_bind_group_layout);
    const text_bind_group = gctx.createBindGroup(text_bind_group_layout,&.{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(TextUniform)+@sizeOf([5]f32),
        },
        .{
            .binding = 1,
            .texture_view_handle = font_texture_view,
        },
        .{
            .binding = 2, 
            .sampler_handle = sampler,
        }
    });
    //INIT text buffers
    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = text.TextMesh.vertices.len*@sizeOf(text.TextVertex)
    });
    {
        gctx.queue.writeBuffer(
            gctx.lookupResource(vertex_buffer).?,
            0,
            text.TextVertex, 
            &text.TextMesh.vertices
        );
    }
    // Create an index buffer.
    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = text.TextMesh.indices.len * @sizeOf(IndexType),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?,
                           0, IndexType, &text.TextMesh.indices );

    //Init Instace buffers for all TextObjects
    for (0..state.textobjects.items.len) |i| {
        var itb: zgpu.BufferHandle = undefined;
        gpu.recreateInstanceBuffer(
            state, &itb, state.textobjects.items[i].charobjs.len, text.CharObject
        );
        state.text_instance_buffers.append(itb) catch unreachable;
    } 

    // create text render pipeline 
    const text_pipeline_layout = gctx.createPipelineLayout(&.{
        text_bind_group_layout,
    });
    defer gctx.releaseResource(text_pipeline_layout);

    const pipeline = pipeline: {//TEXT pipeline creation Block
        const vs_module = zgpu.createWgslShaderModule(
            gctx.device, text_shader, "vs"
        );

        const color_targets = [_]zgpu.wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
            .{.format = .float32x2, .offset=0, .shader_location = 0},
        };
        const instance_attributes = [_]zgpu.wgpu.VertexAttribute{ 
            .{
                .format = .float32x2,
                .offset = @offsetOf(text.CharObject, "font_offset"),
                .shader_location = 10,
            }, 
            .{
                .format = .float32x2,
                .offset = @offsetOf(text.CharObject, "pos_offset"),
                .shader_location = 11,
            },
        };

        const vertex_buffers = [_]zgpu.wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(text.TextVertex),
                .attribute_count = vertex_attributes.len,
                .attributes = &vertex_attributes,
            },
            .{
                .array_stride = @sizeOf(text.CharObject),
                .step_mode = .instance,
                .attribute_count = instance_attributes.len,
                .attributes = &instance_attributes,
            }, 
        };

        const text_pipeline_descriptor = zgpu.wgpu.RenderPipelineDescriptor{ 
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

        break :pipeline gctx.createRenderPipeline(
            text_pipeline_layout,
            text_pipeline_descriptor,
        );
        
    };
    state.text_pipeline = pipeline;
    state.text_bind_group = text_bind_group;
    state.font_texture_view = font_texture_view;
    state.font_texture = font_texture;
    state.text_vertex_buffer = vertex_buffer;
    state.text_index_buffer = index_buffer;
} 


pub fn render_pipeline(
    state: *State,
    meshes_vertices: []const Vertex,
    meshes_indices: []const IndexType,
    images: []const Image,
    render_shader: [*:0]const u8,
    ) void {
    
    const gctx = state.gctx;
    //INIT World Textures
    //INIT World Information
    const total_num_vertices = @as(u32, @intCast(meshes_vertices.len));
    const total_num_indices = @as(u32, @intCast(meshes_indices.len));

    const def_tex_width = images[0].width;
    const def_tex_height = images[0].height;
    const def_tex_num_components = images[0].num_components;
    const def_tex_bytes_per_component = images[0].bytes_per_component;
    const def_tex_is_hdr = images[0].is_hdr;
    const def_tex_layer_count:u32 = @intCast(images.len);
    const def_tex_bytes_per_row = images[0].bytes_per_row;

    const diffuse_texture_array_descriptor = zgpu.wgpu.TextureDescriptor {
        .usage = .{ .texture_binding = true, .copy_dst = true},
        .size = .{ 
            .width = def_tex_width,
            .height = def_tex_height, 
            .depth_or_array_layers = def_tex_layer_count,
        },
        .format = zgpu.imageInfoToTextureFormat( 
            def_tex_num_components,
            def_tex_bytes_per_component,
            def_tex_is_hdr,
        ),

        .mip_level_count = std.math.log2_int(
            u32, 
            @max(def_tex_width, def_tex_height)) + 1
    };
    const diffuse_texture_array = gctx.createTexture(diffuse_texture_array_descriptor);

    const diffuse_texture_array_view_descriptor = zgpu.wgpu.TextureViewDescriptor {
        .dimension = .tvdim_2d_array,
        .base_array_layer = 0,
        .array_layer_count = @intCast(images.len),
    };
    const diffuse_texture_array_view = gctx.createTextureView(
        diffuse_texture_array, 
        diffuse_texture_array_view_descriptor
    );

    for(0..images.len) |layer| {
        gctx.queue.writeTexture(
            .{
                .texture = gctx.lookupResource(diffuse_texture_array).?,
                .origin = .{.x = 0, .y = 0, .z = @intCast(layer)},
                .mip_level = 0,
            }, 
            .{ 
                .bytes_per_row = def_tex_bytes_per_row,
                .rows_per_image = def_tex_height, 
            }, 
            .{ 
                .width = def_tex_width,
                .height = def_tex_height,
                .depth_or_array_layers = 1,
            },
            u8,
            images[layer].data,   
        ); 
    }

    const sampler = state.sampler;
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
        zgpu.textureEntry(1, .{.fragment = true}, .float, .tvdim_2d_array, false),
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
            .binding = 1,
            .texture_view_handle = diffuse_texture_array_view,
        },
        .{
            .binding = 2,
            .sampler_handle = sampler
        }

    });

    // Create a vertex buffer.
    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = total_num_vertices * @sizeOf(Vertex),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?,
                            0, Vertex, meshes_vertices);

    // Create an index buffer.
    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = total_num_indices * @sizeOf(IndexType),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?,
                           0, IndexType, meshes_indices);

   // create world render pipeline 
    const pipeline_layout = gctx.createPipelineLayout(&.{
        frame_bind_group_layout,
        draw_bind_group_layout,
    });
    defer gctx.releaseResource(pipeline_layout);

    const pipeline = pipeline: //World Pipeline creation Block
    {
        const vs_module = zgpu.createWgslShaderModule(gctx.device, render_shader, "vs");
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
        break :pipeline gctx.createRenderPipeline(
            pipeline_layout,
            pipeline_descriptor,
        );
    };

    state.render_pipeline = pipeline;
    state.frame_bind_group = frame_bind_group;
    state.draw_bind_group = draw_bind_group;
    state.vertex_buffer = vertex_buffer;
    state.index_buffer = index_buffer;
    state.diffuse_texture_array = diffuse_texture_array;
    state.diffuse_texture_array_view = diffuse_texture_array_view;
    state.depth_texture = depth.texture;
    state.depth_texture_view = depth.view;

}
