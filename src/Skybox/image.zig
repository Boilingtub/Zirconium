const std = @import("std");
pub const zstbi = @import("zstbi");

pub fn init(allocator: std.mem.Allocator) void {
    zstbi.init(allocator);
}

pub fn deinit() void {
    zstbi.deinit();
}

pub fn load(path: [:0]const u8, force_num_components: u32) !zstbi.Image {
    return try zstbi.Image.loadFromFile(path, force_num_components); 
}

pub export fn Force_image_MipMap_compatible(image: *zstbi.Image) void {
    const square_size = round_pow_2_up(@max(image.width, image.height));
    image.* = image.*.resize(square_size,square_size);
}
pub export fn round_pow_2_down(a:u32) u32 {
    var x = a;
    x |= x>>1;
    x |= x>>2;
    x |= x>>4;
    x |= x>>8;
    x |= x>>16;
    x = (x>>1) + 1;
    return x;
}
pub export fn round_pow_2_up(a:u32) u32 {
    var x = a;
    x -=1;   
    x |= x>>1;
    x |= x>>2;
    x |= x>>4;
    x |= x>>8;
    x |= x>>16;
    x+=1;
    return x;
}

