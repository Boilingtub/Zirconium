struct TextUniform {
  position: vec3<f32>,
  color: vec4<f32>,
}
@group(0) @binding(0) var<uniform> text_uniform: TextUniform;

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
  output.position_clip = vec4(position,1.0);
  output.texcoords = texcoords;
  return output;
}

@group(0) @binding(1) var font_texture: texture_2d<f32>;
@group(0) @binding(2) var texture_sampler: sampler;

@fragment fn fs_main(
  @location(0) texcoords: vec2<f32>,
) -> @location(0) vec4<f32> {
  let texture = textureSample(
      font_texture, 
      texture_sampler, 
      texcoords, 
  );
  let fin_color = texture;
  return fin_color;
}

