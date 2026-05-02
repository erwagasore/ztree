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

    // Tests — run the package root, which imports all module tests.
    const test_step = b.step("test", "Run unit tests");
    addTestRun(b, test_step, target, optimize);

    const check_step = b.step("check", "Run checks");
    check_step.dependOn(test_step);

    const test_all_step = b.step("test-all", "Run unit tests in Debug, ReleaseSafe, and ReleaseFast");
    const modes = [_]std.builtin.OptimizeMode{ .Debug, .ReleaseSafe, .ReleaseFast };
    for (modes) |mode| {
        addTestRun(b, test_all_step, target, mode);
    }
}

fn addTestRun(
    b: *std.Build,
    step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const t = b.addTest(.{
        .root_module = test_mod,
    });
    const run_t = b.addRunArtifact(t);
    step.dependOn(&run_t.step);
}
