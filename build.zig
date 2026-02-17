const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const lib_mod = b.addModule("ztree", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Library artifact (for linking)
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ztree",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // Tests — run tests from each source module
    const test_step = b.step("test", "Run unit tests");

    const test_files = [_][]const u8{
        "src/node.zig",
        "src/constructors.zig",
    };

    for (test_files) |test_file| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });

        const t = b.addTest(.{
            .root_module = test_mod,
        });
        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);
    }
}
