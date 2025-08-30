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
    pub fn from_png(allocator: std.mem.Allocator, font_bmp: *const gpu.zstbi.Image,
        font_chars: []const u8, width_glyph_count: u32) !FontTextureAtlas {
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
