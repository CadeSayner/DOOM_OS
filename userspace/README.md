# User programs

`zig build` builds the kernel, static Zig libc, Doom, and every program in
`user_programs/<name>/main.zig` or `user_programs/<name>/main.c`. It puts the
executables, `kernel.bin`, and the generated `init_rd.tar` in `zig-out/bin/`;
the library is `zig-out/lib/libdoomc.a`. The initrd contains all the programs
and the existing `doom1.wad`. The original boot tar is not modified.

Run Doom with `zig build run`. To start another executable from the same
initrd, use for example:

```
zig build run -Dprogram=zig-hello.elf
zig build run -Dprogram=hello.elf
zig build run -Dprogram=zig-tests.elf
zig build run -Dprogram=libc-tests.elf
```

`zig build iso` builds `DOOMOS.iso` without running QEMU. The same `-Dprogram`
option works with `zig build`, `iso`, `run`, and `debug`. The kernel reports
an error if the requested executable is missing or invalid.

To add a program, create `user_programs/<name>/main.zig` or `main.c` and
rebuild. The directory name becomes `<name>.elf`; use letters, digits,
hyphens, and underscores. A directory cannot contain both entry files.
The loader currently starts one process, and its startup code supplies a
placeholder `argv[0]` rather than command-line arguments.

Zig programs export a C-callable `main` returning `c_int`, as in
`zig-hello/main.zig`. Import `doom_os` and pass `doom_os.allocator` to Zig
containers and formatting functions. It is a `std.mem.Allocator` backed by
this project's `malloc`/`free`, including support for over-aligned allocations.
Use `doom_os.writeAll(1, bytes)` for output; stdout and stderr go to the
serial console. C programs can use the headers in `libc/include`.

The target is 32-bit freestanding x86. Pure Zig standard-library features such
as collections, formatting, and algorithms work, but hosted OS features such as
the standard filesystem, networking, threads, and process APIs do not
automatically work on this kernel. User programs are built in ReleaseFast
without SIMD. The libc is a small C-OS-compatible subset, not a complete ISO C
library: its formatter supports `%s`, `%c`, `%d`, `%i`, `%u`, `%x`, `%X`,
`%p`, and `%%`, with basic width and precision; unsupported formats fail.
The initrd filesystem is read-only, there is no scheduler, and a process exit
halts the system.

Doom controls include WASD to move/turn, F or J to fire, and E, Space, or U
to use doors. Escape opens the menu. Start a new game from the menu rather
than the automatic demo.

Building requires Zig 0.16, NASM, `find`, and `tar`; ISO and run steps also
require `grub-mkrescue` and QEMU. Doom sources are distributed under their
included GPL license.
