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
    position: [2]f32,
    color: [4]f32,
    scale: f32,
};

pub const CharObject = struct {
    font_offset: [4]f32,
    pos_offset: [2]f32,
};

pub const TextDrawable = struct {
    textobj_index: u32,
    position: [2]f32,
    color: [4]f32,
    scale: f32,
};

pub const TextObject = struct {
    charobjs: []CharObject,//Heap allocated
    font_texture_atlas:*const FontTextureAtlas,
    pub fn string_to_textobj(
        allocator: std.mem.Allocator,
        font_texture_atlas:*const FontTextureAtlas,
        str:[]const u8,
        spacing: [2]f32,
    ) TextObject {
        var to : TextObject = .{
            .charobjs =allocator.alloc(CharObject, str.len) catch unreachable,
            .font_texture_atlas = font_texture_atlas,
        };
        var pos_offset: [2]f32 = .{0.0,0.0};
        for(0..(str.len-1)) |i| {
            if (str[i] == '\n') {
                pos_offset[0] = 0;
                pos_offset[1] -= spacing[1];
                continue;
            }
            const off_idx = str[i]-font_texture_atlas.lowest_value;
            pos_offset[0] += spacing[0];
            to.charobjs[i] = .{
                .pos_offset = pos_offset,
                .font_offset = .{
                    @as(f32,@floatFromInt(font_texture_atlas.offset[
                            off_idx].x)) / 
                    @as(f32,@floatFromInt(font_texture_atlas.width)),

                    @as(f32,@floatFromInt(font_texture_atlas.offset[
                            off_idx+1].x)) /
                    @as(f32,@floatFromInt(font_texture_atlas.width)),

                    0,

                    @as(f32,@floatFromInt(font_texture_atlas.offset[
                            off_idx].y)) /
                    @as(f32,@floatFromInt(font_texture_atlas.height)),
                },        
            };  
            //std.debug.print("font_offset:{d}\n",.{to.charobjs[i].font_offset});
        }                             
    
        return to;
    }
    pub fn print(self: *const TextObject) void {
        std.debug.print("FontTextureAtlas=\n{any}\n", .{self.font_texture_atlas});
        std.debug.print("self.charobjs=\n{any}\n", .{self.charobjs});
    }
    pub fn deinit(self:*const TextObject,allocator:std.mem.Allocator) void {
        allocator.free(self.charobjs);
        self.font_texture_atlas.deinit(allocator);
    }
};

pub const BMP_Offset = struct {
    x: u16,
    y: u16,
};
pub const FontTextureAtlas = struct {
    width : u32,
    height : u32,
    num_components: u32,
    lowest_value: u8,
    bytes_per_component: u32,
    offset: []BMP_Offset,
    data: []u8,
    pub fn init(allocator: std.mem.Allocator, font: []const u8,
        comptime font_chars:[]const u8,) !FontTextureAtlas 
    {
        const font_height = 20;
        var font_texture_atlas: FontTextureAtlas = .{
            .width = 0,
            .height = 0,
            .num_components = 1,
            .lowest_value = font_chars[0],
            .bytes_per_component = 1,
            .offset = try allocator.alloc(BMP_Offset, font_chars.len),
            .data = undefined,
        };
        const ttf = try TrueType.load(font);
        const scale = ttf.scaleForPixelHeight(font_height);

        var glyph_buffer : std.ArrayListUnmanaged(u8) = .empty;

        var raw_data_buffer = std.ArrayList(u8).init(allocator);
        var cp_count: u32 = 0;

        var iter = std.unicode.Utf8View.initComptime(font_chars).iterator();
        while(iter.nextCodepoint()) |codepoint| {
            if (ttf.codepointGlyphIndex(codepoint)) |glyph| {

                glyph_buffer.clearRetainingCapacity();
                const dims = try ttf.glyphBitmap(
                    allocator,
                    &glyph_buffer, 
                    glyph,
                    scale,
                    scale,
                );
                if(dims.height < font_height){
                    while(glyph_buffer.items.len < dims.width*font_height) {
                        try glyph_buffer.append(allocator, 0);
                    }
                }
                std.debug.print("\n", .{});
                for(0..glyph_buffer.items.len) |i| {
                    std.debug.print("{d}|", .{glyph_buffer.items[i]});
                    if(i % dims.width == 0) {
                        std.debug.print("\n", .{});
                    }
                }
                try raw_data_buffer.appendSlice(glyph_buffer.items);
                font_texture_atlas.offset[cp_count].x = 
                    @intCast(font_texture_atlas.width);
                font_texture_atlas.offset[cp_count].y = @intCast(dims.height);
                font_texture_atlas.width += dims.width;
                font_texture_atlas.height = @max(font_texture_atlas.height, dims.height);
            }
            cp_count += 1;
        }
        font_texture_atlas.data = raw_data_buffer.items;
        //try font_texture_atlas.write_to_png("font_debug");
        
        return font_texture_atlas;
    }

    pub fn debug_print(self:FontTextureAtlas) void {
        std.debug.print(
            "width:{d}\nheight:{d}\nnum_components:{d}\nbytes_per_component:{d}\n", .{
            self.width,self.height,self.num_components,self.bytes_per_component,
        });
        std.debug.print(
            "data len:{d} bytes\noffset len:\n{d}\n", .{self.data.len, self.offset.len}
        );
    }

    pub fn write_to_png(self:FontTextureAtlas, 
        path:[:0]const u8) !void {
        //gpu.zstbi.init(allocator);
        //defer gpu.zstbi.deinit();
        const img = try gpu.zstbi.Image.loadFromMemory(self.data, 1);
        try img.writeToFile(path, gpu.zstbi.ImageWriteFormat.png);
    }

    pub fn bytes_per_row(self:FontTextureAtlas) u32 {
        return self.width*self.num_components*self.bytes_per_component;
    }

    pub fn deinit(self:FontTextureAtlas, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
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
