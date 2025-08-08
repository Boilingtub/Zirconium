const std = @import("std");
const TrueType = @import("TrueType"); 

pub fn IntArrayFromTo(l:comptime_int,h:comptime_int) [h-l]u8 { 
    var arr: [h-l]u8 = .{0}**(h-l);
    for (0..(h-l)) |i| {
        arr[i] = l+i;
    }
    return arr;
}

pub const TextUniform = struct {
    position: [3]f32,
    color: [4]f32,
};

pub const CharObject = struct {
    chr : u8,
    font_offset: [2]f32,
};

pub const TextDrawable = struct {
    textobj_index: u32,
    position: [3]f32,
    color: [4]f32,
};

pub const TextObject = struct {
    charobjs: []CharObject,//Heap allocated
    spacing: [2]f32,
    font_texture_atlas:*const FontTextureAtlas,
    pub fn string_to_textobj(
        allocator: std.mem.Allocator,
        font_texture_atlas:*const FontTextureAtlas,
        str:[]const u8,
        spacing: [2]f32,
    ) TextObject {
        var charobjs = allocator.alloc(CharObject, str.len) catch unreachable;

        for(0..(str.len-1)) |i| {
            charobjs[i] = .{
                .chr = str[i],
                .font_offset = .{
                    @as(f32,@floatFromInt(font_texture_atlas.offset[
                            str[i]-font_texture_atlas.lowest_value])) / 
                    @as(f32,@floatFromInt(font_texture_atlas.width)),
                    @as(f32,@floatFromInt(font_texture_atlas.offset[
                            str[i]+1-font_texture_atlas.lowest_value])) /
                    @as(f32,@floatFromInt(font_texture_atlas.width)),
                },        
            };       
        }                             

        return TextObject {
            .charobjs = charobjs,
            .spacing = spacing,
            .font_texture_atlas = font_texture_atlas,
        };  
    }
    pub fn deinit(self:*const TextObject,allocator:std.mem.Allocator) void {
        allocator.free(self.charobjs);
        //allocator.free(self.font_texture_atlas);
    }
};

pub const FontTextureAtlas = struct {
    width : u32,
    height : u32,
    num_components: u32,
    lowest_value: u8,
    bytes_per_component: u32,
    offset: []u32,
    data: []u8,
    pub fn init(allocator: std.mem.Allocator, font: []const u8,
        comptime font_chars:[]const u8,) !FontTextureAtlas 
    {
        const ttf = try TrueType.load(font);
        const scale = ttf.scaleForPixelHeight(20);
        const lowest_value = font_chars[0];

        var glyph_buffer : std.ArrayListUnmanaged(u8) = .empty;

        var raw_data_buffer = std.ArrayList(u8).init(allocator);
        var raw_offset = try allocator.alloc(u32,font_chars.len);
        var cp_height = try allocator.alloc(u32, font_chars.len);
        var cp_width = try allocator.alloc(u32, font_chars.len);
        var tot_height:u32 = 0;
        var tot_width:u32 = 0;

        var iter = std.unicode.Utf8View.initComptime(font_chars).iterator();
        var codepoint_count:u32 = 0;
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

                try raw_data_buffer.appendSlice(glyph_buffer.items);
                raw_offset[codepoint_count] = @intCast(
                    raw_data_buffer.items.len
                );
                cp_height[codepoint_count] = dims.height;
                cp_width[codepoint_count] = dims.width;
                tot_width += dims.width;
                tot_height = @max(tot_height, dims.height);
                codepoint_count += 1;
            }
        }

        var font_texture_atlas: FontTextureAtlas = .{
            .width = tot_width,
            .height = tot_height,
            .num_components = 1,
            .lowest_value = lowest_value,
            .bytes_per_component = 1,
            .offset = try allocator.alloc(u32, codepoint_count),
            .data = try allocator.alloc(u8, tot_width*tot_height*1*1),
        };

        var data_count:u32 = 0;
        for(0..tot_height) |h| {
            for(0..codepoint_count-1) |cp| {
                for(0..cp_width[cp]) |w| {
                    if(cp_height[cp] > h) {
                        font_texture_atlas.data[data_count] =
                            raw_data_buffer.items[raw_offset[cp]+cp_width[cp]*h+w];
                    } else {
                        font_texture_atlas.data[data_count] = 0;
                    }
                    data_count += 1;
                }
            }
        }


        return font_texture_atlas;
    }

    pub fn debug_print(self:FontTextureAtlas) void {
        std.debug.print(
            "width:{d}\nheight:{d}\nnum_components:{d}\nbytes_per_component:{d}\n", .{
            self.width,self.height,self.num_components,self.bytes_per_component,
        });
        std.debug.print(
            "data:\n{s}\noffset:\n{d}\n", .{self.data.items,self.offset[0..]}
        );
    }

    pub fn bytes_per_row(self:FontTextureAtlas) u32 {
        return self.width*self.num_components*self.bytes_per_component;
    }

    pub fn deinit(self:FontTextureAtlas, allocator: std.mem.Allocator) void {
        allocator.free(self.offset);
        self.data.deinit();
    }
};
