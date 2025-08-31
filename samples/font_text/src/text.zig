const std = @import("std");
const TrueType = @import("TrueType"); 
const gpu = @import("gpu");

pub fn IntArrayFromTo(l:comptime_int,h:comptime_int) [h-l]u8 { 
    var arr: [h-l]u8 = .{0}**(h-l);
    for (0..(h-l)) |i| {
        arr[i] = l+i;
    }
    return arr;
}

pub const TextUniform = struct {
    color: [4]f32,
    position: [2]f32,   
    scale: f32,
    aspect_ratio: f32 = 1.0,
};

pub const CharObject = struct {
    font_offset: [4]f32,
    pos_offset: [2]f32,
};

pub const TextDrawable = struct {
    color: [4]f32,
    position: [2]f32,
    scale: f32,
    textobj_index: u32,
};

pub const TextObject = struct {
    charobjs: []CharObject,//Heap allocated
    font_texture_atlas:*const FontTextureAtlas,
    spacing:[2]f32,
    pub fn string_to_textobj(
        allocator: std.mem.Allocator,
        font_texture_atlas:*const FontTextureAtlas,
        str:[]const u8,
        spacing: [2]f32,
    ) TextObject {
        var to : TextObject = .{
            .charobjs =allocator.alloc(CharObject, str.len) catch unreachable,
            .font_texture_atlas = font_texture_atlas,
            .spacing = spacing,
        };
        to.change_string(allocator, str);
        return to;
    }
    pub fn change_string(to: *TextObject, allocator: std.mem.Allocator,
        str: []const u8) void {
        if(to.charobjs.len != str.len) {
            to.charobjs = allocator.realloc(to.charobjs, str.len) catch
                unreachable;
        }
        var pos_offset: [2]f32 = .{0.0,0.0};
        for(0..(str.len)) |i| {
            if (str[i] == '\n') {
                pos_offset[0] = 0;
                pos_offset[1] -= to.spacing[1];
                continue;
            }
            pos_offset[0] += to.spacing[0];
            to.charobjs[i] = .{
                .pos_offset = pos_offset,
                .font_offset = to.font_texture_atlas.get_offset_of(str[i]),
            };       
        }                           
        
    }
    pub fn print(self: *const TextObject) void {
        std.debug.print("FontTextureAtlas=\n{any}\n", .{self.font_texture_atlas});
        std.debug.print("self.charobjs=\n{any}\n", .{self.charobjs});
    }
    pub fn deinit(self:*const TextObject,allocator:std.mem.Allocator) void {
        allocator.free(self.charobjs);
    }
};

pub const OffsetMap = struct {
    x: []f32,
    y: []f32,
    pub fn init(allocator: std.mem.Allocator,
        x_count: u32, y_count: u32) !OffsetMap {
        return OffsetMap {
            .x = try allocator.alloc(f32,x_count+1),
            .y = try allocator.alloc(f32,y_count+1),
        };
    }
    pub fn deinit(self: OffsetMap, allocator: std.mem.Allocator) void {
       allocator.free(self.x);
       allocator.free(self.y);

    }
};
pub const FontTextureAtlas = struct {
    bmp: gpu.zstbi.Image,
    lowest_value: u8,
    width_glyph_count: u32,
    offset: OffsetMap,
    pub fn from_ttf(allocator: std.mem.Allocator, ttf_data: []const u8,
        comptime font_chars: []const u8, pixel_height:u16,
        width_glyph_count: u16)  !FontTextureAtlas {
        const height_glyph_count = @as(u16,@intFromFloat(
            @ceil(
                @as(f32,@floatFromInt(font_chars.len)) / 
                @as(f32,@floatFromInt(width_glyph_count))
            )
        ));

        var font_texture_atlas:FontTextureAtlas = .{
            .bmp = undefined,
            .lowest_value = font_chars[0],
            .width_glyph_count = width_glyph_count,
            .offset = try OffsetMap.init(allocator, width_glyph_count,
                height_glyph_count),
        };

        
        const width: u32 = width_glyph_count*pixel_height;
        const height: u32 = height_glyph_count*pixel_height;
        var bmp_data = try allocator.alloc(u8, (width)*(height) );
        for(0..bmp_data.len) |i| {bmp_data[i] = 0;}

        const GlyphBMP = struct {
            width: u16, 
            height: u16,
            data: []u8,
        };
        var bmp_glyps = std.ArrayList(GlyphBMP).init(allocator);

        const ttf = try TrueType.load(ttf_data); 
        const scale = 
            ttf.scaleForPixelHeight(@as(f32,@floatFromInt(pixel_height)));
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(allocator);

        var it = std.unicode.Utf8View.initComptime(font_chars).iterator();
        while(it.nextCodepoint()) |codepoint| {
            if(ttf.codepointGlyphIndex(codepoint)) |glyph| {
                buf.clearRetainingCapacity();
                const dims = ttf.glyphBitmap(
                    allocator, &buf, glyph, scale, scale
                ) catch |err| switch (err) {
                    TrueType.GlyphBitmapError.GlyphNotFound => {
                        for(0..buf.items.len) |i| {buf.items[i] = 0;}
                        const glyph_bmp: GlyphBMP = .{
                            .width = pixel_height,
                            .height = pixel_height,
                            .data = try allocator.dupe(u8, buf.items),
                        };
                        try bmp_glyps.append(glyph_bmp);
                        continue;
                    },
                    else => {unreachable;},
                };
                const glyph_bmp: GlyphBMP = .{
                    .width = dims.width,
                    .height = dims.height,
                    .data = try allocator.dupe(u8, buf.items),
                };
                try bmp_glyps.append(glyph_bmp);
                //Calculate OffsetMap 
            }
        }

        var data_count:u32 = 0;
        for(0..height_glyph_count) |height_glyph_count_loop| {
            const hgc:u16 = @intCast(height_glyph_count_loop);
            const glyph_line_begin = width_glyph_count * hgc;
            const glyph_line_end = @min(
                glyph_line_begin+width_glyph_count,
                bmp_glyps.items.len
            );
            for(0..pixel_height) |line_height| {
                const h:u16 = @intCast(line_height);

                for(glyph_line_begin..glyph_line_end) |glyph_number_in_line| {
                    const g:u16 = @intCast(glyph_number_in_line);
                    const lb_idx = h*bmp_glyps.items[g].width;
                    const le_idx = lb_idx+bmp_glyps.items[g].width;

                    data_count = hgc*width*(pixel_height-1) + h*width + pixel_height*g;
                    if(le_idx <= bmp_glyps.items[g].data.len) {
                        for(lb_idx..le_idx) |i| {
                            bmp_data[data_count+(i-lb_idx)] = bmp_glyps.items[g].data[i];
                        }
                    } else {
                        break;
                    }
                }
            } 
        }
        var bmp = try gpu.zstbi.Image.createEmpty(width, height, 1, .{.bytes_per_component = 1, .bytes_per_row = 1*width});
        bmp.data = bmp_data;
        font_texture_atlas.bmp = bmp;
        return font_texture_atlas;
        
//      const p:bool = true;
//      if(p) {
//          var count:u32 = 0;
//          for(0..height) |_| {
//              for(0..width) |_| {
//                  const pix = bmp_data[count];
//                  if(pix == 0) {
//                      std.debug.print(" ", .{});
//                  } else {
//                      std.debug.print("o", .{});
//                  }
//                  count += 1;
//              }
//              std.debug.print("\n",.{});
//          }
//          std.process.exit(1);
//      }

    }
    pub fn from_bmp(allocator: std.mem.Allocator, font_bmp: *const gpu.zstbi.Image,
        font_chars: []const u8, width_glyph_count: u16) !FontTextureAtlas {
        const height_glyph_count = @as(u16,@intFromFloat(
            @ceil(
                @as(f32,@floatFromInt(font_chars.len)) / 
                @as(f32,@floatFromInt(width_glyph_count))
            )
        ));

        //std.debug.print("{c}", .{font_chars}); //Print chars to screen
        var font_texture_atlas: FontTextureAtlas = .{
            .bmp = font_bmp.*,
            .lowest_value = font_chars[0],
            .width_glyph_count = width_glyph_count,
            .offset = undefined,
        };
        std.debug.assert(font_texture_atlas.bmp.bytes_per_component > 0);

        const glyph_offset_x: f32 = 
            1 / @as(f32,@floatFromInt(width_glyph_count));

        const glyph_offset_y: f32 = 
            1 / @as(f32,@floatFromInt(height_glyph_count));

        font_texture_atlas.offset = try OffsetMap.init(allocator, width_glyph_count, height_glyph_count);
        for(0..font_texture_atlas.offset.x.len) |i| {
            font_texture_atlas.offset.x[i] = glyph_offset_x*@as(f32,@floatFromInt(i));
        }
        for(0..font_texture_atlas.offset.y.len) |i| {
            font_texture_atlas.offset.y[i] = glyph_offset_y*@as(f32,@floatFromInt(i));
        }
        return font_texture_atlas;
    }

                                                                                                                 
    pub fn get_offset_of(self:*const FontTextureAtlas, c:u8) [4]f32 {
        const off_idx = c-self.lowest_value;
        const x_off = off_idx % self.width_glyph_count;
        const y_off = off_idx / (self.width_glyph_count);
        return .{
            self.offset.x[x_off],
            self.offset.x[x_off+1],
            self.offset.y[y_off],
            self.offset.y[y_off+1],
        };
    }
    pub fn debug_print(self:FontTextureAtlas) void {
        std.debug.print(
            "width_glyph_count:{d}\nlowest_value:{d}\noffset_map:{?}\ndata_size:{d}\n",.{
            self.width_glyph_count,self.lowest_value,self.offset,self.bmp.data.len,
        });
    }

    pub fn write_to_png(self:FontTextureAtlas, 
        path:[:0]const u8) !void {
        try self.bmp.writeToFile(path, gpu.zstbi.ImageWriteFormat.png);
    }
                           
    pub fn deinit(self:FontTextureAtlas, allocator: std.mem.Allocator) void {
        self.offset.deinit(allocator);
        //self.bmp.deinit(); 
    }
};

pub const TextVertex = [2]f32;
const TextModel = struct {
    vertices: [4]TextVertex,
    indices: [6]u16,
};

pub const TextMesh: TextModel = .{
    .vertices = .{
        .{ -1, 1,}, // (0)o----o(2)
        .{-1, -1,}, //    |    |
        .{ 1, 1,},  //    |    |
        .{ 1,-1,},  // (1)o----o(3)
    },
    .indices = .{0, 1, 2, 2, 1, 3,}
};
