//! Syscall ABI shared with the userland libc (identical to C-OS).
//!
//! Convention: `int 0x80`, number in eax, arguments in ebx/ecx/edx, result in eax.
//! Errors are returned as negative errno values.

pub const read = 0;
pub const write = 1;
pub const open = 2;
pub const close = 3;
pub const lseek = 8;
pub const execve = 11;
pub const get_proc_uptime = 12;
pub const sleep = 13;
pub const exit = 40;
pub const map_fb = 42;
pub const brk = 45;

pub const ESRCH: i32 = 3;
pub const ENOENT: i32 = 2;
pub const EBADF: i32 = 9;
pub const ENOMEM: i32 = 12;
pub const EFAULT: i32 = 14;
pub const EISDIR: i32 = 21;
pub const EINVAL: i32 = 22;
pub const EMFILE: i32 = 24;
pub const ESPIPE: i32 = 29;
pub const ENOSYS: i32 = 38;

pub const std_in_file_no = 0;
pub const std_out_file_no = 1;

/// Maps a kernel error onto the negative errno the userland expects.
pub fn errnoOf(err: anyerror) i32 {
    return -switch (err) {
        error.FileNotFound => ENOENT,
        error.IsDirectory => EISDIR,
        error.BadFileDescriptor => EBADF,
        error.InvalidSeek => EINVAL,
        error.QueueFull => EINVAL,
        error.Unsupported => ESPIPE,
        error.ReadOnlyFilesystem => EBADF,
        error.OutOfMemory => ENOMEM,
        else => EINVAL,
    };
}
