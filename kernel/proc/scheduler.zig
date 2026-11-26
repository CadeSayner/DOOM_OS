const std = @import("std");
const Queue = @import("../lib/queue.zig").Queue;
const Process = @import("../proc/process.zig").Process;

const Gdt = @import("../arch/x86/gdt.zig");
const Constants = @import("../lib/constants.zig");
const PageDirectory = @import("../proc/process.zig").PageDirectory;
const Context = @import("../context.zig");

extern fn irq_save() u32;
extern fn irq_restore(flags: u32) void;
extern fn load_page_table(page_dir_phys: u32) void;
extern fn switch_context(old_esp: *u32, new_esp: u32) callconv(.c) void;
extern var initial_page_dir: [1024]u32;
extern var stack_top: [*]u32;
extern var stack_bottom: [*]u32;

const run_queue_max_capacity = 1024;

const RunQueue = Queue(run_queue_max_capacity, *Process);
const ReapQueue = Queue(run_queue_max_capacity, *Process);

// process representing the boot that jsut chills until something eventually happens
var boot_process: Process = .{
    .pid = 0,
    .entry_point = 0,
    .status = .Running,
    .page_directory = undefined,
    .saved_esp = 0,
    .kernel_stack_base = undefined,
    .kernel_stack_top = undefined,
    .ticks_allocated = 10,
    .ticks_remaining = 10,
    .allocator = undefined,
    .sbrk = 0,
    .brk = 0,
    .start_time_ms = 0,
    .file_descriptors = .{null} ** 32,
};

pub const Scheduler = struct {
    run_queue: RunQueue = .{},
    reap_queue: ReapQueue = .{},
    executing_process: ?*Process = null,

    pub fn initialiseBootProcess() void {
        boot_process.page_directory = @ptrCast(&initial_page_dir);
        boot_process.kernel_stack_base = @intFromPtr(&stack_bottom);
        boot_process.kernel_stack_top = @intFromPtr(&stack_top);
        boot_process.allocator = Context.ctx.allocator;
    }

    pub fn addProcess(self: *Scheduler, process: *Process) !void {
        const flags = irq_save();
        try self.run_queue.enqueue(process);
        irq_restore(flags);
    }

    // Schedule a new process to run on the CPU
    pub fn schedule(self: *Scheduler) void {
        const flags = irq_save();

        const old_process = self.executing_process orelse &boot_process;

        if(self.run_queue.len == 0 and old_process.status == .Running){
            // just keep the old process running
            irq_restore(flags);
            return;
        }

        var process_iterator = self.run_queue.dequeue() orelse &boot_process;
        while (process_iterator.status == .Terminated) {
            // this will pop the old process off the queue which was the only active reference to it so it needs to be placed on some
            // kind of reaper queue that is registered maybe here actually
            std.log.info("Encountered terminated process, popping", .{});
            process_iterator = self.run_queue.dequeue() orelse &boot_process;
        }

        const new_process = process_iterator;

        self.executing_process = new_process;

        new_process.status = .Running;
        if (old_process.status != .Waiting and old_process.status != .Terminated and old_process != &boot_process) {
            // we add to the end of the queue again round robin style baby and put back to ready status
            old_process.status = .Ready;
            self.run_queue.enqueue(old_process) catch @panic("Failed to enqueue process to run queue.");
        }

        // set the tss to that processes stack_top
        Gdt.setKernelStack(new_process.kernel_stack_top);

        //load the page table of that process
        load_page_table(Constants.virtToPhys(@intFromPtr(new_process.page_directory)));

        // switch over to that process
        switch_context(&old_process.saved_esp, new_process.saved_esp);

        irq_restore(flags);
    }
};