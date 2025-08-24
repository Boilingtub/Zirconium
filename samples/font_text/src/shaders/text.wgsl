struct Vertex {
  @location(0) position: vec2<f32>,
}

struct Instance {
  @location(10) font_offset: vec2<f32>,
  @location(11) pos_offset: vec2<f32>,
}

struct TextUniform {
  position: vec2<f32>,
  color: vec4<f32>,
  scale: f32,
}
@group(0) @binding(0) var<uniform> text_uniform: TextUniform;

struct VertexOut {
  @builtin(position) position_clip: vec4<f32>,
  @location(0) texcoords: vec2<f32>,
}

@vertex fn vs_main(
  vertex: Vertex,
  instance: Instance,
) -> VertexOut {
  var out: VertexOut;
    let pos = vertex.position*0.04 + instance.pos_offset;
    out.position_clip = vec4(pos, 0.0, 1.0);
    out.texcoords = instance.font_offset;
  return out;
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
  //let fin_color = vec4(1.0,1.0,1.0,1.0);
  return fin_color;
}

