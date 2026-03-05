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

    // Example executable
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/storefront.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("ztree", lib_mod);
    const example = b.addExecutable(.{
        .name = "storefront",
        .root_module = example_mod,
    });
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run the storefront example");
    example_step.dependOn(&run_example.step);

    // Profile example
    const profile_mod = b.createModule(.{
        .root_source_file = b.path("examples/profile.zig"),
        .target = target,
        .optimize = optimize,
    });
    profile_mod.addImport("ztree", lib_mod);
    const profile = b.addExecutable(.{
        .name = "profile",
        .root_module = profile_mod,
    });
    b.installArtifact(profile);
    const run_profile = b.addRunArtifact(profile);
    const profile_step = b.step("profile", "Run the profile example");
    profile_step.dependOn(&run_profile.step);

    // Tests — run tests from each source module
    const test_step = b.step("test", "Run unit tests");

    const test_files = [_][]const u8{
        "src/node.zig",
        "src/create.zig",
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
