struct Unifroms {
  object_to_clip: mat4x4<f32>,
  aspect_ratio: f32,
  //mip_level: f32,
}
@group(0) @binding(0) var<uniform> uniforms: Unifroms;

struct VertexOutput {
  @builtin(position)  position_clip: vec4<f32>,
  @location(0) uv: vec2<f32>,
}

@vertex fn vs_main(
    @location(0) position: vec3<f32>,
    @location(1) uv: vec2<f32>,
) -> VertexOutput {
    var p = vec2(position.x / uniforms.aspect_ratio, position.y);
    var output: VertexOutput;
    output.position_clip = vec4(p,position.z, 1.0) * uniforms.object_to_clip;
    output.uv = uv;
    return output;
}

@group(0) @binding(1) var image: texture_2d<f32>;
@group(0) @binding(2) var image_sampler: sampler;
@fragment fn fs_main(
  @location(0) uv: vec2<f32>,
) -> @location(0) vec4<f32> {
  return textureSampleLevel(image, image_sampler, uv, 1);
}

