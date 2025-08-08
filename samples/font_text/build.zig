const std = @import("std");
    
pub fn build(b: *std.Build, 
             target: anytype, 
             optimize: anytype) 
*std.Build.Step.Compile {
    const cwd_path = "samples/font_text";
    const src_path = cwd_path ++ "/src/";
    const content_dir = "/content";

    const lib_mod = b.createModule(.{
        .root_source_file = b.path(src_path ++ "root.zig"),
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
    const gpu = b.addModule("gpu", .{
        .root_source_file = b.path(src_path ++ "gpu.zig")
    });
    lib.root_module.addImport("gpu", gpu);

    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    gpu.addImport("zglfw", zglfw.module("root"));
    lib.linkLibrary(zglfw.artifact("glfw"));

    @import("zgpu").addLibraryPathsTo(lib);
    const zgpu = b.dependency("zgpu", .{
        .target = target,
    });
    gpu.addImport("zgpu", zgpu.module("root"));
    gpu.linkLibrary(zgpu.artifact("zdawn"));

    const zmath = b.dependency("zmath", .{
        .target = target,
    });
    gpu.addImport("zmath", zmath.module("root")); 
    
    const pipelines = b.addModule("pipelines",.{
        .root_source_file = b.path(src_path ++ "pipelines.zig")
    });
    pipelines.addImport("gpu", gpu);

    //mesh.zig
    const mesh = b.addModule("mesh", .{
        .root_source_file = b.path(src_path ++ "mesh.zig")
    });
    const zgltf = b.addModule("zgltf", .{
        .root_source_file = b.path("./libs/zgltf/main.zig")
    });
    mesh.addImport("zgltf", zgltf);
    const zobj = b.addModule("zobj", .{
        .root_source_file = b.path("./libs/zobj/src/main.zig")
    });
    mesh.addImport("zobj", zobj);
    gpu.addImport("mesh", mesh);

    //image.zig
    const zstbi = b.dependency("zstbi", .{});
    gpu.addImport("zstbi", zstbi.module("root"));
    
    //TrueType.zig 
    const text = b.addModule("text", .{
        .root_source_file = b.path(src_path ++ "text.zig"),
    });
    const TrueType = b.addModule("TrueType", .{
        .root_source_file = b.path("./libs/TrueType/TrueType.zig"),
    });
    text.addImport("TrueType", TrueType);
    gpu.addImport("text", text);


    //camera.zig 
    const camera = b.addModule("camera", .{
        .root_source_file = b.path(src_path ++ "camera.zig")
    });
    camera.addImport("zmath",zmath.module("root"));
    gpu.addImport("camera", camera);

    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path(src_path ++ "main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("Zirconium", lib_mod);

    const exe = b.addExecutable(.{
        .name = "Zirconium",
        .root_module = exe_mod,
    });

    const content_path = b.pathJoin(&.{cwd_path, content_dir});
    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options",exe_options);
    exe_options.addOption([]const u8, "content_dir", content_path);

    const install_content_step = b.addInstallDirectory(.{
        .source_dir = b.path(content_path),
        .install_dir = .{ .custom = "" },
        .install_subdir = b.pathJoin(&.{ "bin", content_dir }),
    });
    exe.step.dependOn(&install_content_step.step);

    return exe;
}
