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
    scale: [2]f32,
};

pub const CharObject = struct {
    font_offset: [4]f32,
    pos_offset: [2]f32,
};

pub const TextDrawable = struct {
    scale: [2]f32,
    position: [2]f32,
    color: [4]f32,
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
        //self.font_texture_atlas.deinit(allocator);
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
    pub fn from_png(allocator: std.mem.Allocator, font_data: []const u8,
        font_chars: []const u8) !FontTextureAtlas {
        //std.debug.print("{c}", .{font_chars}); //Print chars to screen
        var font_texture_atlas: FontTextureAtlas = .{
            .bmp = try gpu.zstbi.Image.loadFromMemory(font_data, 1),
            .lowest_value = font_chars[0],
            .width_glyph_count = 19,
            .offset = undefined,
        };
        std.debug.assert(font_texture_atlas.bmp.bytes_per_component > 0);

        const width_glyph_count = 19;//HARD coded will change with different fonts
        const glyph_offset_x: f32 = 
            1 / @as(f32,@floatFromInt(width_glyph_count));

        const height_glyph_count = 5;
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

//    pub fn from_ttf(allocator: std.mem.Allocator, font: []const u8, //OUTDATED BROKEN
//       comptime font_chars:[]const u8,) !FontTextureAtlas 
//   {
//       std.debug.panic("\n[PANIC!]\nFontTextureAtlas.from_ttf() currently broken !\n\n", .{});
//       const font_height = 20;
//       var font_texture_atlas: FontTextureAtlas = .{
//           .width = 0,
//           .height = 0,
//           .num_components = 1,
//           .lowest_value = font_chars[0],
//           .bytes_per_component = 1,
//           .offset = try allocator.alloc(BMP_Offset, font_chars.len),
//           .data = undefined,
//       };
//       const ttf = try TrueType.load(font);
//       const scale = ttf.scaleForPixelHeight(font_height);
//       var glyph_buffer : std.ArrayListUnmanaged(u8) = .empty;
//       var raw_data_buffer = std.ArrayList(u8).init(allocator);
//       var cp_count: u32 = 0;
//
//       var iter = std.unicode.Utf8View.initComptime(font_chars).iterator();
//       while(iter.nextCodepoint()) |codepoint| {
//           if (ttf.codepointGlyphIndex(codepoint)) |glyph| {
//
//               glyph_buffer.clearRetainingCapacity();
//               const dims = try ttf.glyphBitmap(
//                   allocator,
//                   &glyph_buffer, 
//                   glyph,
//                   scale,
//                   scale,
//               );
//               if(dims.height < font_height){
//                   while(glyph_buffer.items.len < dims.width*font_height) {
//                       try glyph_buffer.append(allocator, 0);
//                   }
//               }
//               std.debug.print("\n", .{});
//               for(0..glyph_buffer.items.len) |i| {
//                   std.debug.print("{d}|", .{glyph_buffer.items[i]});
//                   if(i % dims.width == 0) {
//                       std.debug.print("\n", .{});
//                   }
//               }
//               try raw_data_buffer.appendSlice(glyph_buffer.items);
//               font_texture_atlas.offset[cp_count].x = 
//                   @intCast(font_texture_atlas.width);
//               font_texture_atlas.offset[cp_count].y = @intCast(dims.height);
//               font_texture_atlas.width += dims.width;
//               font_texture_atlas.height = @max(font_texture_atlas.height, dims.height);
//           }
//           cp_count += 1;
//       }
//       font_texture_atlas.data = raw_data_buffer.items;
//       return font_texture_atlas;
//   }                                                                                                                                     
    pub fn get_offset_of(self:FontTextureAtlas, c:u8) [4]f32 {
        const off_idx = c-self.lowest_value;
        const width_glyph_count = self.width_glyph_count;
        const x_off = off_idx % width_glyph_count;
        const y_off = off_idx / (width_glyph_count);
        return .{
            self.offset.x[x_off],
            self.offset.x[x_off+1],
            self.offset.y[y_off],
            self.offset.y[y_off+1],
        };
    }
    pub fn debug_print(self:FontTextureAtlas) void {
        std.debug.print(
            "width:{d}\nheight:{d}\nnum_components:{d}\nbytes_per_component:{d}\n", .{
            self.width,self.height,self.num_components,self.bytes_per_component,
        });
        std.debug.print(
            "data len:{d} bytes\noffset:\n{d}\n", .{self.data.len, self.offset.len}
        );
    }

    pub fn write_to_png(self:FontTextureAtlas, 
        path:[:0]const u8) !void {
        try self.bmp.writeToFile(path, gpu.zstbi.ImageWriteFormat.png);
    }

    pub fn deinit(self:FontTextureAtlas, allocator: std.mem.Allocator) void {
        self.offset.deinit(allocator);
        allocator.free(self.bmp.data);
    }
};

pub const TextVertex = [2]f32;
const TextModel = struct {
    vertices: [4]TextVertex,
    indices: [6]u16,
};

pub const TextMesh: TextModel = .{
    .vertices = .{
        .{ 1, 1,}, // (1)o----o(0)
        .{-1, 1,}, //    |    |
        .{-1,-1,}, //    |    |
        .{ 1,-1,}, // (2)o----o(3)
    },
    .indices = .{0, 2, 3, 0, 1, 2,}
};
