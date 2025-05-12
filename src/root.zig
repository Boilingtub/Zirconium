const std = @import("std");

pub export const version = "0.0.1";

pub export fn print_version() void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    stdout.print("Zirconium {s} Loaded", .{version}) catch unreachable;
    bw.flush() catch unreachable;
}
