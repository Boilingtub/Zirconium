struct Vertex {
  @location(0) position: vec2<f32>,
  @builtin(vertex_index) idx: u32,
}

struct Instance {
  @builtin(instance_index) idx: u32,
  @location(10) font_offset: vec4<f32>,
  @location(11) pos_offset: vec2<f32>,
}

struct TextUniform {
  color: vec4<f32>,
  position: vec2<f32>,
  scale: f32,
  aspect_ratio: f32
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
    let x_scale_pos = (vertex.position.x*text_uniform.scale) / text_uniform.aspect_ratio;
    let y_scale_pos = (vertex.position.y*text_uniform.scale) ;
    let x_offpos = instance.pos_offset.x / text_uniform.aspect_ratio;
    let y_offpos = instance.pos_offset.y / text_uniform.aspect_ratio;
    var pos = vec2<f32>(
      x_scale_pos + x_offpos + text_uniform.position.x,
      y_scale_pos + y_offpos + text_uniform.position.y
    );
    out.position_clip = vec4<f32>(pos,0.0,1.0);
    //let uvx = vec2(0.05264*f32(instance.idx),0.05264*f32(instance.idx+1));
    //let uvy = vec2(0,0.2);
    let uvx = vec2(instance.font_offset.xy);
    let uvy = vec2(instance.font_offset.zw);
    switch vertex.idx {
      case 0, default: {
        out.texcoords = vec2(uvx[0],uvy[0]);
      }
      case 1: {
        out.texcoords = vec2(uvx[0], uvy[1]);
      }
      case 2: {
        out.texcoords = vec2(uvx[1], uvy[0]);
      }
      case 3: {
        out.texcoords = vec2(uvx[1], uvy[1]);
      }
   }
 //  var uv = vec2<f32>(f32((vertex.idx << 1u) & 2u), f32(vertex.idx & 2u));
 //  var posi = (uv * 2.0 - 1.0)*0.49;
 //  out.position_clip = vec4<f32>(posi.x, -posi.y, 0.0, 1.0); // Flip Y for correct orientation
 //  out.texcoords = uv;
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
    if(texture.r < 0.1) {discard;};
    let fin_color = vec4(
      texture.r*text_uniform.color.rgb,1.0
    );
    return fin_color;
}

