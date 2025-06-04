struct FrameUniforms {
  world_to_clip: mat4x4<f32>,
  camera_position: vec3<f32>,
}
@group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;

struct DrawUniforms {
  object_to_world: mat4x4<f32>,
  basecolor_roughness: vec4<f32>,
  mip_level: f32,
}
@group(1) @binding(0) var<uniform> draw_uniforms: DrawUniforms;

struct VertexOut {
  @builtin(position) position_clip: vec4<f32>,
  @location(0) texcoords: vec2<f32>,
}
@vertex fn vs_main(
  @location(0) position: vec3<f32>,
  @location(1) normal: vec3<f32>,
  @location(2) texcoords: vec2<f32>,
) -> VertexOut {
  var output: VertexOut;
  output.position_clip = vec4(position, 1.0) * 
                         draw_uniforms.object_to_world * 
                         frame_uniforms.world_to_clip;
  output.texcoords = texcoords;
  return output;
}

@group(1) @binding(1) var image: texture_2d<f32>;
@group(1) @binding(2) var image_sampler: sampler;

@fragment fn fs_main(
  @location(0) texcoords: vec2<f32>,
) -> @location(0) vec4<f32> {
  let base_color = draw_uniforms.basecolor_roughness.xyz;
  let roughness = draw_uniforms.basecolor_roughness.a;
  let texture = textureSampleLevel(
                  image, 
                  image_sampler, 
                  texcoords,
                  draw_uniforms.mip_level
  );
  let fin_color = texture * vec4(base_color,1.0);
  return fin_color;
}

