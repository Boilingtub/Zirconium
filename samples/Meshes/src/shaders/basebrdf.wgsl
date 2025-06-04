struct FrameUniforms {
  world_to_clip: mat4x4<f32>,
  camera_position: vec3<f32>,
}
@group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;

struct Draw_Uniforms {
  object_to_world: mat4x4<f32>,
  basecolor_roughness: vec4<f32>,
}
@group(1) @binding(0) var<uniform> draw_uniforms: DrawUniforms;

struct VertexOut {
  @builtin(position) position_clip: vec4<f32>,
  @location(0) position: vec3<f32>,
  @location(1) normal: vec3<f32>,
  @location(2) barycentrics: vec3<f32>,
}
@vertex fn main(
  @location(0) position: vec3<f32>,
  @location(1) normal: vec3<f32>,
  @builtin(vertex_index) vectex_index: u32,
) -> VertexOut {
  var output: VertexOut;
  output.position_clip = vec4(position,1.0) *
                         draw_uniforms.object_to_world *
                         frame_uniforms.world_to_clip;
  output.position = (vec4(position, 1.0)* draw_uniforms.object_to_world).xyz;
  output.normal = normal * mat3x3(
    draw_uniforms.object_to_world[0].xyz,
    draw_uniforms.object_to_world[1].xyz,
    draw_uniforms.object_to_world[2].xyz,
  );
  let index = vertex_index % 3u;
  output.barycentrics = vec3(
    f32(index == 0u), 
    f32(index == 1u), 
    f32(index == 2u)
  );
  return output;
}


const pi = 3.1415926;

fn saturate(x:f32) -> f32 { return clamp(x, 0.0, 1.0);}

fn distrobutionGgx(n: vec3<f32>, h: vec3<f32>, alpha: f32) -> f32
