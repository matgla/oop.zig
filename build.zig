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

    const mod_tests = b.addModule("tests", .{
        .root_source_file = b.path("tests/tests.zig"),
        .optimize = optimize,
        .target = target,
    });

    const exe_tests = b.addTest(.{
        .root_module = mod_tests,
        .use_llvm = true,
    });
    exe_tests.root_module.addImport("interface", mod);

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    b.installArtifact(exe_tests);

    if (enable_examples) {
        var iterable_dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
        defer iterable_dir.close();
        var it = iterable_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file) {
                if (std.mem.endsWith(u8, entry.name, ".zig")) {
                    const example_module = b.addModule(
                        entry.name[0 .. entry.name.len - 4],
                        .{
                            .root_source_file = b.path(b.pathJoin(&.{ "examples", entry.name })),
                            .optimize = optimize,
                            .target = target,
                        },
                    );
                    const example_exe = b.addExecutable(
                        .{
                            .name = entry.name[0 .. entry.name.len - 4],
                            .root_module = example_module,
                        },
                    );
                    example_exe.root_module.addImport("interface", mod);
                    b.installArtifact(example_exe);
                }
            }
        }
    }

    const lib = b.addLibrary(.{
        .name = "oop",
        .root_module = mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Install documentation");
    docs_step.dependOn(&install_docs.step);
}
