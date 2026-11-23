const std = @import("std");


pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // 32-bit freestanding x86, no libc/OS — the Zig equivalent of `-m32`
    // plus a bare-metal target.
    const Feature = std.Target.x86.Feature;

    var disabled = std.Target.Cpu.Feature.Set.empty;
    disabled.addFeature(@intFromEnum(Feature.mmx));
    disabled.addFeature(@intFromEnum(Feature.sse));
    disabled.addFeature(@intFromEnum(Feature.sse2));
    disabled.addFeature(@intFromEnum(Feature.avx));
    disabled.addFeature(@intFromEnum(Feature.avx2));

    var enabled = std.Target.Cpu.Feature.Set.empty;
    enabled.addFeature(@intFromEnum(Feature.soft_float));

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = disabled,
        .cpu_features_add = enabled,
    });

    // Root module with no zig root source file — this is a pure C/asm/zig
    // object-link executable, same as `ld`-ing a pile of .o files in the
    // Makefile. As you migrate files, you can optionally add a real
    // src/main.zig later and point root_source_file at it.
    const exe = b.addExecutable(.{
        .name = "kernel.bin",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    // Equivalent of `-T linker.ld`. Let the script's ENTRY() decide the
    // entry point instead of Zig hunting for `_start`.
    exe.setLinkerScript(b.path("linker.ld"));
    exe.entry = .disabled;
    // Same include path as your CFLAGS `-I`. Adjust if your `include/`
    // dir lives somewhere other than next to kernel/.
    exe.root_module.addIncludePath(b.path("include"));

    const c_flags = &[_][]const u8{
        "-g",
        "-m32",
        "-ffreestanding",
        "-fno-stack-protector",
        "-fno-builtin",
        "-fno-pic",
        "-fno-pie",
        "-mno-sse",
        "-mno-sse2",
        "-mno-mmx",
    };

    var boot_asm_path: ?[]const u8 = null;
    const boot_marker = "arch" ++ std.fs.path.sep_str ++ "x86" ++ std.fs.path.sep_str ++ "boot.s";

    // We discover sources the same way the Makefile did: shell out to
    // `find`. This sidesteps Zig's std.Io filesystem APIs (which are
    // currently being reworked upstream and churn frequently on dev
    // builds) in favor of std.Build's stable b.run() helper.
    const collect = struct {
        fn run(bb: *std.Build, pattern: []const u8) std.ArrayList([]const u8) {
            var list: std.ArrayList([]const u8) = .empty;
            const output = bb.run(&[_][]const u8{ "find", "kernel", "-name", pattern });
            var lines = std.mem.splitScalar(u8, output, '\n');
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (trimmed.len == 0) continue;
                list.append(bb.allocator, trimmed) catch @panic("OOM");
            }
            return list;
        }
    }.run;

    const c_files = collect(b, "*.c");
    const asm_files_all = collect(b, "*.s");

    var asm_files: std.ArrayList([]const u8) = .empty;
    for (asm_files_all.items) |path| {
        if (std.mem.endsWith(u8, path, boot_marker)) {
            boot_asm_path = path;
        } else {
            asm_files.append(b.allocator, path) catch @panic("OOM");
        }
    }

    // Turn a relative path like "kernel/arch/boot.s" into a flat,
    // collision-free filename like "kernel_arch_boot.s" (mirrors the
    // Makefile's obj/asm/<mirrored-tree>.o trick, just flattened).
    const sanitizePath = struct {
        fn run(allocator: std.mem.Allocator, path: []const u8) []const u8 {
            const buf = allocator.dupe(u8, path) catch @panic("OOM");
            for (buf) |*ch| {
                if (ch.* == '/' or ch.* == '\\' or ch.* == '.') ch.* = '_';
            }
            return buf;
        }
    }.run;

    // ── Helper: run nasm on one file, return the produced object path ──
    const assembleWithNasm = struct {
        fn run(bb: *std.Build, src_path: []const u8) std.Build.LazyPath {
            const nasm = bb.addSystemCommand(&[_][]const u8{ "nasm", "-f", "elf32" });
            nasm.addFileArg(bb.path(src_path));
            nasm.addArg("-o");

            const safe_name = bb.fmt("{s}.o", .{sanitizePath(bb.allocator, src_path)});
            return nasm.addOutputFileArg(safe_name);
        }
    }.run;

    // ── boot.s must be linked first (kernel entry point) ───────────────
    if (boot_asm_path) |bp| {
        exe.root_module.addObjectFile(assembleWithNasm(b, bp));
    } else {
        std.debug.print(
            "warning: kernel/arch/boot.s not found; boot object will not be forced first in link order\n",
            .{},
        );
    }

    // ── Remaining assembly files ─────────────────────────────────────────
    for (asm_files.items) |path| {
        exe.root_module.addObjectFile(assembleWithNasm(b, path));
    }

    // ── C files: one addCSourceFiles call, same shared CFLAGS as the
    //    Makefile applied to every .c file ──────────────────────────────
    if (c_files.items.len > 0) {
        exe.root_module.addCSourceFiles(.{
            .root = b.path("."),
            .files = c_files.items,
            .flags = c_flags,
        });
    }

    // ── Zig files: each compiled as its own freestanding object and
    //    linked in, same granularity as a .c -> .o in the Makefile ─────
    const zig_obj = b.addObject(.{
        .name = "kernel_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("kernel/kernel.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            .stack_protector = false,
        }),
    });

    exe.root_module.addObject(zig_obj);

    b.installArtifact(exe);

    // ── run / debug / clean steps, mirroring the Makefile ───────────────
    const build_root = b.build_root.path orelse ".";

    const move_kernel = b.addSystemCommand(&[_][]const u8{"cp"});
    move_kernel.addArtifactArg(exe);
    move_kernel.addArg(b.pathJoin(&[_][]const u8{ build_root, "DOOMOS/boot/kernel" }));

    const make_iso = b.addSystemCommand(&[_][]const u8{"grub-mkrescue"});
    make_iso.addArg("-o");
    make_iso.addArg(b.pathJoin(&[_][]const u8{ build_root, "DOOMOS.iso" }));
    make_iso.addArg(b.pathJoin(&[_][]const u8{ build_root, "DOOMOS" }));
    make_iso.step.dependOn(&move_kernel.step);

    const run_qemu = b.addSystemCommand(&[_][]const u8{"qemu-system-i386"});
    run_qemu.addArg("-cdrom");
    run_qemu.addArg(b.pathJoin(&[_][]const u8{ build_root, "DOOMOS.iso" }));
    run_qemu.addArgs(&[_][]const u8{ "-boot", "d", "-serial", "stdio" });
    run_qemu.step.dependOn(&make_iso.step);

    const run_step = b.step("run", "Build kernel, make ISO, boot in QEMU");
    run_step.dependOn(&run_qemu.step);

    const debug_qemu = b.addSystemCommand(&[_][]const u8{"qemu-system-i386"});
    debug_qemu.addArg("-cdrom");
    debug_qemu.addArg(b.pathJoin(&[_][]const u8{ build_root, "DOOMOS.iso" }));
    debug_qemu.addArgs(&[_][]const u8{
        "-boot",      "d",
        "-d",         "int,cpu_reset",
        "-no-reboot", "-no-shutdown",
        "-s",         "-S",
    });
    debug_qemu.step.dependOn(&make_iso.step);

    const debug_step = b.step("debug", "Build kernel, make ISO, boot in QEMU paused for GDB");
    debug_step.dependOn(&debug_qemu.step);

    const clean_cmd = b.addSystemCommand(&[_][]const u8{
        "rm",                                                   "-rf", "zig-out", ".zig-cache", "zig-cache",
        b.pathJoin(&[_][]const u8{ build_root, "DOOMOS.iso" }),
    });
    const clean_step = b.step("clean", "Remove build artifacts");
    clean_step.dependOn(&clean_cmd.step);
}
