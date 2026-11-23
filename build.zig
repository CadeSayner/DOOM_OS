const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const program = b.option([]const u8, "program", "Initrd executable to start (default: doom.elf)") orelse "doom.elf";

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
    const options = b.addOptions();
    options.addOption([]const u8, "program", program);
    zig_obj.root_module.addOptions("build_options", options);

    exe.root_module.addObject(zig_obj);

    b.installArtifact(exe);

    const user_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = disabled,
    });
    const user_optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const libc = b.addLibrary(.{
        .name = "doomc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("userspace/libc/libc.zig"),
            .target = user_target,
            .optimize = user_optimize,
            .single_threaded = true,
            .stack_protector = false,
        }),
    });
    b.installArtifact(libc);
    const crt0 = assembleWithNasm(b, "userspace/libc/crt0.s");
    const user_c_flags = &[_][]const u8{
        "-m32",         "-O2",      "-ffreestanding", "-nostdinc", "-fno-stack-protector",
        "-fno-builtin", "-fno-pic", "-fno-pie",       "-mno-sse",  "-mno-sse2",
        "-mno-mmx",
    };
    const doom_sources = &[_][]const u8{
        "dummy.c",    "am_map.c",     "doomdef.c",     "doomstat.c",         "dstrings.c", "d_event.c",  "d_items.c",
        "d_iwad.c",   "d_loop.c",     "d_main.c",      "d_mode.c",           "d_net.c",    "f_finale.c", "f_wipe.c",
        "g_game.c",   "hu_lib.c",     "hu_stuff.c",    "info.c",             "i_cdmus.c",  "i_endoom.c", "i_joystick.c",
        "i_scale.c",  "i_sound.c",    "i_system.c",    "i_timer.c",          "memio.c",    "m_argv.c",   "m_bbox.c",
        "m_cheat.c",  "m_config.c",   "m_controls.c",  "m_fixed.c",          "m_menu.c",   "m_misc.c",   "m_random.c",
        "p_ceilng.c", "p_doors.c",    "p_enemy.c",     "p_floor.c",          "p_inter.c",  "p_lights.c", "p_map.c",
        "p_maputl.c", "p_mobj.c",     "p_plats.c",     "p_pspr.c",           "p_saveg.c",  "p_setup.c",  "p_sight.c",
        "p_spec.c",   "p_switch.c",   "p_telept.c",    "p_tick.c",           "p_user.c",   "r_bsp.c",    "r_data.c",
        "r_draw.c",   "r_main.c",     "r_plane.c",     "r_segs.c",           "r_sky.c",    "r_things.c", "sha1.c",
        "sounds.c",   "statdump.c",   "st_lib.c",      "st_stuff.c",         "s_sound.c",  "tables.c",   "v_video.c",
        "wi_stuff.c", "w_checksum.c", "w_file.c",      "w_main.c",           "w_wad.c",    "z_zone.c",   "w_file_stdc.c",
        "i_input.c",  "i_video.c",    "doomgeneric.c", "doomgeneric_c-os.c",
    };
    const doom = addUserProgram(b, "doom", user_target, user_optimize, crt0, libc, null);
    doom.root_module.addCMacro("DOOMGENERIC_RGBA", "1");
    doom.root_module.addCSourceFiles(.{ .root = b.path("userspace/doom"), .files = doom_sources, .flags = user_c_flags });
    const libc_tests = addUserProgram(b, "libc-tests", user_target, user_optimize, crt0, libc, null);
    libc_tests.root_module.addCSourceFile(.{ .file = b.path("userspace/libc/tests.c"), .flags = user_c_flags });

    var programs: std.ArrayList(UserProgram) = .empty;
    programs.append(b.allocator, .{ .exe = doom, .filename = "doom.elf" }) catch @panic("OOM");
    programs.append(b.allocator, .{ .exe = libc_tests, .filename = "libc-tests.elf" }) catch @panic("OOM");
    const sources = b.run(&.{ "find", "userspace", "-mindepth", "2", "-maxdepth", "2", "-type", "f", "(", "-name", "main.zig", "-o", "-name", "main.c", ")" });
    var lines = std.mem.splitScalar(u8, sources, '\n');
    while (lines.next()) |source| {
        if (source.len == 0) continue;
        const directory = std.fs.path.dirname(source) orelse @panic("Invalid user program path");
        const name = std.fs.path.basename(directory);
        for (name) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_')
                std.debug.panic("Invalid user program directory name: {s}", .{name});
        }
        const filename = b.fmt("{s}.elf", .{name});
        for (programs.items) |existing| {
            if (std.mem.eql(u8, existing.filename, filename))
                std.debug.panic("Duplicate user program: {s}", .{filename});
        }
        const is_zig = std.mem.endsWith(u8, source, ".zig");
        const user_exe = addUserProgram(b, name, user_target, user_optimize, crt0, libc, if (is_zig) source else null);
        if (!is_zig) user_exe.root_module.addCSourceFile(.{ .file = b.path(source), .flags = user_c_flags });
        programs.append(b.allocator, .{ .exe = user_exe, .filename = filename }) catch @panic("OOM");
    }
    std.mem.sort(UserProgram, programs.items, {}, struct {
        fn lessThan(_: void, a: UserProgram, c: UserProgram) bool {
            return std.mem.lessThan(u8, a.filename, c.filename);
        }
    }.lessThan);

    const wad = b.addSystemCommand(&.{ "tar", "-xOf" });
    wad.addFileArg(b.path("DOOMOS/boot/init_rd.tar"));
    wad.addArg("doom1.wad");
    const initrd_files = b.addWriteFiles();
    _ = initrd_files.addCopyFile(wad.captureStdOut(.{}), "doom1.wad");
    const make_initrd = b.addSystemCommand(&.{ "tar", "-cf" });
    const initrd = make_initrd.addOutputFileArg("init_rd.tar");
    make_initrd.addArg("-C");
    make_initrd.addDirectoryArg(initrd_files.getDirectory());
    for (programs.items) |entry| {
        _ = initrd_files.addCopyFile(entry.exe.getEmittedBin(), entry.filename);
        make_initrd.addArg(entry.filename);
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(entry.exe.getEmittedBin(), .bin, entry.filename).step);
    }
    make_initrd.addArg("doom1.wad");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(initrd, .bin, "init_rd.tar").step);

    // ── run / debug / clean ────────────────────────────────────────────
    const build_root = b.build_root.path orelse ".";
    const iso_files = b.addWriteFiles();
    _ = iso_files.addCopyFile(exe.getEmittedBin(), "boot/kernel");
    _ = iso_files.addCopyFile(initrd, "boot/init_rd.tar");
    _ = iso_files.addCopyFile(b.path("DOOMOS/boot/grub/grub.cfg"), "boot/grub/grub.cfg");
    const make_iso = b.addSystemCommand(&[_][]const u8{"grub-mkrescue"});
    make_iso.addArg("-o");
    make_iso.addArg(b.pathJoin(&[_][]const u8{ build_root, "DOOMOS.iso" }));
    make_iso.addDirectoryArg(iso_files.getDirectory());
    const iso_step = b.step("iso", "Build the bootable ISO without starting QEMU");
    iso_step.dependOn(&make_iso.step);
    make_iso.step.dependOn(b.getInstallStep());

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

const UserProgram = struct {
    exe: *std.Build.Step.Compile,
    filename: []const u8,
};

fn addUserProgram(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    crt0: std.Build.LazyPath,
    libc: *std.Build.Step.Compile,
    zig_source: ?[]const u8,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = if (zig_source) |path| b.path(path) else null,
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .stack_protector = false,
    });
    module.addIncludePath(b.path("userspace/libc/include"));
    module.addObjectFile(crt0);
    module.linkLibrary(libc);
    if (zig_source != null) {
        module.addImport("doom_os", b.createModule(.{
            .root_source_file = b.path("userspace/zig/os.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
        }));
    }
    const result = b.addExecutable(.{ .name = name, .root_module = module });
    result.entry = .{ .symbol_name = "_start" };
    return result;
}
