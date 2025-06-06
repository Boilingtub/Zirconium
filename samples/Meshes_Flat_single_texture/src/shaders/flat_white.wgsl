struct FrameUniforms {
  world_to_clip: mat4x4<f32>,
  camera_position: vec3<f32>,
}
@group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;

struct DrawUniforms {
  object_to_world: mat4x4<f32>,
  basecolor_roughness: vec4<f32>,
}
@group(1) @binding(0) var<uniform> draw_uniforms: DrawUniforms;

struct VertexOut {
  @builtin(position) position_clip: vec4<f32>,
  @location(0) color: vec3<f32>,
}
@vertex fn vs_main(
  @location(0) position: vec3<f32>,
) -> VertexOut {
  var output: VertexOut;
  output.position_clip = vec4(position, 1.0) * 
                         draw_uniforms.object_to_world * 
                         frame_uniforms.world_to_clip;
  //output.position = (vec4(position, 1.0)* draw_uniforms.object_to_world).xyz;
  output.color = vec3(1.0,1.0,1.0);
  return output;
}


@fragment fn fs_main(
  @location(0) color: vec3<f32>,
) -> @location(0) vec4<f32> {
  return vec4(color, 1.0);
}

