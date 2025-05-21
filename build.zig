const std = @import("std");
    
const sample = "Camera";

pub fn build(b: *std.Build) void {
    const cwd_path = "src/" ++ sample ++ "/";
    const content_dir = "content/";
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib_mod = b.createModule(.{
        .root_source_file = b.path(cwd_path ++ "root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Zirconium",
        .root_module = lib_mod,
    });

    if (target.result.os.tag == .linux) {
        if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
            lib_mod.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
        }
    }

    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    lib.root_module.addImport("zglfw", zglfw.module("root"));
    lib.linkLibrary(zglfw.artifact("glfw"));

    @import("zgpu").addLibraryPathsTo(lib);
    const zgpu = b.dependency("zgpu", .{
        .target = target,
    });
    lib.root_module.addImport("zgpu", zgpu.module("root"));
    lib.linkLibrary(zgpu.artifact("zdawn"));

    const zmath = b.dependency("zmath", .{
        .target = target,
    });
    lib.root_module.addImport("zmath", zmath.module("root"));
    

    //model.zig
    const model = b.addModule("model", .{
        .root_source_file = b.path(cwd_path ++ "model.zig")
    });
    const zgltf = b.addModule("zgltf", .{
        .root_source_file = b.path("libs/zgltf/main.zig")
    });
    model.addImport("zgltf", zgltf);
    lib.root_module.addImport("model", model);

    //image.zig
    const image = b.addModule("image", .{
        .root_source_file = b.path(cwd_path ++ "image.zig")
    });
    const zstbi = b.dependency("zstbi", .{});
    image.addImport("zstbi", zstbi.module("root"));
    lib.root_module.addImport("image", image);

    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path(cwd_path ++ "main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("Zirconium", lib_mod);

    const exe = b.addExecutable(.{
        .name = "Zirconium",
        .root_module = exe_mod,
    });

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options",exe_options);
    exe_options.addOption([]const u8, "content_dir", content_dir);

    const content_path = b.pathJoin(&.{cwd_path, content_dir});
    const install_content_step = b.addInstallDirectory(.{
        .source_dir = b.path(content_path),
        .install_dir = .{ .custom = "" },
        .install_subdir = b.pathJoin(&.{ "bin", content_dir }),
    });
    exe.step.dependOn(&install_content_step.step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
