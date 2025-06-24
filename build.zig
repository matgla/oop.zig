const std = @import("std");

pub fn build(b: *std.Build) !void {
    const enable_examples = b.option(bool, "examples", "Enable building examples") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("interface", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("tests/tests.zig"),
    });
    exe_tests.root_module.addImport("interface", mod);

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    if (enable_examples) {
        var iterable_dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
        defer iterable_dir.close();
        var it = iterable_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file) {
                if (std.mem.endsWith(u8, entry.name, ".zig")) {
                    const example_exe = b.addExecutable(
                        .{
                            .name = entry.name[0 .. entry.name.len - 4],
                            .root_source_file = b.path(b.pathJoin(&.{ "examples", entry.name })),
                            .optimize = optimize,
                            .target = target,
                        },
                    );
                    example_exe.root_module.addImport("interface", mod);
                    b.installArtifact(example_exe);
                }
            }
        }
    }
}
