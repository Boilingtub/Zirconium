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
  scale: vec2<f32>,
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
    var pos = vec2<f32>(vertex.position.xy*text_uniform.scale.xy
    + instance.pos_offset.xy + text_uniform.position.xy);
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
   let fin_color = vec4(texture.xxxw);
   return fin_color;
}

